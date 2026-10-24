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
    private var snapshot: DurableJSON<[WatchRecording]>?

    init(directory: URL? = nil) {
        root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchRecordings", isDirectory: true)
        index = root.appendingPathComponent("index.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let snapshot = try DurableJSON(url: index, defaultValue: [WatchRecording]())
            self.snapshot = snapshot
            items = snapshot.value
            if !items.isEmpty {
                try retrySaving()
            }
        } catch { self.error = "录音库恢复失败：\(error.localizedDescription)。已有文件不会被覆盖。" }
    }

    func audioURL(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).caf") }

    // Only call when capture has stopped. Also recovers a finalized audio file whose last
    // manifest write failed; users need not restart the app after freeing disk space.
    func retrySaving() throws {
        guard snapshot != nil else { throw LibraryError.unavailable }
        var candidate = items
        for i in candidate.indices where !candidate[i].finalized {
            do {
                let file = try AVAudioFile(forReading: audioURL(candidate[i].id))
                guard file.length > 0 else {
                    candidate[i].syncError = "文件中没有可读音频，已保留，未加入同步队列。"
                    continue
                }
                candidate[i].metadata.duration = Double(file.length) / file.processingFormat.sampleRate
                candidate[i].finalized = true
                candidate[i].syncError = "录音被中断，已恢复可读取部分。"
            } catch {
                candidate[i].syncError = "中断文件无法自动恢复，保留原文件：\(error.localizedDescription)"
            }
        }
        try persist(candidate)
    }

    func register(_ metadata: RecordingMetadata) throws {
        guard snapshot != nil else { throw LibraryError.unavailable }
        var candidate = items
        candidate.insert(WatchRecording(metadata: metadata), at: 0)
        try persist(candidate)
    }

    func finish(_ id: UUID, duration: Double) throws {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var candidate = items
        candidate[i].metadata.duration = duration
        candidate[i].finalized = duration > 0
        if duration == 0 { candidate[i].syncError = "没有可用音频，未加入同步队列。" }
        try persist(candidate)
    }

    func acknowledge(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var candidate = items
        candidate[i].acknowledged = true
        candidate[i].syncError = nil
        do { try persist(candidate) } catch { self.error = error.localizedDescription }
    }

    func transferFailed(_ id: UUID, message: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var candidate = items
        candidate[i].syncError = message
        do { try persist(candidate) } catch { self.error = error.localizedDescription }
    }

    func removeAcknowledged(_ id: UUID) throws {
        guard let item = items.first(where: { $0.id == id }), item.acknowledged else { return }
        // The phone has acknowledged its durable copy; only then allow deleting the Watch copy.
        // Keep the manifest entry if removing the file fails; tolerate an earlier successful removal.
        if FileManager.default.fileExists(atPath: audioURL(id).path) {
            try FileManager.default.removeItem(at: audioURL(id))
        }
        try persist(items.filter { $0.id != id })
    }

    private func persist(_ candidate: [WatchRecording]) throws {
        guard let snapshot else { throw LibraryError.unavailable }
        try snapshot.commit(candidate)
        items = candidate
        error = nil
    }

    enum LibraryError: LocalizedError {
        case unavailable
        var errorDescription: String? { "请先解决本地录音库存储错误。" }
    }
}
