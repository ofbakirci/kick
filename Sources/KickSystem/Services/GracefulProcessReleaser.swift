import AppKit
import Darwin
import Foundation
import KickCore

@MainActor
public final class GracefulProcessReleaser: ProcessReleasing {
    private let currentUserID: UInt32
    private let currentProcessID: Int32
    private let metadataProvider: ProcessMetadataProviding

    public init(
        currentUserID: UInt32 = getuid(),
        currentProcessID: Int32 = getpid()
    ) {
        self.currentUserID = currentUserID
        self.currentProcessID = currentProcessID
        self.metadataProvider = SystemProcessMetadataProvider()
    }

    init(
        currentUserID: UInt32,
        currentProcessID: Int32,
        metadataProvider: ProcessMetadataProviding
    ) {
        self.currentUserID = currentUserID
        self.currentProcessID = currentProcessID
        self.metadataProvider = metadataProvider
    }

    public func planRelease(of processes: [BlockingProcess]) -> [ProcessReleasePlan] {
        processes.map(planRelease)
    }

    public func requestRelease(of processes: [BlockingProcess]) async -> [ReleaseAttempt] {
        processes.map(requestRelease)
    }

    private func requestRelease(_ process: BlockingProcess) -> ReleaseAttempt {
        let plan = planRelease(process)
        guard plan.strategy == .quitApplication else {
            return manual(process, plan.message)
        }

        guard let application = NSRunningApplication(processIdentifier: process.pid) else {
            return manual(process, "This is no longer a normal app. Close it yourself.")
        }
        guard hasSameLiveIdentity(process) else {
            return manual(process, "Kick could not verify that this is the same app.")
        }
        if application.isTerminated {
            return ReleaseAttempt(
                processID: process.pid,
                processName: plan.processName,
                disposition: .alreadyClosed,
                message: "The app is already closed."
            )
        }
        if application.terminate() {
            return ReleaseAttempt(
                processID: process.pid,
                processName: plan.processName,
                disposition: .requested,
                message: "Kick asked the app to quit."
            )
        }

        return failed(process, "The app did not accept the quit request.")
    }

    private func planRelease(_ process: BlockingProcess) -> ProcessReleasePlan {
        let manual: (String) -> ProcessReleasePlan = { message in
            ProcessReleasePlan(
                processID: process.pid,
                processName: process.command,
                strategy: .manualAction,
                message: message
            )
        }

        if process.pid <= 1 || process.pid == currentProcessID {
            return manual("Kick will not close this protected process.")
        }
        guard process.userID == currentUserID else {
            return manual("This process belongs to macOS or another user.")
        }
        if process.isSystemDissent || process.openFiles.isEmpty {
            return manual("Kick cannot verify how this app uses the disk. Close it yourself.")
        }
        if process.hasWritableFiles {
            return manual("It can write to the disk. Finish its work first.")
        }
        // Specific guidance for shells, transfers, and virtual machines comes
        // before the generic "cannot verify" message.
        if ProcessCommandPolicy.isSensitive(process.command) {
            return manual(ProcessCommandPolicy.manualGuidance(for: process.command))
        }
        if process.hasUnknownAccess {
            return manual("Kick cannot verify how this process uses the disk.")
        }
        guard process.startTime != nil, process.executablePath != nil else {
            return manual("Kick cannot verify this app's process identity.")
        }
        guard let application = NSRunningApplication(processIdentifier: process.pid) else {
            return manual(
                process.holdsCurrentFolder
                    ? "Its current folder is on this disk. Close this command or helper, then try again."
                    : "Close this command or helper, then try again."
            )
        }
        guard application.activationPolicy != .prohibited else {
            return manual("This background service must finish on its own.")
        }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return manual("Kick will not close itself.")
        }

        return ProcessReleasePlan(
            processID: process.pid,
            processName: application.localizedName ?? process.command,
            strategy: .quitApplication,
            message: "Kick will ask this app to quit."
        )
    }

    private func hasSameLiveIdentity(_ process: BlockingProcess) -> Bool {
        guard let metadata = metadataProvider.metadata(for: process.pid) else { return false }
        return metadata.matchesIdentity(of: process)
    }

    private func manual(_ process: BlockingProcess, _ message: String) -> ReleaseAttempt {
        ReleaseAttempt(
            processID: process.pid,
            processName: process.command,
            disposition: .needsManualAction,
            message: message
        )
    }

    private func failed(_ process: BlockingProcess, _ message: String) -> ReleaseAttempt {
        ReleaseAttempt(
            processID: process.pid,
            processName: process.command,
            disposition: .failed,
            message: message
        )
    }
}
