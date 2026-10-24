import Foundation
import AVFoundation
import Combine

struct WatchRecording: Codable, Identifiable {
    var metadata: RecordingMetadata
    var id: UUID { metadata.id }
    var finalized = false
    var acknowledged = false
    var syncError: String?
}

@MainActor
final class WatchLibrary: ObservableObject {
    @Published private(set) var items: [WatchRecording] = []
    @Published var error: String?
    private let root: URL
    private let index: URL

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchRecordings", isDirectory: true)
        index = root.appendingPathComponent("index.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) {
                items = try JSONDecoder().decode([WatchRecording].self, from: Data(contentsOf: index))
                // A crash/relaunch may leave an open recording. Recover its readable PCM frames.
                for i in items.indices where !items[i].finalized {
                    do {
                        let file = try AVAudioFile(forReading: audioURL(items[i].id))
                        guard file.length > 0 else { continue }
                        items[i].metadata.duration = Double(file.length) / file.processingFormat.sampleRate
                        items[i].finalized = true
                        items[i].syncError = "录音被中断，已恢复可读取部分。"
                    } catch {
                        items[i].syncError = "中断文件无法自动恢复，保留原文件：\(error.localizedDescription)"
                    }
                }
                try persist()
            }
        } catch { self.error = "录音库恢复失败：\(error.localizedDescription)。已有文件不会被覆盖。" }
    }

    func audioURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).caf") }

    func register(_ metadata: RecordingMetadata) throws {
        guard error == nil else { throw LibraryError.unavailable }
        items.insert(WatchRecording(metadata: metadata), at: 0)
        do { try persist() } catch { items.removeAll { $0.id == metadata.id }; throw error }
    }

    func finish(_ id: UUID, duration: Double) throws {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].metadata.duration = duration
        items[i].finalized = duration > 0
        if duration == 0 { items[i].syncError = "没有可用音频，未加入同步队列。" }
        try persist()
    }

    func acknowledge(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].acknowledged = true
        items[i].syncError = nil
        do { try persist() } catch { self.error = error.localizedDescription }
    }

    func transferFailed(_ id: UUID, message: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].syncError = message
        do { try persist() } catch { self.error = error.localizedDescription }
    }

    func removeAcknowledged(_ id: UUID) throws {
        guard let item = items.first(where: { $0.id == id }), item.acknowledged else { return }
        // The phone has acknowledged its durable copy; only then allow deleting the Watch copy.
        try FileManager.default.removeItem(at: audioURL(id))
        items.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        try JSONEncoder().encode(items).write(to: index, options: .atomic)
    }

    enum LibraryError: LocalizedError {
        case unavailable
        var errorDescription: String? { "请先解决本地录音库存储错误。" }
    }
}
