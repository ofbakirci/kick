import Foundation
import KickCore

public final class FileManagerDiskEjector: DiskEjecting {
    private let fileManager: FileManager
    private let identityValidator: DiskIdentityValidating

    public init(
        fileManager: FileManager = .default,
        identityValidator: DiskIdentityValidating = SystemDiskIdentityValidator()
    ) {
        self.fileManager = fileManager
        self.identityValidator = identityValidator
    }

    public func eject(_ disk: ExternalDisk) async throws {
        try await identityValidator.validate(disk)

        guard let mountURL = disk.primaryMountURL else {
            throw EjectionFailure(
                message: "This disk is no longer mounted.",
                kind: .identityChanged
            )
        }

        try await withCheckedThrowingContinuation { continuation in
            fileManager.unmountVolume(
                at: mountURL,
                options: [.allPartitionsAndEjectDisk, .withoutUI]
            ) { error in
                guard let error = error as NSError? else {
                    continuation.resume(returning: ())
                    return
                }

                let pid = (
                    error.userInfo[NSFileManagerUnmountDissentingProcessIdentifierErrorKey]
                        as? NSNumber
                )?.int32Value
                let kind = EjectionErrorClassifier.kind(for: error)
                continuation.resume(
                    throwing: EjectionFailure(
                        message: error.localizedDescription,
                        dissentingProcessID: pid,
                        kind: kind,
                        underlyingDomain: error.domain,
                        underlyingCode: error.code
                    )
                )
            }
        }
    }
}

enum EjectionErrorClassifier {
    static func kind(for error: NSError) -> EjectionFailureKind {
        error.domain == NSCocoaErrorDomain && error.code == NSFileManagerUnmountBusyError
            ? .busy
            : .other
    }
}

public protocol DiskIdentityValidating {
    func validate(_ disk: ExternalDisk) async throws
}

public struct SystemDiskIdentityValidator: DiskIdentityValidating {
    private let provider: VolumeProviding

    public init(provider: VolumeProviding = SystemVolumeProvider()) {
        self.provider = provider
    }

    public func validate(_ disk: ExternalDisk) async throws {
        guard let expectedAttachmentID = disk.attachmentID else {
            throw identityFailure()
        }

        let currentDisks = try await provider.mountedExternalDisks()
        guard let current = currentDisks.first(where: {
            $0.attachmentID == expectedAttachmentID
        }) else {
            throw identityFailure()
        }

        let expectedVolumeUUIDs = Set(disk.volumes.compactMap(\.volumeUUID))
        let currentVolumeUUIDs = Set(current.volumes.compactMap(\.volumeUUID))
        let expectedPaths = Set(disk.mountURLs.map(\.standardizedFileURL.path))
        let currentPaths = Set(current.mountURLs.map(\.standardizedFileURL.path))
        guard current.attachmentID == expectedAttachmentID,
              expectedVolumeUUIDs == currentVolumeUUIDs,
              expectedPaths == currentPaths,
              disk.mediaUUID == current.mediaUUID else {
            throw identityFailure()
        }
    }

    private func identityFailure() -> EjectionFailure {
        EjectionFailure(
            message: "The disk identity changed. Refresh the list and try again.",
            kind: .identityChanged
        )
    }
}
