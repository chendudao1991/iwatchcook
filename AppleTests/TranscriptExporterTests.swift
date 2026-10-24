import XCTest
import PDFKit
import UIKit

@MainActor
final class TranscriptExporterTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testTXTMatchesEditedUnicodeTextExactly() throws {
        let text = "中文转写 👩🏽‍💻\n第二行 e\u{301}"
        let data = try TranscriptExporter.data(title: "标题", text: text, date: date, format: .txt)
        XCTAssertEqual(String(data: data, encoding: .utf8), text)
    }

    func testPDFContainsChineseTitleAndTranscript() throws {
        let data = try TranscriptExporter.data(title: "会议笔记", text: "你好，中文转写。", date: date, format: .pdf)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("会议笔记") == true)
        XCTAssertTrue(document.string?.contains("你好") == true)
    }

    func testLongPDFPaginatesAndIncludesFinalParagraph() throws {
        let text = String(repeating: "分页测试：这是一段较长的中文内容，用于验证分页不会截断正文。\n", count: 250)
            + "END-OF-LONG-NOTE"
        let data = try TranscriptExporter.data(title: "长录音", text: text, date: date, format: .pdf)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.page(at: document.pageCount - 1)?.string?.contains("END-OF-LONG-NOTE") == true)
    }

    func testRTFRoundTripContainsChineseAndEmoji() throws {
        let text = "中文会议记录 👩🏽‍💻\n第二段内容"
        let data = try TranscriptExporter.data(title: "记录标题", text: text, date: date, format: .rtf)
        let restored = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                              documentAttributes: nil)
        XCTAssertTrue(restored.string.contains("记录标题"))
        XCTAssertTrue(restored.string.contains(text))
    }
}
