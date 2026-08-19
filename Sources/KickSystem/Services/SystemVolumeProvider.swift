import DiskArbitration
import Foundation
import IOKit
import KickCore

public final class SystemVolumeProvider: VolumeProviding {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func mountedExternalDisks() async throws -> [ExternalDisk] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey,
            .volumeUUIDStringKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsBrowsableKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeTypeNameKey,
            .volumeIsReadOnlyKey
        ]

        let mountedURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: []
        ) ?? []

        let session = DASessionCreate(kCFAllocatorDefault)
        var groups: [String: DiskGroup] = [:]

        for url in mountedURLs {
            // A mounted URL can disappear while this snapshot is being read.
            // Ignore only that stale entry and keep the rest of the disk list.
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                continue
            }
            guard values.volumeIsLocal == true else { continue }

            guard let resolution = resolveDiskIdentity(for: url, session: session),
                  !resolution.isVirtual else {
                continue
            }

            let volumeID = values.volumeUUIDString ?? url.path
            let groupID = resolution.identity?.groupingID ?? "volume:\(volumeID)"
            let volume = DiskVolume(
                id: volumeID,
                volumeUUID: values.volumeUUIDString,
                capacityPoolID: CapacityPoolIdentifier.make(
                    fileSystemType: values.volumeTypeName,
                    logicalWholeDiskIdentifier: resolution.logicalWholeDiskIdentifier,
                    fallbackDiskGroupID: groupID
                ),
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                mountURL: url,
                totalCapacity: values.volumeTotalCapacity.map(Int64.init),
                availableCapacity: values.volumeAvailableCapacity.map(Int64.init),
                formatDescription: values.volumeLocalizedFormatDescription,
                isReadOnly: values.volumeIsReadOnly ?? false
            )

            let isEjectableExternal = VolumeEligibility.isExternal(
                isLocal: values.volumeIsLocal,
                isBrowsable: values.volumeIsBrowsable,
                isInternal: values.volumeIsInternal,
                isEjectable: values.volumeIsEjectable,
                isRemovable: values.volumeIsRemovable
            )
            var group = groups[groupID] ?? DiskGroup(
                identity: resolution.identity,
                volumes: [],
                isEjectableExternal: false
            )
            group.volumes.append(volume)
            group.isEjectableExternal = group.isEjectableExternal || isEjectableExternal
            groups[groupID] = group
        }

        return groups.compactMap { _, group -> ExternalDisk? in
            guard group.isEjectableExternal,
                  group.identity?.attachmentID != nil else {
                return nil
            }
            let volumes = group.volumes.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let displayName: String
            if volumes.count == 1 {
                displayName = volumes[0].name
            } else if let deviceName = group.identity?.deviceName, !deviceName.isEmpty {
                displayName = deviceName
            } else {
                displayName = volumes.map(\.name).joined(separator: " + ")
            }

            let persistentID = group.identity?.attachmentID.map { "attachment:\($0)" }
                ?? "volumes:\(volumes.map(\.id).sorted().joined(separator: "|"))"
            return ExternalDisk(
                id: persistentID,
                displayName: displayName,
                deviceName: group.identity?.deviceName,
                mediaUUID: group.identity?.mediaUUID,
                attachmentID: group.identity?.attachmentID,
                wholeDiskIdentifier: group.identity?.bsdName,
                volumes: volumes,
                physicalCapacity: group.identity?.mediaSize
            )
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func resolveDiskIdentity(
        for url: URL,
        session: DASession?
    ) -> ResolvedDiskIdentity? {
        guard let session,
              let volumeDisk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else {
            return nil
        }

        let wholeDisk = DADiskCopyWholeDisk(volumeDisk) ?? volumeDisk
        let bsdName = DADiskGetBSDName(wholeDisk).map { String(cString: $0) }
        let description = DADiskCopyDescription(wholeDisk) as NSDictionary?

        let diskArbitrationUUID = diskArbitrationMediaUUID(from: description)
        let mediaName = description?[kDADiskDescriptionMediaNameKey] as? String
        let deviceModel = description?[kDADiskDescriptionDeviceModelKey] as? String
        let deviceName = [mediaName, deviceModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let mediaSize = (description?[kDADiskDescriptionMediaSizeKey] as? NSNumber)?.int64Value
        let deviceProtocol = description?[kDADiskDescriptionDeviceProtocolKey] as? String
        let mediaScan = IOKitDiskIdentityResolver.scan(for: volumeDisk)
        let isVirtual = mediaScan.isVirtual || MediaTransportEligibility.isVirtual(
            deviceProtocol: deviceProtocol,
            physicalInterconnect: nil,
            physicalInterconnectLocation: nil,
            hasDiskImageURL: false
        )

        if let physical = mediaScan.physicalIdentity {
            return ResolvedDiskIdentity(
                identity: WholeDiskIdentity(
                    groupingID: "io:\(physical.registryEntryID)",
                    attachmentID: physical.registryEntryID,
                    mediaUUID: physical.mediaUUID,
                    bsdName: physical.bsdName ?? bsdName,
                    deviceName: deviceName,
                    mediaSize: physical.mediaSize ?? mediaSize
                ),
                logicalWholeDiskIdentifier: bsdName,
                isVirtual: isVirtual
            )
        }

        let logicalGroupingID = bsdName.map { "logical:\($0)" }
            ?? diskArbitrationUUID.map { "logical-media:\($0)" }
        return ResolvedDiskIdentity(
            identity: logicalGroupingID.map {
                WholeDiskIdentity(
                    groupingID: $0,
                    attachmentID: nil,
                    mediaUUID: nil,
                    bsdName: bsdName,
                    deviceName: deviceName,
                    mediaSize: mediaSize
                )
            },
            logicalWholeDiskIdentifier: bsdName,
            isVirtual: isVirtual
        )
    }

    private func diskArbitrationMediaUUID(from description: NSDictionary?) -> String? {
        guard let rawValue = description?[kDADiskDescriptionMediaUUIDKey] else {
            return nil
        }
        let value = rawValue as CFTypeRef
        guard CFGetTypeID(value) == CFUUIDGetTypeID() else { return nil }
        let uuid = unsafeBitCast(value, to: CFUUID.self)
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
    }
}

enum IOKitDiskIdentityResolver {
    static func scan(for disk: DADisk) -> IOMediaScan {
        var entry = DADiskCopyIOMedia(disk)
        guard entry != IO_OBJECT_NULL else {
            return IOMediaScan(physicalIdentity: nil, isVirtual: false)
        }

        var topmostWholeMedia: PhysicalIOMediaIdentity?
        var topmostWholeMediaIsRemovableOrEjectable = false
        var isExternalLocation = false
        var isVirtual = false
        while entry != IO_OBJECT_NULL {
            let protocolCharacteristics: NSDictionary? = registryProperty(
                entry,
                key: "Protocol Characteristics"
            )
            let physicalInterconnect = protocolCharacteristics?["Physical Interconnect"] as? String
            let physicalInterconnectLocation = protocolCharacteristics?[
                "Physical Interconnect Location"
            ] as? String
            let hasDiskImageURL = registryPropertyValue(entry, key: "DiskImageURL") != nil
            isVirtual = isVirtual || MediaTransportEligibility.isVirtual(
                deviceProtocol: nil,
                physicalInterconnect: physicalInterconnect,
                physicalInterconnectLocation: physicalInterconnectLocation,
                hasDiskImageURL: hasDiskImageURL
            )
            isExternalLocation = isExternalLocation || MediaTransportEligibility.isExternalLocation(
                physicalInterconnectLocation: physicalInterconnectLocation
            )

            if IOObjectConformsTo(entry, "IOMedia") != 0,
               registryProperty(entry, key: "Whole") as Bool? == true {
                var registryEntryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(entry, &registryEntryID) == KERN_SUCCESS {
                    // Walking upward, the last whole IOMedia is the physical
                    // device. A synthesized APFS container is also "Whole", so
                    // keep overwriting until the walk passes the real disk.
                    topmostWholeMedia = PhysicalIOMediaIdentity(
                        registryEntryID: registryEntryID,
                        mediaUUID: registryProperty(entry, key: "UUID"),
                        bsdName: registryProperty(entry, key: kIOBSDNameKey),
                        mediaSize: (registryProperty(entry, key: "Size") as NSNumber?)?.int64Value
                    )
                    topmostWholeMediaIsRemovableOrEjectable =
                        registryProperty(entry, key: "Ejectable") as Bool? == true
                        || registryProperty(entry, key: "Removable") as Bool? == true
                }
            }

            var parent = io_registry_entry_t()
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = result == KERN_SUCCESS ? parent : IO_OBJECT_NULL
        }
        return IOMediaScan(
            physicalIdentity: PhysicalMediaEligibility.physicalIdentity(
                topmostWholeMedia: topmostWholeMedia,
                isRemovableOrEjectable: topmostWholeMediaIsRemovableOrEjectable,
                isExternalLocation: isExternalLocation
            ),
            isVirtual: isVirtual
        )
    }

    static func copyActiveMedia(attachmentID: UInt64) -> io_service_t {
        guard let matching = IORegistryEntryIDMatching(attachmentID) else {
            return IO_OBJECT_NULL
        }
        return IOServiceGetMatchingService(kIOMainPortDefault, matching)
    }

    private static func registryProperty<T>(
        _ entry: io_registry_entry_t,
        key: String
    ) -> T? {
        registryPropertyValue(entry, key: key) as? T
    }

    private static func registryPropertyValue(
        _ entry: io_registry_entry_t,
        key: String
    ) -> Any? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }
}

enum VolumeEligibility {
    static func isExternal(
        isLocal: Bool?,
        isBrowsable: Bool?,
        isInternal: Bool?,
        isEjectable: Bool?,
        isRemovable: Bool?
    ) -> Bool {
        // Hidden sibling volumes can hold files even when Finder does not show
        // them. Keep them in the physical disk snapshot so diagnosis covers the
        // full device. The UI presents the grouped physical disk, not each mount.
        guard isLocal == true else {
            return false
        }
        // Fixed-media USB and Thunderbolt disks (HDD and SSD enclosures) report
        // ejectable=false and removable=false. macOS still marks them as not
        // internal, and that is what makes them external for Kick.
        return isEjectable == true || isRemovable == true || isInternal == false
    }
}

enum MediaTransportEligibility {
    static func isVirtual(
        deviceProtocol: String?,
        physicalInterconnect: String?,
        physicalInterconnectLocation: String?,
        hasDiskImageURL: Bool
    ) -> Bool {
        if hasDiskImageURL {
            return true
        }

        let transportValues = [deviceProtocol, physicalInterconnect]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if transportValues.contains(where: {
            $0.contains("virtual") || $0.contains("disk image")
        }) {
            return true
        }

        return physicalInterconnectLocation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("file") == .orderedSame
    }

    static func isExternalLocation(physicalInterconnectLocation: String?) -> Bool {
        physicalInterconnectLocation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("external") == .orderedSame
    }
}

enum PhysicalMediaEligibility {
    /// A whole IOMedia counts as the physical disk when the media is removable
    /// or ejectable (cards, flash readers, disk images) or when the device sits
    /// on an external bus (fixed-media USB and Thunderbolt enclosures). The
    /// internal system disk matches neither rule.
    static func physicalIdentity(
        topmostWholeMedia: PhysicalIOMediaIdentity?,
        isRemovableOrEjectable: Bool,
        isExternalLocation: Bool
    ) -> PhysicalIOMediaIdentity? {
        guard isRemovableOrEjectable || isExternalLocation else { return nil }
        return topmostWholeMedia
    }
}

enum CapacityPoolIdentifier {
    static func make(
        fileSystemType: String?,
        logicalWholeDiskIdentifier: String?,
        fallbackDiskGroupID: String
    ) -> String? {
        guard fileSystemType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("apfs") == .orderedSame else {
            return nil
        }

        let containerID = logicalWholeDiskIdentifier ?? fallbackDiskGroupID
        return "apfs:\(containerID)"
    }
}

private struct DiskGroup {
    let identity: WholeDiskIdentity?
    var volumes: [DiskVolume]
    var isEjectableExternal: Bool
}

private struct WholeDiskIdentity {
    let groupingID: String
    let attachmentID: UInt64?
    let mediaUUID: String?
    let bsdName: String?
    let deviceName: String?
    let mediaSize: Int64?
}

private struct ResolvedDiskIdentity {
    let identity: WholeDiskIdentity?
    let logicalWholeDiskIdentifier: String?
    let isVirtual: Bool
}

struct IOMediaScan {
    let physicalIdentity: PhysicalIOMediaIdentity?
    let isVirtual: Bool
}

struct PhysicalIOMediaIdentity {
    let registryEntryID: UInt64
    let mediaUUID: String?
    let bsdName: String?
    let mediaSize: Int64?
}
