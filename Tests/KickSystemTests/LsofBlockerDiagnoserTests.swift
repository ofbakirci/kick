import Foundation
import KickCore
@testable import KickSystem
import XCTest

final class LsofBlockerDiagnoserTests: XCTestCase {
    func testUsesFilesystemModeWithoutAShellForEveryVolume() async throws {
        let runner = RecordingRunner(results: [
            CommandResult(status: 0, standardOutput: processData(pid: 11), standardError: Data()),
            CommandResult(status: 0, standardOutput: processData(pid: 12), standardError: Data())
        ])
        let disk = ExternalDisk(
            id: "disk",
            displayName: "Disk",
            volumes: [
                DiskVolume(id: "a", name: "A", mountURL: URL(fileURLWithPath: "/Volumes/A")),
                DiskVolume(id: "b", name: "B", mountURL: URL(fileURLWithPath: "/Volumes/B"))
            ]
        )

        let result = try await LsofBlockerDiagnoser(runner: runner).blockers(on: disk)

        XCTAssertEqual(result.map(\.pid), [11, 12])
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].executable.path, "/usr/sbin/lsof")
        XCTAssertEqual(
            runner.calls[0].arguments,
            ["-S", "2", "-nP", "-F0pcuLftanR", "+c", "0", "+f", "--", "/Volumes/A"]
        )
        XCTAssertEqual(runner.calls[1].arguments.last, "/Volumes/B")
    }

    func testNonzeroCommandWithErrorIsNotReportedAsClean() async {
        let runner = RecordingRunner(results: [
            CommandResult(
                status: 1,
                standardOutput: Data(),
                standardError: Data("permission denied".utf8)
            )
        ])
        let diagnoser = LsofBlockerDiagnoser(runner: runner)

        do {
            _ = try await diagnoser.blockers(on: testDisk)
            XCTFail("Expected diagnosis to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("permission denied"))
        }
    }

    func testExitStatusOneWithNoOutputOrErrorIsClean() async throws {
        let runner = RecordingRunner(results: [
            CommandResult(status: 1, standardOutput: Data(), standardError: Data())
        ])

        let result = try await LsofBlockerDiagnoser(runner: runner).blockers(on: testDisk)

        XCTAssertTrue(result.isEmpty)
    }

    func testEnrichesParsedProcessWithStableExecutionMetadata() async throws {
        let runner = RecordingRunner(results: [
            CommandResult(status: 0, standardOutput: processData(pid: 42), standardError: Data())
        ])
        let metadata = ProcessMetadata(
            pid: 42,
            parentPID: 1,
            userID: 501,
            command: "Preview",
            executablePath: "/Applications/Preview.app/Contents/MacOS/Preview",
            startTime: ProcessStartTime(seconds: 100, microseconds: 25)
        )
        let diagnoser = LsofBlockerDiagnoser(
            runner: runner,
            metadataProvider: StubProcessMetadataProvider(metadataByPID: [42: metadata])
        )

        let result = try await diagnoser.blockers(on: testDisk)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].executablePath, metadata.executablePath)
        XCTAssertEqual(result[0].startTime, metadata.startTime)
        XCTAssertFalse(result[0].isSystemDissent)
    }

    func testSynthesizesBlockerFromMacOSDissentPIDWhenLsofIsEmpty() async throws {
        let runner = RecordingRunner(results: [
            CommandResult(status: 1, standardOutput: Data(), standardError: Data())
        ])
        let metadata = ProcessMetadata(
            pid: 77,
            parentPID: 1,
            userID: 501,
            command: "com.example.Holder",
            executablePath: "/Applications/Holder.app/Contents/MacOS/Holder",
            startTime: ProcessStartTime(seconds: 200, microseconds: 50)
        )
        let diagnoser = LsofBlockerDiagnoser(
            runner: runner,
            metadataProvider: StubProcessMetadataProvider(metadataByPID: [77: metadata])
        )

        let result = try await diagnoser.blockers(on: testDisk, dissentingProcessID: 77)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].pid, 77)
        XCTAssertEqual(result[0].command, metadata.command)
        XCTAssertEqual(result[0].openFiles, [])
        XCTAssertEqual(result[0].executablePath, metadata.executablePath)
        XCTAssertEqual(result[0].startTime, metadata.startTime)
        XCTAssertTrue(result[0].isSystemDissent)
    }

    func testDissentPIDAlreadyFoundByLsofIsNotDuplicated() async throws {
        let runner = RecordingRunner(results: [
            CommandResult(status: 0, standardOutput: processData(pid: 88), standardError: Data())
        ])
        let metadata = ProcessMetadata(
            pid: 88,
            parentPID: 1,
            userID: 501,
            command: "Preview",
            executablePath: "/Applications/Preview.app/Contents/MacOS/Preview",
            startTime: ProcessStartTime(seconds: 300, microseconds: 75)
        )
        let diagnoser = LsofBlockerDiagnoser(
            runner: runner,
            metadataProvider: StubProcessMetadataProvider(metadataByPID: [88: metadata])
        )

        let result = try await diagnoser.blockers(on: testDisk, dissentingProcessID: 88)

        XCTAssertEqual(result.map(\.pid), [88])
        XCTAssertEqual(result[0].openFiles.count, 1)
        XCTAssertEqual(result[0].startTime, metadata.startTime)
    }

    func testEnrichesParsedProcessWithItsParentApplication() async throws {
        let runner = RecordingRunner(results: [
            CommandResult(status: 0, standardOutput: processData(pid: 91), standardError: Data())
        ])
        let metadata = ProcessMetadata(
            pid: 91,
            parentPID: 40,
            userID: 501,
            command: "zsh",
            executablePath: "/bin/zsh",
            startTime: ProcessStartTime(seconds: 400, microseconds: 1)
        )
        let terminal = ParentApplication(pid: 40, name: "Terminal", bundleIdentifier: "com.apple.Terminal")
        let diagnoser = LsofBlockerDiagnoser(
            runner: runner,
            metadataProvider: StubProcessMetadataProvider(
                metadataByPID: [91: metadata],
                parentApplicationsByPID: [91: terminal]
            )
        )

        let result = try await diagnoser.blockers(on: testDisk)

        XCTAssertEqual(result.first?.parentApplication, terminal)
    }

    private var testDisk: ExternalDisk {
        ExternalDisk(
            id: "disk",
            displayName: "Disk",
            volumes: [
                DiskVolume(
                    id: "volume",
                    name: "Disk",
                    mountURL: URL(fileURLWithPath: "/Volumes/Disk")
                )
            ]
        )
    }

    private func processData(pid: Int32) -> Data {
        let fields = [
            "p\(pid)", "R1", "cPreview", "u501", "Luser",
            "\nf3", "ar", "tREG", "n/Volumes/Disk/file"
        ]
        var data = Data()
        for field in fields {
            data.append(Data(field.utf8))
            data.append(0)
        }
        return data
    }
}

private struct StubProcessMetadataProvider: ProcessMetadataProviding {
    let metadataByPID: [Int32: ProcessMetadata]
    var parentApplicationsByPID: [Int32: ParentApplication] = [:]

    func metadata(for pid: Int32) -> ProcessMetadata? {
        metadataByPID[pid]
    }

    func parentApplication(for pid: Int32) -> ParentApplication? {
        parentApplicationsByPID[pid]
    }
}

private final class RecordingRunner: CommandRunning {
    struct Call {
        let executable: URL
        let arguments: [String]
    }

    private var results: [CommandResult]
    private(set) var calls: [Call] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return results.removeFirst()
    }
}
