@testable import KickCore
import XCTest

final class BlockingProcessIdentityTests: XCTestCase {
    func testMatchingStableExecutionIdentityIsTheSameProcess() {
        let process = makeProcess()

        XCTAssertTrue(process.hasSameIdentity(as: makeProcess()))
    }

    func testDifferentStartTimeIsNotTheSameProcess() {
        let original = makeProcess()
        let reusedPID = makeProcess(
            startTime: ProcessStartTime(seconds: 101, microseconds: 20)
        )

        XCTAssertFalse(original.hasSameIdentity(as: reusedPID))
    }

    func testDifferentExecutablePathIsNotTheSameProcess() {
        let original = makeProcess()
        let replacement = makeProcess(executablePath: "/Applications/Other.app/Contents/MacOS/Other")

        XCTAssertFalse(original.hasSameIdentity(as: replacement))
    }

    func testMissingStableIdentityOnEitherSideDoesNotMatchAStableIdentity() {
        let stable = makeProcess()
        let missingStartTime = makeProcess(startTime: nil)
        let missingExecutable = makeProcess(executablePath: nil)

        XCTAssertFalse(stable.hasSameIdentity(as: missingStartTime))
        XCTAssertFalse(missingStartTime.hasSameIdentity(as: stable))
        XCTAssertFalse(stable.hasSameIdentity(as: missingExecutable))
        XCTAssertFalse(missingExecutable.hasSameIdentity(as: stable))
    }

    func testLegacyIdentityStillMatchesWhenBothStableFieldsAreUnavailable() {
        let first = makeProcess(executablePath: nil, startTime: nil)
        let second = makeProcess(executablePath: nil, startTime: nil)

        XCTAssertTrue(first.hasSameIdentity(as: second))
    }

    private func makeProcess(
        executablePath: String? = "/Applications/Preview.app/Contents/MacOS/Preview",
        startTime: ProcessStartTime? = ProcessStartTime(seconds: 100, microseconds: 20)
    ) -> BlockingProcess {
        BlockingProcess(
            pid: 404,
            parentPID: 1,
            command: "Preview",
            userID: 501,
            loginName: "user",
            openFiles: [OpenFileReference(path: "/Volumes/Disk/file.pdf", access: .read)],
            executablePath: executablePath,
            startTime: startTime
        )
    }

    func testCurrentFolderReferenceIsNotUnknownAccess() {
        let shell = BlockingProcess(
            pid: 900,
            parentPID: 1,
            command: "zsh",
            userID: 501,
            openFiles: [
                OpenFileReference(path: "/Volumes/Disk", descriptor: "cwd", fileType: "DIR", access: .unknown)
            ]
        )
        let helper = BlockingProcess(
            pid: 901,
            parentPID: 1,
            command: "helper",
            userID: 501,
            openFiles: [
                OpenFileReference(path: "/Volumes/Disk", descriptor: "cwd", fileType: "DIR", access: .unknown),
                OpenFileReference(path: "/Volumes/Disk/a.bin", descriptor: "4", fileType: "REG", access: .unknown)
            ]
        )

        XCTAssertTrue(shell.holdsCurrentFolder)
        XCTAssertFalse(shell.hasUnknownAccess)
        XCTAssertTrue(helper.hasUnknownAccess)
        XCTAssertFalse(shell.hasWritableFiles)
    }
}
