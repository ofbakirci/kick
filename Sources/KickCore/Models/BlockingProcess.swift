import Foundation

public enum OpenAccess: String, Hashable {
    case read
    case write
    case readWrite
    case unknown

    public init(lsofValue: String?) {
        switch lsofValue {
        case "r": self = .read
        case "w": self = .write
        case "u": self = .readWrite
        default: self = .unknown
        }
    }

    public var canWrite: Bool {
        self == .write || self == .readWrite
    }
}

public struct OpenFileReference: Hashable {
    public let path: String
    public let descriptor: String?
    public let fileType: String?
    public let access: OpenAccess

    /// `cwd` and `rtd` entries point at a directory the process sits in. They
    /// are not open files and can never carry a write.
    public var isDirectoryReference: Bool {
        descriptor == "cwd" || descriptor == "rtd"
    }

    public init(
        path: String,
        descriptor: String? = nil,
        fileType: String? = nil,
        access: OpenAccess = .unknown
    ) {
        self.path = path
        self.descriptor = descriptor
        self.fileType = fileType
        self.access = access
    }
}

/// The nearest ancestor of a process that is a normal macOS app, such as the
/// Terminal window that owns a shell.
public struct ParentApplication: Hashable {
    public let pid: Int32
    public let name: String
    public let bundleIdentifier: String?

    public init(pid: Int32, name: String, bundleIdentifier: String? = nil) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct ProcessStartTime: Hashable {
    public let seconds: UInt64
    public let microseconds: UInt64

    public init(seconds: UInt64, microseconds: UInt64) {
        self.seconds = seconds
        self.microseconds = microseconds
    }
}

public struct BlockingProcess: Identifiable, Hashable {
    public var id: Int32 { pid }

    public let pid: Int32
    public let parentPID: Int32?
    public let command: String
    public let userID: UInt32?
    public let loginName: String?
    public let openFiles: [OpenFileReference]
    public let executablePath: String?
    public let startTime: ProcessStartTime?
    public let isSystemDissent: Bool
    public let parentApplication: ParentApplication?

    public init(
        pid: Int32,
        parentPID: Int32? = nil,
        command: String,
        userID: UInt32? = nil,
        loginName: String? = nil,
        openFiles: [OpenFileReference],
        executablePath: String? = nil,
        startTime: ProcessStartTime? = nil,
        isSystemDissent: Bool = false,
        parentApplication: ParentApplication? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
        self.userID = userID
        self.loginName = loginName
        self.openFiles = openFiles
        self.executablePath = executablePath
        self.startTime = startTime
        self.isSystemDissent = isSystemDissent
        self.parentApplication = parentApplication
    }

    public var hasWritableFiles: Bool {
        openFiles.contains { $0.access.canWrite }
    }

    /// True when an open file has an access mode Kick cannot read. Directory
    /// references (`cwd`, `rtd`) always report a blank mode, so they do not count.
    public var hasUnknownAccess: Bool {
        openFiles.contains { $0.access == .unknown && !$0.isDirectoryReference }
    }

    /// True when the process holds the disk through its current folder.
    public var holdsCurrentFolder: Bool {
        openFiles.contains { $0.descriptor == "cwd" }
    }

    public var primaryPath: String? {
        openFiles.first?.path
    }

    public func hasSameIdentity(as other: BlockingProcess) -> Bool {
        guard pid == other.pid
            && userID == other.userID
            && command == other.command
            && parentPID == other.parentPID else {
            return false
        }

        if startTime != nil || other.startTime != nil {
            guard startTime == other.startTime else { return false }
        }
        if executablePath != nil || other.executablePath != nil {
            guard executablePath == other.executablePath else { return false }
        }
        return true
    }

    public func withExecutionIdentity(
        executablePath: String?,
        startTime: ProcessStartTime?,
        parentApplication: ParentApplication? = nil
    ) -> BlockingProcess {
        BlockingProcess(
            pid: pid,
            parentPID: parentPID,
            command: command,
            userID: userID,
            loginName: loginName,
            openFiles: openFiles,
            executablePath: executablePath,
            startTime: startTime,
            isSystemDissent: isSystemDissent,
            parentApplication: parentApplication ?? self.parentApplication
        )
    }

    public func merging(_ other: BlockingProcess) -> BlockingProcess {
        let files = Array(Set(openFiles + other.openFiles)).sorted { $0.path < $1.path }
        return BlockingProcess(
            pid: pid,
            parentPID: parentPID ?? other.parentPID,
            command: command.isEmpty ? other.command : command,
            userID: userID ?? other.userID,
            loginName: loginName ?? other.loginName,
            openFiles: files,
            executablePath: executablePath ?? other.executablePath,
            startTime: startTime ?? other.startTime,
            isSystemDissent: isSystemDissent || other.isSystemDissent,
            parentApplication: parentApplication ?? other.parentApplication
        )
    }
}
