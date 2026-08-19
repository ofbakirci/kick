import Foundation
import KickCore
@testable import KickSystem
import XCTest

final class EjectionSafetyTests: XCTestCase {
    func testOnlyCocoaUnmountBusyErrorEnablesBlockerRelease() {
        let busy = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileManagerUnmountBusyError
        )
        let permission = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let posixBusy = NSError(domain: NSPOSIXErrorDomain, code: 16)

        XCTAssertEqual(EjectionErrorClassifier.kind(for: busy), .busy)
        XCTAssertEqual(EjectionErrorClassifier.kind(for: permission), .other)
        XCTAssertEqual(EjectionErrorClassifier.kind(for: posixBusy), .other)
    }

    func testIdentityValidatorAcceptsTheSameMountedDisk() async throws {
        let disk = fixtureDisk(
            id: "attachment:41",
            volumeUUID: "volume-1",
            attachmentID: 41
        )
        let validator = SystemDiskIdentityValidator(
            provider: IdentityVolumeProvider(disks: [disk])
        )

        try await validator.validate(disk)
    }

    func testIdentityValidatorRejectsAReplacementAtTheSamePath() async {
        let original = fixtureDisk(
            id: "attachment:41",
            volumeUUID: "volume-1",
            attachmentID: 41
        )
        let replacement = fixtureDisk(
            id: "attachment:42",
            volumeUUID: "volume-2",
            attachmentID: 42
        )
        let validator = SystemDiskIdentityValidator(
            provider: IdentityVolumeProvider(disks: [replacement])
        )

        do {
            try await validator.validate(original)
            XCTFail("Expected identity validation to fail")
        } catch let error as EjectionFailure {
            XCTAssertEqual(error.kind, .identityChanged)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIdentityValidatorRejectsACloneWithTheSameUUIDAndPath() async {
        let original = fixtureDisk(
            id: "attachment:41",
            volumeUUID: "duplicated-volume",
            attachmentID: 41
        )
        let clone = fixtureDisk(
            id: "attachment:42",
            volumeUUID: "duplicated-volume",
            attachmentID: 42
        )
        let validator = SystemDiskIdentityValidator(
            provider: IdentityVolumeProvider(disks: [clone])
        )

        await assertIdentityChanged {
            try await validator.validate(original)
        }
    }

    func testIdentityValidatorRejectsDiskWithoutPhysicalAttachmentIdentity() async {
        let disk = fixtureDisk(
            id: "volumes:volume-1",
            volumeUUID: "volume-1",
            attachmentID: nil
        )
        let validator = SystemDiskIdentityValidator(
            provider: IdentityVolumeProvider(disks: [disk])
        )

        await assertIdentityChanged {
            try await validator.validate(disk)
        }
    }

    private func fixtureDisk(
        id: String,
        volumeUUID: String,
        attachmentID: UInt64?
    ) -> ExternalDisk {
        ExternalDisk(
            id: id,
            displayName: "Disk",
            mediaUUID: "physical-media",
            attachmentID: attachmentID,
            volumes: [
                DiskVolume(
                    id: volumeUUID,
                    volumeUUID: volumeUUID,
                    name: "Disk",
                    mountURL: URL(fileURLWithPath: "/Volumes/Disk")
                )
            ]
        )
    }

    private func assertIdentityChanged(
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected identity validation to fail", file: file, line: line)
        } catch let error as EjectionFailure {
            XCTAssertEqual(error.kind, .identityChanged, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private struct IdentityVolumeProvider: VolumeProviding {
    let disks: [ExternalDisk]

    func mountedExternalDisks() async throws -> [ExternalDisk] { disks }
}
