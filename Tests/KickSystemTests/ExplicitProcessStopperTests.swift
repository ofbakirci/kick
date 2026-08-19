import Darwin
import Foundation
import KickCore
@testable import KickSystem
import XCTest

@MainActor
final class ExplicitProcessStopperTests: XCTestCase {
    func testRefusesAnotherUsersProcess() {
        let process = cliProcess(pid: 98_801, userID: getuid() + 1)
        let stopper = makeStopper(metadata: [:], signaler: { _, _ in XCTFail("must not signal"); return 0 })

        let plan = stopper.planStop(of: process)

        XCTAssertEqual(plan.method, .unavailable)
    }

    func testRefusesProtectedAndOwnProcess() {
        let stopper = makeStopper(metadata: [:], signaler: { _, _ in XCTFail("must not signal"); return 0 })

        XCTAssertEqual(stopper.planStop(of: cliProcess(pid: 1, userID: getuid())).method, .unavailable)
        XCTAssertEqual(stopper.planStop(of: cliProcess(pid: getpid(), userID: getuid())).method, .unavailable)
    }

    func testRefusesWhenStableIdentityIsMissing() {
        let process = BlockingProcess(
            pid: 98_802,
            parentPID: 1,
            command: "helper",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file", access: .read)]
        )
        let stopper = makeStopper(metadata: [:], signaler: { _, _ in XCTFail("must not signal"); return 0 })

        XCTAssertEqual(stopper.planStop(of: process).method, .unavailable)
    }

    func testCommandLineToolGetsASingleSIGTERMAfterIdentityCheck() async {
        let process = cliProcess(pid: 98_803, userID: getuid())
        var signals: [(Int32, Int32)] = []
        let stopper = makeStopper(
            metadata: [process.pid: metadata(matching: process)],
            signaler: { pid, signal in signals.append((pid, signal)); return 0 }
        )

        let plan = stopper.planStop(of: process)
        let attempt = await stopper.requestStop(of: process)

        XCTAssertEqual(plan.method, .terminateProcess)
        XCTAssertEqual(attempt.disposition, .requested)
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.0, process.pid)
        XCTAssertEqual(signals.first?.1, SIGTERM)
    }

    func testDoesNotSignalWhenThePIDNowBelongsToAnotherProcess() async {
        let process = cliProcess(pid: 98_804, userID: getuid())
        let recycled = ProcessMetadata(
            pid: process.pid,
            parentPID: 1,
            userID: getuid(),
            command: "other",
            executablePath: "/usr/bin/other",
            startTime: ProcessStartTime(seconds: 999, microseconds: 0)
        )
        var signalCount = 0
        let stopper = makeStopper(
            metadata: [process.pid: recycled],
            signaler: { _, _ in signalCount += 1; return 0 }
        )

        let attempt = await stopper.requestStop(of: process)

        XCTAssertEqual(attempt.disposition, .failed)
        XCTAssertEqual(signalCount, 0)
    }

    func testReportsAlreadyClosedWhenTheProcessIsGone() async {
        let process = cliProcess(pid: 98_805, userID: getuid())
        var signalCount = 0
        let stopper = makeStopper(metadata: [:], signaler: { _, _ in signalCount += 1; return 0 })

        let attempt = await stopper.requestStop(of: process)

        XCTAssertEqual(attempt.disposition, .alreadyClosed)
        XCTAssertEqual(signalCount, 0)
    }

    func testWarnsForWritersAndVirtualMachines() {
        let stopper = makeStopper(metadata: [:], signaler: { _, _ in 0 })
        let writer = BlockingProcess(
            pid: 98_806,
            parentPID: 1,
            command: "cp",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/out", access: .write)],
            executablePath: "/bin/cp",
            startTime: ProcessStartTime(seconds: 1, microseconds: 1)
        )
        let machine = BlockingProcess(
            pid: 98_807,
            parentPID: 1,
            command: "com.apple.Virtualization.VirtualMachine",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/vm.img", access: .read)],
            executablePath: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine",
            startTime: ProcessStartTime(seconds: 1, microseconds: 2)
        )

        XCTAssertTrue(stopper.planStop(of: writer).warning?.contains("incomplete") == true)
        XCTAssertTrue(stopper.planStop(of: machine).warning?.contains("virtual machine") == true)
    }

    func testRealChildProcessStopsAfterOneSIGTERM() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate() } }

        let provider = SystemProcessMetadataProvider()
        // Give the kernel a moment to publish the start time.
        var live: ProcessMetadata?
        for _ in 0..<50 where live == nil {
            live = provider.metadata(for: child.processIdentifier)
            if live == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        let metadata = try XCTUnwrap(live)
        let process = BlockingProcess(
            pid: child.processIdentifier,
            parentPID: metadata.parentPID,
            command: "sleep",
            userID: metadata.userID,
            openFiles: [OpenFileReference(path: "/Volumes/Disk", descriptor: "cwd", access: .unknown)],
            executablePath: metadata.executablePath,
            startTime: metadata.startTime
        )
        let stopper = ExplicitProcessStopper()

        let plan = stopper.planStop(of: process)
        let attempt = await stopper.requestStop(of: process)

        XCTAssertEqual(plan.method, .terminateProcess)
        XCTAssertEqual(attempt.disposition, .requested)
        let deadline = Date().addingTimeInterval(3)
        while child.isRunning, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
    }

    // MARK: - Helpers

    private func makeStopper(
        metadata: [Int32: ProcessMetadata],
        signaler: @escaping (Int32, Int32) -> Int32
    ) -> ExplicitProcessStopper {
        ExplicitProcessStopper(
            currentUserID: getuid(),
            currentProcessID: getpid(),
            metadataProvider: StubMetadataProvider(metadataByPID: metadata),
            signaler: signaler
        )
    }

    private func cliProcess(pid: Int32, userID: UInt32) -> BlockingProcess {
        BlockingProcess(
            pid: pid,
            parentPID: 1,
            command: "sleep",
            userID: userID,
            openFiles: [OpenFileReference(path: "/Volumes/Disk", descriptor: "cwd", access: .unknown)],
            executablePath: "/bin/sleep",
            startTime: ProcessStartTime(seconds: 100, microseconds: 7)
        )
    }

    private func metadata(matching process: BlockingProcess) -> ProcessMetadata {
        ProcessMetadata(
            pid: process.pid,
            parentPID: process.parentPID ?? 1,
            userID: process.userID ?? getuid(),
            command: process.command,
            executablePath: process.executablePath,
            startTime: process.startTime ?? ProcessStartTime(seconds: 0, microseconds: 0)
        )
    }
}

private struct StubMetadataProvider: ProcessMetadataProviding {
    let metadataByPID: [Int32: ProcessMetadata]

    func metadata(for pid: Int32) -> ProcessMetadata? {
        metadataByPID[pid]
    }
}
