import Foundation
@testable import KickCore
import XCTest

final class ExternalDiskCapacityTests: XCTestCase {
    func testSharedAPFSPoolIsCountedOnceUsingTheConservativeValue() {
        let disk = fixtureDisk(volumes: [
            fixtureVolume(id: "one", poolID: "apfs:disk8", total: 1_000, available: 420),
            fixtureVolume(id: "two", poolID: "apfs:disk8", total: 1_000, available: 380)
        ])

        XCTAssertEqual(disk.totalCapacity, 1_000)
        XCTAssertEqual(disk.availableCapacity, 380)
    }

    func testIndependentCapacityPoolsAreSummed() {
        let disk = fixtureDisk(volumes: [
            fixtureVolume(id: "one", poolID: "apfs:disk8", total: 1_000, available: 400),
            fixtureVolume(id: "two", poolID: "apfs:disk9", total: 2_000, available: 700)
        ])

        XCTAssertEqual(disk.totalCapacity, 3_000)
        XCTAssertEqual(disk.availableCapacity, 1_100)
    }

    func testPhysicalCapacityRemainsTheTotalDiskCapacity() {
        let disk = fixtureDisk(
            volumes: [
                fixtureVolume(id: "one", poolID: "apfs:disk8", total: 900, available: 400),
                fixtureVolume(id: "two", poolID: "apfs:disk8", total: 900, available: 400)
            ],
            physicalCapacity: 1_000
        )

        XCTAssertEqual(disk.totalCapacity, 1_000)
        XCTAssertEqual(disk.availableCapacity, 400)
    }

    private func fixtureDisk(
        volumes: [DiskVolume],
        physicalCapacity: Int64? = nil
    ) -> ExternalDisk {
        ExternalDisk(
            id: "attachment:42",
            displayName: "Disk",
            attachmentID: 42,
            volumes: volumes,
            physicalCapacity: physicalCapacity
        )
    }

    private func fixtureVolume(
        id: String,
        poolID: String?,
        total: Int64,
        available: Int64
    ) -> DiskVolume {
        DiskVolume(
            id: id,
            capacityPoolID: poolID,
            name: id,
            mountURL: URL(fileURLWithPath: "/Volumes/\(id)"),
            totalCapacity: total,
            availableCapacity: available
        )
    }
}
