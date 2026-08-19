import Foundation

public enum EjectionPhase: Equatable {
    case ready
    case ejecting
    case diagnosing
    case blocked
    case releasing
    case stopping(name: String)
    case retrying
    case ejected(name: String)
    case failed(
        title: String,
        message: String,
        recovery: FailureRecovery = .retryEject
    )

    public var isBusy: Bool {
        switch self {
        case .ejecting, .diagnosing, .releasing, .stopping, .retrying:
            return true
        default:
            return false
        }
    }

    public var allowsDiskSelection: Bool {
        guard !isBusy else { return false }
        switch self {
        case .ejected, .failed(_, _, .refreshDisks):
            return false
        default:
            return true
        }
    }
}

public enum FailureRecovery: Equatable {
    case refreshDisks
    case retryEject
}

public enum ReleaseDisposition: Equatable {
    case requested
    case alreadyClosed
    case needsManualAction
    case failed
}

public struct ReleaseAttempt: Identifiable, Equatable {
    public let id: UUID
    public let processID: Int32
    public let processName: String
    public let disposition: ReleaseDisposition
    public let message: String

    public init(
        id: UUID = UUID(),
        processID: Int32,
        processName: String,
        disposition: ReleaseDisposition,
        message: String
    ) {
        self.id = id
        self.processID = processID
        self.processName = processName
        self.disposition = disposition
        self.message = message
    }
}

public enum EjectionFailureKind: Equatable {
    case busy
    case identityChanged
    case other
}

public struct EjectionFailure: LocalizedError, Equatable {
    public let message: String
    public let dissentingProcessID: Int32?
    public let kind: EjectionFailureKind
    public let underlyingDomain: String?
    public let underlyingCode: Int?

    public init(
        message: String,
        dissentingProcessID: Int32? = nil,
        kind: EjectionFailureKind = .other,
        underlyingDomain: String? = nil,
        underlyingCode: Int? = nil
    ) {
        self.message = message
        self.dissentingProcessID = dissentingProcessID
        self.kind = kind
        self.underlyingDomain = underlyingDomain
        self.underlyingCode = underlyingCode
    }

    public var errorDescription: String? { message }
}

public enum ReleaseStrategy: Equatable {
    case quitApplication
    case manualAction
}

/// How the explicit, user-initiated Stop action would stop one blocker.
/// Stop is separate from Safely Kick. It sends one polite request and never
/// forces a kill.
public enum StopMethod: Equatable {
    /// A normal macOS app. Kick asks it to quit, the same as Quit in its menu.
    case quitApplication
    /// A command-line tool or helper. Kick sends one `SIGTERM`.
    case terminateProcess
    /// Kick refuses to stop this process.
    case unavailable
}

public struct ProcessStopPlan: Identifiable, Equatable {
    public var id: Int32 { processID }
    public let processID: Int32
    public let processName: String
    public let method: StopMethod
    public let message: String
    public let warning: String?

    public init(
        processID: Int32,
        processName: String,
        method: StopMethod,
        message: String,
        warning: String? = nil
    ) {
        self.processID = processID
        self.processName = processName
        self.method = method
        self.message = message
        self.warning = warning
    }
}

public struct ProcessReleasePlan: Identifiable, Equatable {
    public var id: Int32 { processID }
    public let processID: Int32
    public let processName: String
    public let strategy: ReleaseStrategy
    public let message: String

    public init(
        processID: Int32,
        processName: String,
        strategy: ReleaseStrategy,
        message: String
    ) {
        self.processID = processID
        self.processName = processName
        self.strategy = strategy
        self.message = message
    }
}
