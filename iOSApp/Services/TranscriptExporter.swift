import Foundation
import UIKit
import CoreText
import UniformTypeIdentifiers

enum TranscriptExportFormat: Equatable {
    case txt, pdf, rtf
    var contentType: UTType {
        switch self {
        case .txt: return .plainText
        case .pdf: return .pdf
        case .rtf: return .rtf
        }
    }
}

@MainActor
enum TranscriptExporter {
    static func data(title: String, text: String, date: Date, format: TranscriptExportFormat) throws -> Data {
        if format == .txt { return Data(text.utf8) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let header = title + "\n" + date.formatted(date: .abbreviated, time: .shortened) + "\n\n"
        let attributed = NSAttributedString(string: header + text, attributes: [
            .font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ])
        if format == .rtf {
            // RTF is editable in Word; this is deliberately not labelled a .docx export.
            return try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                       documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let bounds = page.insetBy(dx: 48, dy: 48)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let path = CGPath(rect: bounds, transform: nil)
        var offset = 0
        var madeProgress = true
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            while offset < attributed.length {
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { madeProgress = false; break }
                context.beginPage()
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: page.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()
                // CoreText ranges are UTF-16 offsets, including CJK, combining marks and emoji.
                offset = visible.location + visible.length
            }
        }
        guard madeProgress, offset == attributed.length else { throw ExportError.pagination }
        return data
    }

    enum ExportError: LocalizedError {
        case pagination
        var errorDescription: String? { "无法完成文字分页，未导出不完整的 PDF。请先使用 TXT 导出。" }
    }
}
