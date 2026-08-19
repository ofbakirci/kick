import Darwin
import KickCore
@testable import KickSystem
import XCTest

@MainActor
final class GracefulProcessReleaserTests: XCTestCase {
    func testProtectsVirtualMachineProcess() async {
        let process = BlockingProcess(
            pid: 98_765,
            parentPID: 1,
            command: "com.apple.Virtualization.VirtualMachine",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/VM.img", access: .read)]
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let result = await releaser.requestRelease(of: [process])

        XCTAssertEqual(result.first?.disposition, .needsManualAction)
        XCTAssertTrue(result.first?.message.contains("virtual machine") == true)
    }

    func testProtectsWritableProcess() async {
        let process = BlockingProcess(
            pid: 98_766,
            parentPID: 1,
            command: "CopyTool",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/copy", access: .write)]
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let result = await releaser.requestRelease(of: [process])

        XCTAssertEqual(result.first?.disposition, .needsManualAction)
        XCTAssertTrue(result.first?.message.contains("Finish its work") == true)
    }

    func testProtectsDifferentUser() async {
        let process = BlockingProcess(
            pid: 98_767,
            parentPID: 1,
            command: "Service",
            userID: getuid() + 1,
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file", access: .read)]
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let result = await releaser.requestRelease(of: [process])

        XCTAssertEqual(result.first?.disposition, .needsManualAction)
    }

    func testDoesNotSignalACommandLineProcess() async {
        let process = BlockingProcess(
            pid: 98_768,
            parentPID: 1,
            command: "KickHold",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file", access: .read)]
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])
        let result = await releaser.requestRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(result.first?.disposition, .needsManualAction)
    }

    func testRefusesAutomaticQuitWhenStableExecutionIdentityIsMissing() async {
        let process = BlockingProcess(
            pid: 98_770,
            parentPID: 1,
            command: "Preview",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file.pdf", access: .read)]
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])
        let result = await releaser.requestRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(plan.first?.message, "Kick cannot verify this app's process identity.")
        XCTAssertEqual(result.first?.disposition, .needsManualAction)
        XCTAssertEqual(result.first?.message, "Kick cannot verify this app's process identity.")
    }

    func testProtectsUnknownFileAccess() async {
        let process = BlockingProcess(
            pid: 98_769,
            parentPID: 1,
            command: "UnknownHelper",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file", access: .unknown)]
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let result = await releaser.requestRelease(of: [process])

        XCTAssertEqual(result.first?.disposition, .needsManualAction)
        XCTAssertTrue(result.first?.message.contains("cannot verify") == true)
    }

    func testProtectsDissentOnlyProcessWithoutOpenPathEvidence() {
        let process = BlockingProcess(
            pid: 98_771,
            parentPID: 1,
            command: "Preview",
            userID: getuid(),
            openFiles: [],
            executablePath: "/System/Applications/Preview.app/Contents/MacOS/Preview",
            startTime: ProcessStartTime(seconds: 100, microseconds: 20),
            isSystemDissent: true
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(
            plan.first?.message,
            "Kick cannot verify how this app uses the disk. Close it yourself."
        )
    }

    func testProtectsFinder() {
        let process = BlockingProcess(
            pid: 98_772,
            parentPID: 1,
            command: "Finder",
            userID: getuid(),
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file", access: .read)],
            executablePath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            startTime: ProcessStartTime(seconds: 100, microseconds: 30)
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(plan.first?.message, "Close the file or wait for macOS to finish.")
    }

    func testShellHoldingTheCurrentFolderGetsTerminalGuidance() {
        let process = BlockingProcess(
            pid: 98_773,
            parentPID: 1,
            command: "zsh",
            userID: getuid(),
            openFiles: [
                OpenFileReference(path: "/Volumes/Disk", descriptor: "cwd", fileType: "DIR", access: .unknown)
            ],
            executablePath: "/bin/zsh",
            startTime: ProcessStartTime(seconds: 100, microseconds: 40)
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(plan.first?.message, "Change the terminal folder or close its window.")
    }

    func testCommandLineToolHoldingTheCurrentFolderGetsCloseGuidance() {
        let process = BlockingProcess(
            pid: 98_774,
            parentPID: 1,
            command: "sleep",
            userID: getuid(),
            openFiles: [
                OpenFileReference(path: "/Volumes/Disk", descriptor: "cwd", fileType: "DIR", access: .unknown)
            ],
            executablePath: "/bin/sleep",
            startTime: ProcessStartTime(seconds: 100, microseconds: 50)
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(
            plan.first?.message,
            "Its current folder is on this disk. Close this command or helper, then try again."
        )
    }

    func testTransferToolWithUnknownAccessGetsTransferGuidance() {
        let process = BlockingProcess(
            pid: 98_775,
            parentPID: 1,
            command: "rsync",
            userID: getuid(),
            openFiles: [
                OpenFileReference(path: "/Volumes/Disk/a", descriptor: "5", fileType: "REG", access: .unknown)
            ],
            executablePath: "/usr/bin/rsync",
            startTime: ProcessStartTime(seconds: 100, microseconds: 60)
        )
        let releaser = GracefulProcessReleaser(currentProcessID: getpid())

        let plan = releaser.planRelease(of: [process])

        XCTAssertEqual(plan.first?.strategy, .manualAction)
        XCTAssertEqual(plan.first?.message, "Wait for the transfer or backup to finish.")
    }
}
