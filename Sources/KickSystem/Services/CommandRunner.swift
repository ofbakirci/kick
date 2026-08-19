import Foundation

public struct CommandResult {
    public let status: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(status: Int32, standardOutput: Data, standardError: Data) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var errorText: String {
        String(decoding: standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol CommandRunning {
    func run(executable: URL, arguments: [String]) async throws -> CommandResult
}

public enum CommandRunnerError: LocalizedError {
    case couldNotCreateTemporaryFiles
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .couldNotCreateTemporaryFiles:
            return "Kick could not prepare a process check."
        case .timedOut:
            return "The process check took too long. Try again."
        }
    }
}

public final class SystemCommandRunner: CommandRunning {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 8) {
        self.timeout = max(timeout, 0.05)
    }

    public func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        let execution = CommandExecution(
            executable: executable,
            arguments: arguments,
            timeout: timeout
        )

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                execution.start(continuation: continuation)
            }
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class CommandExecution: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
    }

    func start(continuation: CheckedContinuation<CommandResult, Error>) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                continuation.resume(returning: try runSynchronously())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() {
        let runningProcess: Process?
        lock.lock()
        cancellationRequested = true
        runningProcess = process
        lock.unlock()

        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    private func runSynchronously() throws -> CommandResult {
        try checkCancellation()

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Kick-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let outputURL = temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              fileManager.createFile(atPath: errorURL.path, contents: nil) else {
            throw CommandRunnerError.couldNotCreateTemporaryFiles
        }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()

        lock.lock()
        self.process = process
        let wasCancelled = cancellationRequested
        lock.unlock()

        if wasCancelled {
            stop(process)
            throw CancellationError()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if isCancellationRequested {
                stop(process)
                throw CancellationError()
            }
            if Date() >= deadline {
                stop(process)
                throw CommandRunnerError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.025)
        }

        lock.lock()
        self.process = nil
        lock.unlock()

        try checkCancellation()

        try outputHandle.synchronize()
        try errorHandle.synchronize()

        return CommandResult(
            status: process.terminationStatus,
            standardOutput: try Data(contentsOf: outputURL),
            standardError: try Data(contentsOf: errorURL)
        )
    }

    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private func checkCancellation() throws {
        if isCancellationRequested {
            throw CancellationError()
        }
    }

    private func stop(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }

        let graceDeadline = Date().addingTimeInterval(0.4)
        while process.isRunning, Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            // Do not signal by raw PID after the grace period. The PID could be
            // reused if the child exits between a state check and a signal.
            // Foundation keeps the launched child registered and reaps it when
            // it eventually exits.
            process.terminationHandler = { _ in }
        } else {
            process.waitUntilExit()
        }

        lock.lock()
        self.process = nil
        lock.unlock()
    }
}
