import Foundation
@testable import KickCore
import XCTest

@MainActor
final class KickWorkflowTests: XCTestCase {
    func testCleanEjectDoesNotDiagnoseOrRelease() async {
        let ejector = ScriptedEjector(results: [.success(())])
        let diagnoser = ScriptedDiagnoser(snapshots: [])
        let releaser = SpyReleaser()
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()

        XCTAssertEqual(workflow.phase, .ejected(name: "Test Disk"))
        XCTAssertEqual(ejector.callCount, 1)
        XCTAssertEqual(diagnoser.callCount, 0)
        XCTAssertEqual(releaser.callCount, 0)
    }

    func testBusyEjectShowsBlockerBeforeRelease() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [[blocker]])
        let releaser = SpyReleaser()
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()

        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.blockers, [blocker])
        XCTAssertEqual(releaser.callCount, 0)
    }

    func testSafeKickRevalidatesReleasesAndRetriesEject() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy)),
            .success(())
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker],
            []
        ])
        let releaser = SpyReleaser()
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performSafeKick()

        XCTAssertEqual(workflow.phase, .ejected(name: "Test Disk"))
        XCTAssertEqual(ejector.callCount, 2)
        XCTAssertEqual(diagnoser.callCount, 3)
        XCTAssertEqual(releaser.received, [blocker])
    }

    func testSafeKickWaitsForApprovedAppToReleaseBeforeRetryingEject() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy)),
            .success(())
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker],
            [blocker],
            []
        ])
        let releaser = SpyReleaser()
        let workflow = KickWorkflow(
            volumeProvider: StaticVolumeProvider(disks: [Fixtures.disk]),
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser,
            settleDelayNanoseconds: 1_000_000,
            releaseTimeoutNanoseconds: 50_000_000
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performSafeKick()

        XCTAssertEqual(workflow.phase, .ejected(name: "Test Disk"))
        XCTAssertEqual(ejector.callCount, 2)
        XCTAssertEqual(diagnoser.callCount, 4)
        XCTAssertEqual(releaser.received, [blocker])
    }

    func testRemainingProtectedBlockerKeepsDiskMounted() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker],
            [blocker]
        ])
        let releaser = SpyReleaser(disposition: .needsManualAction)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performSafeKick()

        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.blockers, [blocker])
        XCTAssertEqual(ejector.callCount, 1)
        XCTAssertEqual(workflow.releaseAttempts.first?.disposition, .needsManualAction)
    }

    func testSelectionChangeIsIgnoredWhileEjectIsBusyAndCurrentResultApplies() async {
        let secondDisk = Fixtures.disk(id: "second", name: "Second Disk")
        let provider = StaticVolumeProvider(disks: [Fixtures.disk, secondDisk])
        let ejector = SuspendedEjector()
        let diagnoser = ScriptedDiagnoser(snapshots: [[Fixtures.blocker]])
        let workflow = KickWorkflow(
            volumeProvider: provider,
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(),
            settleDelayNanoseconds: 0
        )

        await workflow.refresh()
        let operation = Task { await workflow.attemptEject() }
        for _ in 0..<20 where !ejector.isWaiting {
            await Task.yield()
        }

        workflow.selectDisk(id: secondDisk.id)
        ejector.finish(with: EjectionFailure(message: "Old result"))
        await operation.value

        XCTAssertEqual(workflow.selectedDiskID, Fixtures.disk.id)
        XCTAssertEqual(
            workflow.phase,
            .failed(title: "Could not eject", message: "Old result")
        )
        XCTAssertEqual(diagnoser.callCount, 0)
    }

    func testIdentityChangedFailureRemovesStaleDiskAndRequiresRefresh() async {
        let secondDisk = Fixtures.disk(id: "second", name: "Second Disk")
        let provider = StaticVolumeProvider(disks: [Fixtures.disk, secondDisk])
        let ejector = ScriptedEjector(results: [
            .failure(
                EjectionFailure(
                    message: "The selected disk changed.",
                    kind: .identityChanged
                )
            )
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [])
        let workflow = KickWorkflow(
            volumeProvider: provider,
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(),
            settleDelayNanoseconds: 0
        )

        await workflow.refresh()
        await workflow.attemptEject()

        XCTAssertEqual(workflow.disks, [secondDisk])
        XCTAssertNil(workflow.selectedDiskID)
        XCTAssertEqual(
            workflow.phase,
            .failed(
                title: "Could not eject",
                message: "The selected disk changed.",
                recovery: .refreshDisks
            )
        )
        XCTAssertEqual(diagnoser.callCount, 0)
    }

    func testNonBusyEjectErrorNeverDiagnosesOrReleases() async {
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Permission denied", kind: .other))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [])
        let releaser = SpyReleaser()
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()

        XCTAssertEqual(
            workflow.phase,
            .failed(title: "Could not eject", message: "Permission denied")
        )
        XCTAssertEqual(diagnoser.callCount, 0)
        XCTAssertEqual(releaser.callCount, 0)
    }

    func testUnmountNotificationDuringEjectStillFinishesSuccess() async {
        let secondDisk = Fixtures.disk(id: "second", name: "Second Disk")
        let provider = MutableVolumeProvider(disks: [Fixtures.disk, secondDisk])
        let ejector = SuspendedEjector()
        let workflow = KickWorkflow(
            volumeProvider: provider,
            ejector: ejector,
            diagnoser: ScriptedDiagnoser(snapshots: []),
            releaser: SpyReleaser(),
            settleDelayNanoseconds: 0
        )

        await workflow.refresh()
        let operation = Task { await workflow.attemptEject() }
        for _ in 0..<20 where !ejector.isWaiting {
            await Task.yield()
        }

        provider.disks = [secondDisk]
        await workflow.refresh()
        XCTAssertEqual(workflow.selectedDiskID, Fixtures.disk.id)

        ejector.finish(with: nil)
        await operation.value

        XCTAssertEqual(workflow.phase, .ejected(name: "Test Disk"))
        XCTAssertEqual(workflow.selectedDiskID, secondDisk.id)
    }

    func testSafeKickDoesNotReleaseBlockerThatAppearsAfterConfirmation() async {
        let reviewed = Fixtures.blocker
        let newBlocker = Fixtures.secondBlocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [reviewed],
            [reviewed, newBlocker],
            [newBlocker]
        ])
        let releaser = SpyReleaser()
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performSafeKick()

        XCTAssertEqual(releaser.received, [reviewed])
        XCTAssertEqual(workflow.blockers, [newBlocker])
        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(ejector.callCount, 1)
    }

    func testSafeKickDoesNotReleaseBlockerThatBecameEligibleAfterConfirmation() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker],
            [blocker]
        ])
        let releaser = SpyReleaser(planStrategy: .manualAction)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()
        XCTAssertEqual(workflow.releasePlans.first?.strategy, .manualAction)

        releaser.planStrategy = .quitApplication
        await workflow.performSafeKick()

        XCTAssertEqual(releaser.callCount, 0)
        XCTAssertTrue(releaser.received.isEmpty)
        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.releaseAttempts.first?.disposition, .needsManualAction)
        XCTAssertEqual(workflow.releasePlans.first?.strategy, .quitApplication)
    }

    func testSafeKickRevalidatesApprovedStrategyBeforeRelease() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker],
            [blocker]
        ])
        let releaser = SpyReleaser(planStrategy: .quitApplication)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()
        releaser.planStrategy = .manualAction
        await workflow.performSafeKick()

        XCTAssertEqual(releaser.callCount, 0)
        XCTAssertTrue(releaser.received.isEmpty)
        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.releaseAttempts.first?.disposition, .needsManualAction)
    }

    func testCancelledSafeKickReturnsToBlockedState() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker]
        ])
        let releaser = SpyReleaser()
        let workflow = KickWorkflow(
            volumeProvider: StaticVolumeProvider(disks: [Fixtures.disk]),
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser,
            settleDelayNanoseconds: 60_000_000_000
        )

        await workflow.refresh()
        await workflow.attemptEject()
        let operation = Task { await workflow.performSafeKick() }
        for _ in 0..<100 where releaser.callCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(releaser.callCount, 1)
        operation.cancel()
        await operation.value

        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.blockers, [blocker])
        XCTAssertFalse(workflow.phase.isBusy)
    }

    func testOlderRefreshResultCannotReplaceNewerDiskList() async {
        let firstDisk = Fixtures.disk(id: "first", name: "First Disk")
        let secondDisk = Fixtures.disk(id: "second", name: "Second Disk")
        let provider = SuspendedVolumeProvider()
        let workflow = KickWorkflow(
            volumeProvider: provider,
            ejector: ScriptedEjector(results: []),
            diagnoser: ScriptedDiagnoser(snapshots: []),
            releaser: SpyReleaser(),
            settleDelayNanoseconds: 0
        )

        let olderRefresh = Task { await workflow.refresh() }
        for _ in 0..<100 where provider.startedCallCount < 1 {
            await Task.yield()
        }
        let newerRefresh = Task { await workflow.refresh() }
        for _ in 0..<100 where provider.startedCallCount < 2 {
            await Task.yield()
        }

        provider.finish(call: 1, with: [secondDisk])
        await newerRefresh.value
        provider.finish(call: 0, with: [firstDisk])
        await olderRefresh.value

        XCTAssertEqual(workflow.disks, [secondDisk])
        XCTAssertEqual(workflow.selectedDiskID, secondDisk.id)
    }

    func testRefreshFailureClearsStaleDisksAndRequiresRefresh() async {
        let provider = ResultVolumeProvider(result: .success([Fixtures.disk]))
        let workflow = KickWorkflow(
            volumeProvider: provider,
            ejector: ScriptedEjector(results: []),
            diagnoser: ScriptedDiagnoser(snapshots: []),
            releaser: SpyReleaser(),
            settleDelayNanoseconds: 0
        )

        await workflow.refresh()
        XCTAssertEqual(workflow.selectedDiskID, Fixtures.disk.id)

        provider.result = .failure(TestProviderError.unavailable)
        await workflow.refresh()
        workflow.selectDisk(id: Fixtures.disk.id)

        XCTAssertTrue(workflow.disks.isEmpty)
        XCTAssertNil(workflow.selectedDiskID)
        XCTAssertEqual(
            workflow.phase,
            .failed(
                title: "Could not check disks",
                message: "Disk scan unavailable",
                recovery: .refreshDisks
            )
        )
        XCTAssertFalse(workflow.phase.allowsDiskSelection)
    }

    func testRetryBusyDiagnosesNewBlockerWithoutReleasingIt() async {
        let approved = Fixtures.blocker
        let newBlocker = Fixtures.secondBlocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy)),
            .failure(EjectionFailure(message: "Busy again", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [approved],
            [approved],
            [],
            [newBlocker]
        ])
        let releaser = SpyReleaser()
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performSafeKick()

        XCTAssertEqual(ejector.callCount, 2)
        XCTAssertEqual(releaser.received, [approved])
        XCTAssertEqual(workflow.blockers, [newBlocker])
        XCTAssertEqual(workflow.phase, .blocked)
    }

    // MARK: - Stop (last stage, separate from Safely Kick)

    func testBlockedStatePublishesStopPlans() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [[blocker]])
        let stopper = SpyStopper(method: .terminateProcess)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(planStrategy: .manualAction),
            stopper: stopper
        )

        await workflow.refresh()
        await workflow.attemptEject()

        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.stopPlans.map(\.processID), [blocker.pid])
        XCTAssertEqual(workflow.stopPlans.first?.method, .terminateProcess)
    }

    func testStopRevalidatesTheProcessThenRetriesEject() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy)),
            .success(())
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],   // diagnosis after the busy eject
            [blocker],   // fresh snapshot before the stop request
            []           // recheck after the stop request
        ])
        let stopper = SpyStopper(method: .terminateProcess)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(planStrategy: .manualAction),
            stopper: stopper
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performStop(of: blocker)

        XCTAssertEqual(workflow.phase, .ejected(name: "Test Disk"))
        XCTAssertEqual(stopper.received, [blocker])
        XCTAssertEqual(ejector.callCount, 2)
        XCTAssertEqual(diagnoser.callCount, 3)
    }

    func testStopSendsNothingWhenTheProcessAlreadyLeft() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy)),
            .success(())
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [],          // the process left before Kick acted
            []
        ])
        let stopper = SpyStopper(method: .terminateProcess)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(planStrategy: .manualAction),
            stopper: stopper
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performStop(of: blocker)

        XCTAssertEqual(workflow.phase, .ejected(name: "Test Disk"))
        XCTAssertTrue(stopper.received.isEmpty)
        XCTAssertEqual(workflow.releaseAttempts.first?.disposition, .alreadyClosed)
    }

    func testStopDoesNotSignalARecycledPID() async {
        let blocker = Fixtures.blocker
        let impostor = BlockingProcess(
            pid: blocker.pid,
            parentPID: blocker.parentPID,
            command: blocker.command,
            userID: blocker.userID,
            loginName: blocker.loginName,
            openFiles: blocker.openFiles,
            executablePath: "/usr/bin/other",
            startTime: ProcessStartTime(seconds: 9, microseconds: 9)
        )
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [impostor],  // same PID, different process
            [impostor]
        ])
        let stopper = SpyStopper(method: .terminateProcess)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(planStrategy: .manualAction),
            stopper: stopper
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performStop(of: blocker)

        XCTAssertTrue(stopper.received.isEmpty)
        XCTAssertEqual(workflow.releaseAttempts.first?.disposition, .alreadyClosed)
        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.blockers, [impostor])
        XCTAssertEqual(ejector.callCount, 1)
    }

    func testStopKeepsDiskMountedWhenTheBlockerStays() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [
            [blocker],
            [blocker],
            [blocker]    // still there after the request
        ])
        let stopper = SpyStopper(method: .terminateProcess)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(planStrategy: .manualAction),
            stopper: stopper
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performStop(of: blocker)

        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertEqual(workflow.blockers, [blocker])
        XCTAssertEqual(ejector.callCount, 1)
        XCTAssertEqual(workflow.releaseAttempts.first?.disposition, .requested)
    }

    func testStopIsIgnoredWhenThePlanIsUnavailable() async {
        let blocker = Fixtures.blocker
        let ejector = ScriptedEjector(results: [
            .failure(EjectionFailure(message: "Busy", kind: .busy))
        ])
        let diagnoser = ScriptedDiagnoser(snapshots: [[blocker]])
        let stopper = SpyStopper(method: .unavailable)
        let workflow = makeWorkflow(
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: SpyReleaser(planStrategy: .manualAction),
            stopper: stopper
        )

        await workflow.refresh()
        await workflow.attemptEject()
        await workflow.performStop(of: blocker)

        XCTAssertEqual(workflow.phase, .blocked)
        XCTAssertTrue(stopper.received.isEmpty)
        XCTAssertEqual(diagnoser.callCount, 1)
    }

    private func makeWorkflow(
        ejector: DiskEjecting,
        diagnoser: BlockerDiagnosing,
        releaser: ProcessReleasing,
        stopper: ProcessStopping? = nil
    ) -> KickWorkflow {
        KickWorkflow(
            volumeProvider: StaticVolumeProvider(disks: [Fixtures.disk]),
            ejector: ejector,
            diagnoser: diagnoser,
            releaser: releaser,
            stopper: stopper,
            settleDelayNanoseconds: 0
        )
    }
}

private final class StaticVolumeProvider: VolumeProviding {
    let disks: [ExternalDisk]

    init(disks: [ExternalDisk]) {
        self.disks = disks
    }

    func mountedExternalDisks() async throws -> [ExternalDisk] { disks }
}

private final class MutableVolumeProvider: VolumeProviding {
    var disks: [ExternalDisk]

    init(disks: [ExternalDisk]) {
        self.disks = disks
    }

    func mountedExternalDisks() async throws -> [ExternalDisk] { disks }
}

private final class ResultVolumeProvider: VolumeProviding {
    var result: Result<[ExternalDisk], Error>

    init(result: Result<[ExternalDisk], Error>) {
        self.result = result
    }

    func mountedExternalDisks() async throws -> [ExternalDisk] {
        try result.get()
    }
}

private enum TestProviderError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Disk scan unavailable" }
}

private final class SuspendedVolumeProvider: VolumeProviding {
    private var continuations: [Int: CheckedContinuation<[ExternalDisk], Error>] = [:]
    private(set) var startedCallCount = 0

    func mountedExternalDisks() async throws -> [ExternalDisk] {
        let call = startedCallCount
        startedCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[call] = continuation
        }
    }

    func finish(call: Int, with disks: [ExternalDisk]) {
        continuations.removeValue(forKey: call)?.resume(returning: disks)
    }
}

private final class ScriptedEjector: DiskEjecting {
    private var results: [Result<Void, Error>]
    private(set) var callCount = 0

    init(results: [Result<Void, Error>]) {
        self.results = results
    }

    func eject(_ disk: ExternalDisk) async throws {
        callCount += 1
        guard !results.isEmpty else {
            XCTFail("Missing eject result")
            return
        }
        try results.removeFirst().get()
    }
}

private final class ScriptedDiagnoser: BlockerDiagnosing {
    private var snapshots: [[BlockingProcess]]
    private(set) var callCount = 0

    init(snapshots: [[BlockingProcess]]) {
        self.snapshots = snapshots
    }

    func blockers(on disk: ExternalDisk) async throws -> [BlockingProcess] {
        callCount += 1
        guard !snapshots.isEmpty else {
            XCTFail("Missing diagnosis snapshot")
            return []
        }
        return snapshots.removeFirst()
    }
}

@MainActor
private final class SpyReleaser: ProcessReleasing {
    let disposition: ReleaseDisposition
    var planStrategy: ReleaseStrategy
    private(set) var callCount = 0
    private(set) var received: [BlockingProcess] = []

    init(
        disposition: ReleaseDisposition = .requested,
        planStrategy: ReleaseStrategy = .quitApplication
    ) {
        self.disposition = disposition
        self.planStrategy = planStrategy
    }

    func planRelease(of processes: [BlockingProcess]) -> [ProcessReleasePlan] {
        processes.map {
            ProcessReleasePlan(
                processID: $0.pid,
                processName: $0.command,
                strategy: planStrategy,
                message: planStrategy == .quitApplication
                    ? "Kick will ask this app to quit."
                    : "Close this process yourself."
            )
        }
    }

    func requestRelease(of processes: [BlockingProcess]) async -> [ReleaseAttempt] {
        callCount += 1
        received.append(contentsOf: processes)
        return processes.map {
            ReleaseAttempt(
                processID: $0.pid,
                processName: $0.command,
                disposition: disposition,
                message: "Test result"
            )
        }
    }
}

@MainActor
private final class SpyStopper: ProcessStopping {
    let method: StopMethod
    private(set) var received: [BlockingProcess] = []

    init(method: StopMethod) {
        self.method = method
    }

    func planStop(of process: BlockingProcess) -> ProcessStopPlan {
        ProcessStopPlan(
            processID: process.pid,
            processName: process.command,
            method: method,
            message: "Test plan"
        )
    }

    func requestStop(of process: BlockingProcess) async -> ReleaseAttempt {
        received.append(process)
        return ReleaseAttempt(
            processID: process.pid,
            processName: process.command,
            disposition: .requested,
            message: "Test stop"
        )
    }
}

private final class SuspendedEjector: DiskEjecting {
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }

    func eject(_ disk: ExternalDisk) async throws {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(with error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: ())
        }
        continuation = nil
    }
}

private enum Fixtures {
    static let disk = disk(id: "test", name: "Test Disk")

    static func disk(id: String, name: String) -> ExternalDisk {
        ExternalDisk(
            id: id,
            displayName: name,
            volumes: [
                DiskVolume(
                    id: "\(id)-volume",
                    name: name,
                    mountURL: URL(fileURLWithPath: "/Volumes/\(name)")
                )
            ]
        )
    }

    static let blocker = BlockingProcess(
        pid: 700,
        parentPID: 1,
        command: "Preview",
        userID: 501,
        loginName: "user",
        openFiles: [
            OpenFileReference(path: "/Volumes/Test Disk/image.png", access: .read)
        ]
    )

    static let secondBlocker = BlockingProcess(
        pid: 701,
        parentPID: 1,
        command: "Photos",
        userID: 501,
        loginName: "user",
        openFiles: [
            OpenFileReference(path: "/Volumes/Test Disk/library.photoslibrary", access: .read)
        ]
    )
}
