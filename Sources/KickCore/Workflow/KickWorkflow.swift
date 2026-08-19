import Combine
import Foundation
import OSLog

@MainActor
public final class KickWorkflow: ObservableObject {
    private static let logger = Logger(
        subsystem: "co.nousworks.kick",
        category: "workflow"
    )

    @Published public private(set) var disks: [ExternalDisk] = []
    @Published public private(set) var selectedDiskID: ExternalDisk.ID?
    @Published public private(set) var blockers: [BlockingProcess] = []
    @Published public private(set) var phase = EjectionPhase.ready
    @Published public private(set) var releasePlans: [ProcessReleasePlan] = []
    @Published public private(set) var stopPlans: [ProcessStopPlan] = []
    @Published public private(set) var releaseAttempts: [ReleaseAttempt] = []

    private let volumeProvider: VolumeProviding
    private let ejector: DiskEjecting
    private let diagnoser: BlockerDiagnosing
    private let releaser: ProcessReleasing
    private let stopper: ProcessStopping?
    private let settleDelayNanoseconds: UInt64
    private let releaseTimeoutNanoseconds: UInt64
    private var activeOperationID: UUID?
    private var refreshGeneration: UInt64 = 0

    public init(
        volumeProvider: VolumeProviding,
        ejector: DiskEjecting,
        diagnoser: BlockerDiagnosing,
        releaser: ProcessReleasing,
        stopper: ProcessStopping? = nil,
        settleDelayNanoseconds: UInt64 = 1_200_000_000,
        releaseTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.volumeProvider = volumeProvider
        self.ejector = ejector
        self.diagnoser = diagnoser
        self.releaser = releaser
        self.stopper = stopper
        self.settleDelayNanoseconds = settleDelayNanoseconds
        self.releaseTimeoutNanoseconds = releaseTimeoutNanoseconds
    }

    public var selectedDisk: ExternalDisk? {
        guard let selectedDiskID else { return nil }
        return disks.first { $0.id == selectedDiskID }
    }

    public func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        Self.logger.debug("Disk refresh started")

        do {
            let current = try await volumeProvider.mountedExternalDisks()
            guard generation == refreshGeneration else { return }
            guard !phase.isBusy || activeOperationID == nil else {
                Self.logger.debug("Disk refresh ignored during an active operation")
                return
            }
            if case .ejected = phase {
                Self.logger.debug("Disk refresh deferred on the success screen")
                return
            }
            disks = current
            Self.logger.info("Disk refresh completed count=\(current.count, privacy: .public)")

            if let selectedDiskID, current.contains(where: { $0.id == selectedDiskID }) {
                return
            }

            activeOperationID = nil
            selectedDiskID = current.first?.id
            blockers = []
            releasePlans = []
            stopPlans = []
            releaseAttempts = []
            phase = .ready
        } catch {
            guard generation == refreshGeneration, !phase.isBusy else { return }
            if case .ejected = phase {
                Self.logger.debug("Disk refresh failure ignored on the success screen")
                return
            }
            let nsError = error as NSError
            Self.logger.error(
                "Disk refresh failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            activeOperationID = nil
            disks = []
            selectedDiskID = nil
            blockers = []
            releasePlans = []
            stopPlans = []
            releaseAttempts = []
            phase = .failed(
                title: "Could not check disks",
                message: readableMessage(for: error),
                recovery: .refreshDisks
            )
        }
    }

    public func selectDisk(id: ExternalDisk.ID) {
        guard phase.allowsDiskSelection,
              disks.contains(where: { $0.id == id }),
              id != selectedDiskID else { return }
        invalidatePendingRefreshes()
        activeOperationID = nil
        selectedDiskID = id
        blockers = []
        releasePlans = []
        stopPlans = []
        releaseAttempts = []
        phase = .ready
    }

    public func attemptEject() async {
        guard let disk = selectedDisk, !phase.isBusy else { return }

        Self.logger.info("Eject started")
        invalidatePendingRefreshes()
        let operationID = UUID()
        activeOperationID = operationID
        blockers = []
        releasePlans = []
        stopPlans = []
        releaseAttempts = []
        phase = .ejecting

        do {
            try await ejector.eject(disk)
            guard isCurrent(operationID, diskID: disk.id) else { return }
            Self.logger.info("Eject completed")
            finishSuccess(for: disk)
        } catch {
            let ejectMessage = readableMessage(for: error)
            guard isCurrent(operationID, diskID: disk.id) else { return }

            guard let failure = error as? EjectionFailure, failure.kind == .busy else {
                logEjectionFailure(error)
                activeOperationID = nil
                if let failure = error as? EjectionFailure,
                   failure.kind == .identityChanged {
                    removeStaleDisk(disk)
                }
                phase = .failed(
                    title: "Could not eject",
                    message: ejectMessage,
                    recovery: (error as? EjectionFailure)?.kind == .identityChanged
                        ? .refreshDisks
                        : .retryEject
                )
                return
            }
            logEjectionFailure(failure)
            phase = .diagnosing

            do {
                let found = try await diagnoseBlockers(
                    on: disk,
                    dissentingProcessID: failure.dissentingProcessID
                )
                guard isCurrent(operationID, diskID: disk.id) else { return }
                Self.logger.info("Diagnosis completed blockers=\(found.count, privacy: .public)")

                if found.isEmpty {
                    activeOperationID = nil
                    phase = .failed(title: "Could not eject", message: ejectMessage)
                } else {
                    enterBlockedState(with: found)
                }
            } catch {
                guard isCurrent(operationID, diskID: disk.id) else { return }
                activeOperationID = nil
                let nsError = error as NSError
                Self.logger.error(
                    "Diagnosis failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                )
                phase = .failed(
                    title: "Could not inspect this disk",
                    message: "\(ejectMessage) \(readableMessage(for: error))"
                )
            }
        }
    }

    public func performSafeKick() async {
        guard let disk = selectedDisk, phase == .blocked else { return }

        let approvals = frozenReleaseApprovals()
        let eligibleCount = approvals.filter { $0.plan.strategy == .quitApplication }.count
        Self.logger.info(
            "Release review confirmed total=\(approvals.count, privacy: .public) eligible=\(eligibleCount, privacy: .public)"
        )
        invalidatePendingRefreshes()
        let operationID = UUID()
        activeOperationID = operationID
        releaseAttempts = []
        phase = .releasing

        do {
            var attempts: [ReleaseAttempt] = []
            for approval in approvals {
                let freshSnapshot = try await diagnoser.blockers(on: disk)
                guard isCurrent(operationID, diskID: disk.id) else { return }

                guard let fresh = freshSnapshot.first(where: {
                    $0.hasSameIdentity(as: approval.process)
                }) else {
                    attempts.append(
                        ReleaseAttempt(
                            processID: approval.process.pid,
                            processName: approval.process.command,
                            disposition: .alreadyClosed,
                            message: "It released the disk before Kick acted."
                        )
                    )
                    continue
                }

                let currentPlan = releaser.planRelease(of: [fresh]).first
                guard approval.plan.strategy == .quitApplication else {
                    attempts.append(
                        ReleaseAttempt(
                            processID: fresh.pid,
                            processName: approval.plan.processName,
                            disposition: .needsManualAction,
                            message: approval.plan.message
                        )
                    )
                    continue
                }

                guard let currentPlan, currentPlan.strategy == .quitApplication else {
                    attempts.append(
                        ReleaseAttempt(
                            processID: fresh.pid,
                            processName: currentPlan?.processName ?? fresh.command,
                            disposition: .needsManualAction,
                            message: currentPlan?.message
                                ?? "Kick cannot verify that this app is still safe to close."
                        )
                    )
                    continue
                }

                attempts.append(contentsOf: await releaser.requestRelease(of: [fresh]))
            }
            releaseAttempts = attempts
            Self.logger.info(
                "Release requests completed count=\(attempts.count, privacy: .public)"
            )

            let exitingProcesses = approvals
                .filter { $0.plan.strategy == .quitApplication }
                .map(\.process)
            try await settleAndRetryEject(
                on: disk,
                operationID: operationID,
                exiting: exitingProcesses
            )
        } catch is CancellationError {
            recoverFromCancellation(operationID: operationID, diskID: disk.id)
        } catch {
            failOperation(operationID: operationID, diskID: disk.id, error: error)
        }
    }

    /// The explicit Stop action for one blocker. It is separate from Safely
    /// Kick: the user picks the process and confirms. Kick takes a fresh
    /// snapshot, confirms the same process still holds the disk, sends one
    /// polite stop request, then rechecks and retries the normal eject.
    public func performStop(of process: BlockingProcess) async {
        guard let disk = selectedDisk, phase == .blocked, let stopper else { return }
        guard let target = blockers.first(where: { $0.hasSameIdentity(as: process) }) else {
            return
        }
        let plan = stopper.planStop(of: target)
        guard plan.method != .unavailable else { return }

        Self.logger.info(
            "Stop requested method=\(self.stopMethodName(plan.method), privacy: .public)"
        )
        invalidatePendingRefreshes()
        let operationID = UUID()
        activeOperationID = operationID
        releaseAttempts = []
        phase = .stopping(name: plan.processName)

        do {
            let freshSnapshot = try await diagnoser.blockers(on: disk)
            guard isCurrent(operationID, diskID: disk.id) else { return }

            let attempt: ReleaseAttempt
            if let fresh = freshSnapshot.first(where: { $0.hasSameIdentity(as: target) }) {
                attempt = await stopper.requestStop(of: fresh)
            } else {
                attempt = ReleaseAttempt(
                    processID: target.pid,
                    processName: plan.processName,
                    disposition: .alreadyClosed,
                    message: "It released the disk before Kick acted."
                )
            }
            guard isCurrent(operationID, diskID: disk.id) else { return }
            releaseAttempts = [attempt]
            Self.logger.info(
                "Stop request completed disposition=\(self.dispositionName(attempt.disposition), privacy: .public)"
            )

            try await settleAndRetryEject(
                on: disk,
                operationID: operationID,
                exiting: attempt.disposition == .requested ? [target] : []
            )
        } catch is CancellationError {
            recoverFromCancellation(operationID: operationID, diskID: disk.id)
        } catch {
            failOperation(operationID: operationID, diskID: disk.id, error: error)
        }
    }

    public func resetResult() async {
        invalidatePendingRefreshes()
        phase = .ready
        blockers = []
        releasePlans = []
        stopPlans = []
        releaseAttempts = []
        await refresh()
    }

    /// Shared tail of Safely Kick and Stop: wait for the processes that were
    /// asked to leave, recheck the disk, then retry the normal eject.
    private func settleAndRetryEject(
        on disk: ExternalDisk,
        operationID: UUID,
        exiting: [BlockingProcess]
    ) async throws {
        let remaining = try await waitForReleasedProcesses(on: disk, exiting: exiting)
        guard isCurrent(operationID, diskID: disk.id) else { return }
        blockers = remaining

        guard remaining.isEmpty else {
            Self.logger.info(
                "Release recheck still blocked count=\(remaining.count, privacy: .public)"
            )
            enterBlockedState(with: remaining)
            return
        }

        phase = .retrying
        do {
            try await ejector.eject(disk)
            guard isCurrent(operationID, diskID: disk.id) else { return }
            finishSuccess(for: disk)
        } catch let failure as EjectionFailure where failure.kind == .busy {
            guard isCurrent(operationID, diskID: disk.id) else { return }
            phase = .diagnosing

            let found = try await diagnoseBlockers(
                on: disk,
                dissentingProcessID: failure.dissentingProcessID
            )
            guard isCurrent(operationID, diskID: disk.id) else { return }
            guard !found.isEmpty else { throw failure }
            enterBlockedState(with: found)
        }
    }

    private func recoverFromCancellation(operationID: UUID, diskID: ExternalDisk.ID) {
        guard isCurrent(operationID, diskID: diskID) else { return }
        activeOperationID = nil
        Self.logger.info("Release operation cancelled safely")
        if blockers.isEmpty {
            releasePlans = []
            stopPlans = []
            phase = .ready
        } else {
            phase = .blocked
        }
    }

    private func failOperation(operationID: UUID, diskID: ExternalDisk.ID, error: Error) {
        guard isCurrent(operationID, diskID: diskID) else { return }
        activeOperationID = nil
        let nsError = error as NSError
        Self.logger.error(
            "Release operation failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
        phase = .failed(
            title: "Kick stopped safely",
            message: readableMessage(for: error)
        )
    }

    private func isCurrent(_ operationID: UUID, diskID: ExternalDisk.ID) -> Bool {
        let matches = activeOperationID == operationID && selectedDiskID == diskID
        if !matches {
            Self.logger.debug("Ignored a stale operation result")
        }
        return matches
    }

    private func finishSuccess(for disk: ExternalDisk) {
        invalidatePendingRefreshes()
        activeOperationID = nil
        blockers = []
        releasePlans = []
        stopPlans = []
        disks.removeAll { $0.id == disk.id }
        selectedDiskID = disks.first?.id
        phase = .ejected(name: disk.displayName)
    }

    private func removeStaleDisk(_ disk: ExternalDisk) {
        disks.removeAll { $0.id == disk.id }
        selectedDiskID = nil
        blockers = []
        releasePlans = []
        stopPlans = []
        releaseAttempts = []
    }

    private func enterBlockedState(with processes: [BlockingProcess]) {
        blockers = processes
        releasePlans = releaser.planRelease(of: processes)
        stopPlans = stopper.map { stopper in processes.map { stopper.planStop(of: $0) } } ?? []
        activeOperationID = nil
        phase = .blocked
    }

    private func diagnoseBlockers(
        on disk: ExternalDisk,
        dissentingProcessID: Int32?
    ) async throws -> [BlockingProcess] {
        if let diagnoser = diagnoser as? DissentAwareBlockerDiagnosing {
            return try await diagnoser.blockers(
                on: disk,
                dissentingProcessID: dissentingProcessID
            )
        }
        return try await diagnoser.blockers(on: disk)
    }

    private func waitForReleasedProcesses(
        on disk: ExternalDisk,
        exiting eligibleProcesses: [BlockingProcess]
    ) async throws -> [BlockingProcess] {
        guard settleDelayNanoseconds > 0, releaseTimeoutNanoseconds > 0 else {
            return try await diagnoser.blockers(on: disk)
        }

        var elapsed: UInt64 = 0
        while true {
            let delay = min(settleDelayNanoseconds, releaseTimeoutNanoseconds - elapsed)
            try await Task.sleep(nanoseconds: delay)
            elapsed += delay

            let remaining = try await diagnoser.blockers(on: disk)
            if remaining.isEmpty || elapsed >= releaseTimeoutNanoseconds {
                return remaining
            }

            let onlyAppsBeingQuit = remaining.allSatisfy { process in
                eligibleProcesses.contains { $0.hasSameIdentity(as: process) }
            }
            if !onlyAppsBeingQuit {
                return remaining
            }
        }
    }

    private func frozenReleaseApprovals() -> [FrozenReleaseApproval] {
        blockers.compactMap { process in
            guard let plan = releasePlans.first(where: { $0.processID == process.pid }) else {
                return nil
            }
            return FrozenReleaseApproval(process: process, plan: plan)
        }
    }

    private func invalidatePendingRefreshes() {
        refreshGeneration &+= 1
    }

    private func readableMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "macOS did not provide a reason." : message
    }

    private func logEjectionFailure(_ error: Error) {
        if let failure = error as? EjectionFailure {
            Self.logger.error(
                "Eject failed kind=\(self.failureKindName(failure.kind), privacy: .public) domain=\(failure.underlyingDomain ?? "none", privacy: .public) code=\(failure.underlyingCode ?? 0, privacy: .public)"
            )
            return
        }
        let nsError = error as NSError
        Self.logger.error(
            "Eject failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
    }

    private func failureKindName(_ kind: EjectionFailureKind) -> String {
        switch kind {
        case .busy: "busy"
        case .identityChanged: "identityChanged"
        case .other: "other"
        }
    }

    private func stopMethodName(_ method: StopMethod) -> String {
        switch method {
        case .quitApplication: "quitApplication"
        case .terminateProcess: "terminateProcess"
        case .unavailable: "unavailable"
        }
    }

    private func dispositionName(_ disposition: ReleaseDisposition) -> String {
        switch disposition {
        case .requested: "requested"
        case .alreadyClosed: "alreadyClosed"
        case .needsManualAction: "needsManualAction"
        case .failed: "failed"
        }
    }
}

private struct FrozenReleaseApproval {
    let process: BlockingProcess
    let plan: ProcessReleasePlan
}
