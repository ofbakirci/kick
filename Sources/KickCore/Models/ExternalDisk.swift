import Foundation

public struct DiskVolume: Identifiable, Hashable {
    public let id: String
    public let volumeUUID: String?
    public let capacityPoolID: String?
    public let name: String
    public let mountURL: URL
    public let totalCapacity: Int64?
    public let availableCapacity: Int64?
    public let formatDescription: String?
    public let isReadOnly: Bool

    public init(
        id: String,
        volumeUUID: String? = nil,
        capacityPoolID: String? = nil,
        name: String,
        mountURL: URL,
        totalCapacity: Int64? = nil,
        availableCapacity: Int64? = nil,
        formatDescription: String? = nil,
        isReadOnly: Bool = false
    ) {
        self.id = id
        self.volumeUUID = volumeUUID
        self.capacityPoolID = capacityPoolID
        self.name = name
        self.mountURL = mountURL
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.formatDescription = formatDescription
        self.isReadOnly = isReadOnly
    }
}

public struct ExternalDisk: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let deviceName: String?
    public let mediaUUID: String?
    public let attachmentID: UInt64?
    public let wholeDiskIdentifier: String?
    public let volumes: [DiskVolume]
    public let physicalCapacity: Int64?

    public init(
        id: String,
        displayName: String,
        deviceName: String? = nil,
        mediaUUID: String? = nil,
        attachmentID: UInt64? = nil,
        wholeDiskIdentifier: String? = nil,
        volumes: [DiskVolume],
        physicalCapacity: Int64? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.deviceName = deviceName
        self.mediaUUID = mediaUUID
        self.attachmentID = attachmentID
        self.wholeDiskIdentifier = wholeDiskIdentifier
        self.volumes = volumes
        self.physicalCapacity = physicalCapacity
    }

    public var primaryMountURL: URL? {
        volumes.first?.mountURL
    }

    public var mountURLs: [URL] {
        volumes.map(\.mountURL)
    }

    public var totalCapacity: Int64? {
        physicalCapacity ?? pooledCapacity(\.totalCapacity)
    }

    public var availableCapacity: Int64? {
        pooledCapacity(\.availableCapacity)
    }

    public var formatSummary: String {
        let formats = Array(Set(volumes.compactMap(\.formatDescription))).sorted()
        return formats.isEmpty ? "External disk" : formats.joined(separator: " + ")
    }

    private func pooledCapacity(_ keyPath: KeyPath<DiskVolume, Int64?>) -> Int64? {
        var capacitiesByPool: [String: Int64] = [:]

        for volume in volumes {
            guard let capacity = volume[keyPath: keyPath] else { continue }
            let poolID = volume.capacityPoolID ?? "volume:\(volume.id)"
            if let existing = capacitiesByPool[poolID] {
                // APFS volumes in one container report the same shared pool. If
                // quotas differ, use the smaller value so Kick never overstates it.
                capacitiesByPool[poolID] = min(existing, capacity)
            } else {
                capacitiesByPool[poolID] = capacity
            }
        }

        guard !capacitiesByPool.isEmpty else { return nil }
        return capacitiesByPool.values.reduce(0, +)
    }
}
