import Foundation
import Combine
import AVFoundation

@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published var storageError: String?
    private let root: URL
    private let indexURL: URL
    private var deletedIDs: Set<UUID> = []

    private struct Index: Codable {
        var recordings: [Recording]
        var deletedIDs: Set<UUID>
    }

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                let saved = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
                recordings = saved.recordings
                deletedIDs = saved.deletedIDs
                for i in recordings.indices where recordings[i].state == .transcribing {
                    recordings[i].state = .failed
                    recordings[i].error = "上次转写被中断，可从已完成分段继续。"
                }
            }
        } catch { storageError = "读取录音索引失败：\(error.localizedDescription)；原文件未删除。" }
    }

    func audioURL(_ recording: Recording) -> URL { root.appendingPathComponent(recording.fileName) }
    func recording(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }

    // Copy must finish inside WCSession's file delegate callback, before its temporary URL expires.
    nonisolated static func stageIncomingFile(_ url: URL) throws -> URL {
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        try FileManager.default.copyItem(at: url, to: staged)
        return staged
    }

    @discardableResult
    func importAudio(_ staged: URL, metadata: RecordingMetadata) throws -> Bool {
        defer { try? FileManager.default.removeItem(at: staged) }
        // A delayed duplicate must not resurrect a user-deleted recording.
        if deletedIDs.contains(metadata.id) || recording(metadata.id) != nil { return false }
        guard storageError == nil else { throw StoreError.unavailable }
        let audio = try AVAudioFile(forReading: staged)
        guard audio.length > 0 else { throw SpeechFailure.emptyAudio }
        let value = Recording(metadata: metadata)
        let target = audioURL(value)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.copyItem(at: staged, to: target)
        }
        recordings.insert(value, at: 0)
        do { try persist() }
        catch { recordings.removeAll { $0.id == metadata.id }; throw error }
        return true
    }

    func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        do { try persist() } catch { storageError = error.localizedDescription }
    }

    func delete(_ id: UUID) throws {
        guard let value = recording(id) else { return }
        let old = recordings
        recordings.removeAll { $0.id == id }
        deletedIDs.insert(id)
        do { try persist() }
        catch { recordings = old; deletedIDs.remove(id); throw error }
        // Tombstone is durable before removing the audio.
        if FileManager.default.fileExists(atPath: audioURL(value).path) {
            try FileManager.default.removeItem(at: audioURL(value))
        }
    }

    private func persist() throws {
        let bytes = try JSONEncoder().encode(Index(recordings: recordings, deletedIDs: deletedIDs))
        try bytes.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    enum StoreError: LocalizedError {
        case unavailable
        var errorDescription: String? { "本地索引不可用，请先解决存储错误；不会覆盖现有索引。" }
    }
}
