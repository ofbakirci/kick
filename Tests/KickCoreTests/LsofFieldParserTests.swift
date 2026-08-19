import Foundation
@testable import KickCore
import XCTest

final class LsofFieldParserTests: XCTestCase {
    func testParsesMultipleFilesAndProcesses() {
        let data = fieldData([
            "p101", "R1", "cPhotos", "u501", "Luser",
            "\nf3", "ar", "tREG", "n/Volumes/Drive/Library.photoslibrary",
            "\nf4", "au", "tREG", "n/Volumes/Drive/catalog.db",
            "\np202", "R101", "cmdworker", "u501", "Luser",
            "\nf7", "ar", "tDIR", "n/Volumes/Drive"
        ])

        let result = LsofFieldParser().parse(data)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].pid, 101)
        XCTAssertEqual(result[0].command, "Photos")
        XCTAssertEqual(result[0].openFiles.count, 2)
        XCTAssertEqual(result[0].openFiles[1].access, .readWrite)
        XCTAssertTrue(result[0].hasWritableFiles)
        XCTAssertEqual(result[1].parentPID, 101)
    }

    func testKeepsUnicodeAndNewlinesInsideAPath() {
        let path = "/Volumes/Arşiv/çekim\nfinal.mov"
        let data = fieldData([
            "p303", "R1", "cPreview", "u501",
            "\nf8", "ar", "tREG", "n\(path)"
        ])

        let result = LsofFieldParser().parse(data)

        XCTAssertEqual(result.first?.openFiles.first?.path, path)
    }

    func testIgnoresMalformedProcessRecords() {
        let data = fieldData([
            "pnot-a-pid", "cBroken", "\nf3", "n/Volumes/Drive/file",
            "\np404", "cGood", "\nf4", "n/Volumes/Drive/good"
        ])

        let result = LsofFieldParser().parse(data)

        XCTAssertEqual(result.map(\.pid), [404])
    }

    func testMergesRepeatedProcessRecordsWithoutDuplicateFiles() {
        let data = fieldData([
            "p505", "R1", "cFinder", "u501",
            "\nf3", "ar", "tDIR", "n/Volumes/Drive",
            "\np505", "R1", "cFinder", "u501",
            "\nf3", "ar", "tDIR", "n/Volumes/Drive"
        ])

        let result = LsofFieldParser().parse(data)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].openFiles.count, 1)
    }

    private func fieldData(_ fields: [String]) -> Data {
        var data = Data()
        for field in fields {
            data.append(field.data(using: .utf8)!)
            data.append(0)
        }
        return data
    }
}
