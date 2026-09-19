import XCTest
@testable import MacDirStat

final class CategorizationTests: XCTestCase {
    func testKnownExtensionsMapToCategories() {
        XCTAssertEqual(FileExtensionMap.category(for: "pdf"), .documents)
        XCTAssertEqual(FileExtensionMap.category(for: "png"), .images)
        XCTAssertEqual(FileExtensionMap.category(for: "mp4"), .video)
        XCTAssertEqual(FileExtensionMap.category(for: "mp3"), .audio)
        XCTAssertEqual(FileExtensionMap.category(for: "swift"), .code)
    }

    func testExtensionLookupIsCaseInsensitive() {
        XCTAssertEqual(FileExtensionMap.category(for: "PNG"), .images)
        XCTAssertEqual(FileExtensionMap.category(for: "Mp4"), .video)
    }

    func testUnknownExtensionFallsBackToOther() {
        XCTAssertEqual(FileExtensionMap.category(for: "wat"), .other)
        XCTAssertEqual(FileExtensionMap.category(for: ""), .other)
    }

    func testEveryCategoryHasDistinctDisplayName() {
        let names = Set(FileCategory.allCases.map(\.displayName))
        XCTAssertEqual(names.count, FileCategory.allCases.count)
    }
}

final class ByteFormatterTests: XCTestCase {
    func testFormatsAreNonEmptyAndScale() {
        XCTAssertFalse(ByteFormatter.string(from: Int64(0)).isEmpty)
        // A megabyte-scale value should not be reported in plain bytes.
        let mb = ByteFormatter.string(from: Int64(5_000_000))
        XCTAssertTrue(mb.contains("MB"), "expected MB in \(mb)")
    }

    func testUInt64OverloadClampsWithoutCrashing() {
        let s = ByteFormatter.string(from: UInt64.max)
        XCTAssertFalse(s.isEmpty)
    }
}
