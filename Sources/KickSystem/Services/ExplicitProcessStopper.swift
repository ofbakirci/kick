import AppKit
import Darwin
import Foundation
import KickCore

/// The explicit Stop action. It is the last stage, separate from Safely Kick.
/// The user picks one blocker and confirms. Kick checks the live process
/// identity again and sends one polite request: a normal quit request for an
/// app, or one `SIGTERM` for a command-line tool. It never sends `SIGKILL`.
@MainActor
public final class ExplicitProcessStopper: ProcessStopping {
    typealias Signaler = (_ pid: Int32, _ signal: Int32) -> Int32

    private let currentUserID: UInt32
    private let currentProcessID: Int32
    private let metadataProvider: ProcessMetadataProviding
    private let signaler: Signaler

    public init(
        currentUserID: UInt32 = getuid(),
        currentProcessID: Int32 = getpid()
    ) {
        self.currentUserID = currentUserID
        self.currentProcessID = currentProcessID
        self.metadataProvider = SystemProcessMetadataProvider()
        self.signaler = { pid, signal in Darwin.kill(pid, signal) }
    }

    init(
        currentUserID: UInt32,
        currentProcessID: Int32,
        metadataProvider: ProcessMetadataProviding,
        signaler: @escaping Signaler
    ) {
        self.currentUserID = currentUserID
        self.currentProcessID = currentProcessID
        self.metadataProvider = metadataProvider
        self.signaler = signaler
    }

    public func planStop(of process: BlockingProcess) -> ProcessStopPlan {
        let application = runningApplication(for: process)
        let name = application?.localizedName ?? process.command
        let unavailable: (String) -> ProcessStopPlan = { message in
            ProcessStopPlan(
                processID: process.pid,
                processName: name,
                method: .unavailable,
                message: message
            )
        }

        if process.pid <= 1 || process.pid == currentProcessID {
            return unavailable("Kick will not stop this protected process.")
        }
        guard process.userID == currentUserID else {
            return unavailable("This process belongs to macOS or another user. Kick cannot stop it.")
        }
        guard process.startTime != nil, process.executablePath != nil else {
            return unavailable("Kick cannot verify this process identity, so it will not send a stop request.")
        }
        if ProcessCommandPolicy.isSystemUserInterface(process.command) {
            return unavailable("This is part of macOS. Close the file or wait for macOS to finish.")
        }

        if let application {
            guard application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return unavailable("Kick will not stop itself.")
            }
            return ProcessStopPlan(
                processID: process.pid,
                processName: name,
                method: .quitApplication,
                message: "Kick will ask \(name) to quit, the same as Quit in its menu. The app can still show a save dialog.",
                warning: warning(for: process)
            )
        }

        return ProcessStopPlan(
            processID: process.pid,
            processName: name,
            method: .terminateProcess,
            message: "Kick will send one stop request (SIGTERM) to \(name). Most tools stop cleanly. Kick never forces a kill.",
            warning: warning(for: process)
        )
    }

    public func requestStop(of process: BlockingProcess) async -> ReleaseAttempt {
        let plan = planStop(of: process)
        switch plan.method {
        case .unavailable:
            return attempt(process, plan, .needsManualAction, plan.message)

        case .quitApplication:
            guard let application = runningApplication(for: process) else {
                return attempt(process, plan, .alreadyClosed, "The app is no longer running.")
            }
            guard liveIdentityMatches(process) else {
                return attempt(
                    process, plan, .failed,
                    "Kick could not verify that this is the same app. Nothing was sent."
                )
            }
            if application.isTerminated {
                return attempt(process, plan, .alreadyClosed, "The app is already closed.")
            }
            if application.terminate() {
                return attempt(process, plan, .requested, "Kick asked \(plan.processName) to quit.")
            }
            return attempt(process, plan, .failed, "The app did not accept the quit request.")

        case .terminateProcess:
            guard metadataProvider.metadata(for: process.pid) != nil else {
                return attempt(process, plan, .alreadyClosed, "The process already exited.")
            }
            guard liveIdentityMatches(process) else {
                return attempt(
                    process, plan, .failed,
                    "Kick could not verify that this is the same process. Nothing was sent."
                )
            }
            if signaler(process.pid, SIGTERM) == 0 {
                return attempt(process, plan, .requested, "Kick sent a stop request to \(plan.processName).")
            }
            switch errno {
            case ESRCH:
                return attempt(process, plan, .alreadyClosed, "The process already exited.")
            case EPERM:
                return attempt(process, plan, .failed, "macOS did not allow Kick to stop this process.")
            default:
                return attempt(process, plan, .failed, "The stop request failed (error \(errno)).")
            }
        }
    }

    private func runningApplication(for process: BlockingProcess) -> NSRunningApplication? {
        guard let application = NSRunningApplication(processIdentifier: process.pid),
              application.activationPolicy != .prohibited else {
            return nil
        }
        return application
    }

    private func liveIdentityMatches(_ process: BlockingProcess) -> Bool {
        guard let metadata = metadataProvider.metadata(for: process.pid) else { return false }
        return metadata.matchesIdentity(of: process)
    }

    private func warning(for process: BlockingProcess) -> String? {
        if process.hasWritableFiles {
            return "It has a file open for writing. Stopping it now can leave that file incomplete."
        }
        if ProcessCommandPolicy.isVirtualMachine(process.command) {
            return "A running virtual machine can lose unsaved state. Stop it from its own app if you can."
        }
        if ProcessCommandPolicy.isTransfer(process.command) {
            return "A backup or sync stops mid-transfer. It can resume later, but the current file stays incomplete."
        }
        if ProcessCommandPolicy.isShell(process.command) {
            return "This ends the shell session in that terminal window."
        }
        return nil
    }

    private func attempt(
        _ process: BlockingProcess,
        _ plan: ProcessStopPlan,
        _ disposition: ReleaseDisposition,
        _ message: String
    ) -> ReleaseAttempt {
        ReleaseAttempt(
            processID: process.pid,
            processName: plan.processName,
            disposition: disposition,
            message: message
        )
    }
}
