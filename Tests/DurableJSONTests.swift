import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import WristNoteCore
#endif

final class DurableJSONTests: XCTestCase {
    func testFailedWritePreservesMemoryAndLastDurableCheckpoint() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let initial = try DurableJSON(url: url, defaultValue: [String]())
        try initial.commit(["已完成第一段"])

        let failing = try DurableJSON(url: url, defaultValue: [String]()) { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }
        XCTAssertThrowsError(try failing.commit(["第二段尚未落盘"]))
        XCTAssertEqual(failing.value, ["已完成第一段"])
        let restored = try DurableJSON(url: url, defaultValue: [String]())
        XCTAssertEqual(restored.value, ["已完成第一段"])
    }

    func testCorruptIndexDoesNotBecomeAnEmptyWritableCatalog() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let corrupt = Data("{broken-index".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try DurableJSON(url: url, defaultValue: [String]()))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testRetryAfterTransientFailureCommitsSuccessfully() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var failNextWrite = true
        let snapshot = try DurableJSON(url: url, defaultValue: [String]()) { data, url in
            if failNextWrite {
                failNextWrite = false
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try snapshot.commit(["可重试"])); XCTAssertTrue(snapshot.value.isEmpty)
        try snapshot.commit(["重试成功"])
        XCTAssertEqual(snapshot.value, ["重试成功"])
        XCTAssertEqual(try DurableJSON(url: url, defaultValue: [String]()).value, ["重试成功"])
    }
}
