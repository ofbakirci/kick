import Foundation

public protocol VolumeProviding {
    func mountedExternalDisks() async throws -> [ExternalDisk]
}

public protocol DiskEjecting {
    func eject(_ disk: ExternalDisk) async throws
}

public protocol BlockerDiagnosing {
    func blockers(on disk: ExternalDisk) async throws -> [BlockingProcess]
}

public protocol DissentAwareBlockerDiagnosing: BlockerDiagnosing {
    func blockers(
        on disk: ExternalDisk,
        dissentingProcessID: Int32?
    ) async throws -> [BlockingProcess]
}

@MainActor
public protocol ProcessReleasing {
    func planRelease(of processes: [BlockingProcess]) -> [ProcessReleasePlan]
    func requestRelease(of processes: [BlockingProcess]) async -> [ReleaseAttempt]
}

/// The explicit Stop action. The user picks one blocker and confirms. Kick
/// re-checks the process identity and sends one polite stop request.
@MainActor
public protocol ProcessStopping {
    func planStop(of process: BlockingProcess) -> ProcessStopPlan
    func requestStop(of process: BlockingProcess) async -> ReleaseAttempt
}

public extension ProcessReleasing {
    func planRelease(of processes: [BlockingProcess]) -> [ProcessReleasePlan] {
        processes.map {
            ProcessReleasePlan(
                processID: $0.pid,
                processName: $0.command,
                strategy: .manualAction,
                message: "Close this process, then try again."
            )
        }
    }
}
