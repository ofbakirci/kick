import Darwin
import Foundation
import KickCore

public enum DiagnosisError: LocalizedError {
    case lsofFailed(String)
    case incompleteOutput(String)

    public var errorDescription: String? {
        switch self {
        case .lsofFailed(let message):
            return message.isEmpty ? "macOS could not inspect the disk." : message
        case .incompleteOutput(let message):
            return message.isEmpty
                ? "macOS returned an incomplete process list."
                : "macOS returned an incomplete process list. \(message)"
        }
    }
}

public final class LsofBlockerDiagnoser: DissentAwareBlockerDiagnosing {
    private let runner: CommandRunning
    private let parser: LsofFieldParser
    private let metadataProvider: ProcessMetadataProviding

    public init(
        runner: CommandRunning = SystemCommandRunner(),
        parser: LsofFieldParser = LsofFieldParser()
    ) {
        self.runner = runner
        self.parser = parser
        self.metadataProvider = SystemProcessMetadataProvider()
    }

    init(
        runner: CommandRunning,
        parser: LsofFieldParser = LsofFieldParser(),
        metadataProvider: ProcessMetadataProviding
    ) {
        self.runner = runner
        self.parser = parser
        self.metadataProvider = metadataProvider
    }

    public func blockers(on disk: ExternalDisk) async throws -> [BlockingProcess] {
        try await blockers(on: disk, dissentingProcessID: nil)
    }

    public func blockers(
        on disk: ExternalDisk,
        dissentingProcessID: Int32?
    ) async throws -> [BlockingProcess] {
        var byPID: [Int32: BlockingProcess] = [:]
        var order: [Int32] = []

        for mountURL in disk.mountURLs {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: [
                    "-S",
                    "2",
                    "-nP",
                    "-F0pcuLftanR",
                    "+c",
                    "0",
                    "+f",
                    "--",
                    mountURL.path
                ]
            )
            let parsed = parser.parse(result.standardOutput)
                .filter { $0.pid != getpid() }
                .map(enrich)

            if result.status != 0 {
                if !parsed.isEmpty {
                    throw DiagnosisError.incompleteOutput(result.errorText)
                }
                if result.status != 1 || !result.errorText.isEmpty {
                    throw DiagnosisError.lsofFailed(result.errorText)
                }
            }

            for process in parsed {
                if let existing = byPID[process.pid] {
                    byPID[process.pid] = existing.merging(process)
                } else {
                    order.append(process.pid)
                    byPID[process.pid] = process
                }
            }
        }

        if let dissentingProcessID,
           dissentingProcessID > 1,
           dissentingProcessID != getpid(),
           byPID[dissentingProcessID] == nil,
           let metadata = metadataProvider.metadata(for: dissentingProcessID) {
            order.append(dissentingProcessID)
            byPID[dissentingProcessID] = metadata.blockerReportedByMacOS(
                parentApplication: metadataProvider.parentApplication(for: dissentingProcessID)
            )
        }

        return order.compactMap { byPID[$0] }
    }

    private func enrich(_ process: BlockingProcess) -> BlockingProcess {
        guard let metadata = metadataProvider.metadata(for: process.pid) else {
            return process
        }
        return process.withExecutionIdentity(
            executablePath: metadata.executablePath,
            startTime: metadata.startTime,
            parentApplication: metadataProvider.parentApplication(for: process.pid)
        )
    }
}
