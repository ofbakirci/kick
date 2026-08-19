@testable import KickSystem
import XCTest

final class VolumeEligibilityTests: XCTestCase {
    func testIncludesRemovableMediaEvenWhenMacOSMarksItInternal() {
        XCTAssertTrue(
            VolumeEligibility.isExternal(
                isLocal: true,
                isBrowsable: true,
                isInternal: true,
                isEjectable: true,
                isRemovable: true
            )
        )
    }

    func testExcludesTheInternalSystemDisk() {
        XCTAssertFalse(
            VolumeEligibility.isExternal(
                isLocal: true,
                isBrowsable: true,
                isInternal: true,
                isEjectable: false,
                isRemovable: false
            )
        )
    }

    func testExcludesNetworkVolumes() {
        XCTAssertFalse(
            VolumeEligibility.isExternal(
                isLocal: false,
                isBrowsable: true,
                isInternal: false,
                isEjectable: true,
                isRemovable: true
            )
        )
    }

    func testIncludesHiddenSiblingOnAnExternalDisk() {
        XCTAssertTrue(
            VolumeEligibility.isExternal(
                isLocal: true,
                isBrowsable: false,
                isInternal: false,
                isEjectable: true,
                isRemovable: false
            )
        )
    }

    func testIncludesFixedMediaUSBDiskThatIsNeitherEjectableNorRemovable() {
        // USB HDD and SSD enclosures report ejectable=false and removable=false.
        // macOS still marks them as not internal.
        XCTAssertTrue(
            VolumeEligibility.isExternal(
                isLocal: true,
                isBrowsable: true,
                isInternal: false,
                isEjectable: false,
                isRemovable: false
            )
        )
    }

    func testFixedMediaOnAnExternalBusIsThePhysicalDisk() {
        let media = PhysicalIOMediaIdentity(
            registryEntryID: 4_296_856_513,
            mediaUUID: nil,
            bsdName: "disk7",
            mediaSize: 2_000_398_934_016
        )

        XCTAssertEqual(
            PhysicalMediaEligibility.physicalIdentity(
                topmostWholeMedia: media,
                isRemovableOrEjectable: false,
                isExternalLocation: true
            )?.registryEntryID,
            media.registryEntryID
        )
    }

    func testRemovableMediaOnAnInternalReaderIsThePhysicalDisk() {
        let media = PhysicalIOMediaIdentity(
            registryEntryID: 77,
            mediaUUID: nil,
            bsdName: "disk6",
            mediaSize: 32_000_000_000
        )

        XCTAssertEqual(
            PhysicalMediaEligibility.physicalIdentity(
                topmostWholeMedia: media,
                isRemovableOrEjectable: true,
                isExternalLocation: false
            )?.registryEntryID,
            media.registryEntryID
        )
    }

    func testFixedMediaOnAnInternalBusIsNotAPhysicalExternalDisk() {
        let media = PhysicalIOMediaIdentity(
            registryEntryID: 4_294_969_755,
            mediaUUID: nil,
            bsdName: "disk0",
            mediaSize: 500_277_792_768
        )

        XCTAssertNil(
            PhysicalMediaEligibility.physicalIdentity(
                topmostWholeMedia: media,
                isRemovableOrEjectable: false,
                isExternalLocation: false
            )
        )
    }

    func testExternalInterconnectLocationIsRecognized() {
        XCTAssertTrue(
            MediaTransportEligibility.isExternalLocation(physicalInterconnectLocation: "External")
        )
        XCTAssertFalse(
            MediaTransportEligibility.isExternalLocation(physicalInterconnectLocation: "Internal")
        )
        XCTAssertFalse(
            MediaTransportEligibility.isExternalLocation(physicalInterconnectLocation: "File")
        )
        XCTAssertFalse(
            MediaTransportEligibility.isExternalLocation(physicalInterconnectLocation: nil)
        )
    }

    func testVirtualInterfaceIsExcluded() {
        XCTAssertTrue(
            MediaTransportEligibility.isVirtual(
                deviceProtocol: "Virtual Interface",
                physicalInterconnect: nil,
                physicalInterconnectLocation: nil,
                hasDiskImageURL: false
            )
        )
    }

    func testDiskImageMetadataIsExcluded() {
        XCTAssertTrue(
            MediaTransportEligibility.isVirtual(
                deviceProtocol: nil,
                physicalInterconnect: "USB",
                physicalInterconnectLocation: "External",
                hasDiskImageURL: true
            )
        )
    }

    func testFileBackedTransportIsExcluded() {
        XCTAssertTrue(
            MediaTransportEligibility.isVirtual(
                deviceProtocol: nil,
                physicalInterconnect: nil,
                physicalInterconnectLocation: "File",
                hasDiskImageURL: false
            )
        )
    }

    func testPhysicalUSBTransportIsPreserved() {
        XCTAssertFalse(
            MediaTransportEligibility.isVirtual(
                deviceProtocol: "USB",
                physicalInterconnect: "USB",
                physicalInterconnectLocation: "External",
                hasDiskImageURL: false
            )
        )
    }

    func testAPFSVolumesUseTheirLogicalContainerAsCapacityPool() {
        XCTAssertEqual(
            CapacityPoolIdentifier.make(
                fileSystemType: "apfs",
                logicalWholeDiskIdentifier: "disk8",
                fallbackDiskGroupID: "io:42"
            ),
            "apfs:disk8"
        )
    }

    func testNonAPFSVolumesDoNotShareCapacityPool() {
        XCTAssertNil(
            CapacityPoolIdentifier.make(
                fileSystemType: "exfat",
                logicalWholeDiskIdentifier: "disk8",
                fallbackDiskGroupID: "io:42"
            )
        )
    }
}
