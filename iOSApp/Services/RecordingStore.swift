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
    private var snapshot: DurableJSON<Index>?

    private struct Index: Codable {
        var recordings: [Recording]
        var deletedIDs: Set<UUID>
    }

    init(directory: URL? = nil) {
        root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let snapshot = try DurableJSON(url: indexURL, defaultValue: Index(recordings: [], deletedIDs: []))
            self.snapshot = snapshot
            let saved = snapshot.value
            recordings = saved.recordings
            deletedIDs = saved.deletedIDs
            for i in recordings.indices where recordings[i].state == .transcribing {
                recordings[i].state = .failed
                recordings[i].error = "上次转写被中断，可从已完成分段继续。"
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
        guard snapshot != nil else { throw StoreError.unavailable }
        let audio = try AVAudioFile(forReading: staged)
        guard audio.length > 0 else { throw SpeechFailure.emptyAudio }
        let value = Recording(metadata: metadata)
        let target = audioURL(value)
        // A target without an index entry may be an orphan from an interrupted import.
        // Never reuse it merely because it exists. Both URLs are in this app's data volume.
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: staged.path)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
        } else {
            try FileManager.default.moveItem(at: staged, to: target)
        }
        var candidate = recordings
        candidate.insert(value, at: 0)
        try persist(candidate, deletedIDs: deletedIDs)
        return true
    }

    func update(_ id: UUID, _ change: (inout Recording) -> Void) throws {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        var candidate = recordings
        change(&candidate[i])
        try persist(candidate, deletedIDs: deletedIDs)
    }

    func delete(_ id: UUID) throws {
        guard let value = recording(id) else { return }
        let candidate = recordings.filter { $0.id != id }
        var tombstones = deletedIDs
        tombstones.insert(id)
        try persist(candidate, deletedIDs: tombstones)
        // Tombstone is durable before removing the audio.
        if FileManager.default.fileExists(atPath: audioURL(value).path) {
            try FileManager.default.removeItem(at: audioURL(value))
        }
    }

    private func persist(_ candidate: [Recording], deletedIDs tombstones: Set<UUID>) throws {
        guard let snapshot else { throw StoreError.unavailable }
        do {
            try snapshot.commit(Index(recordings: candidate, deletedIDs: tombstones))
            recordings = candidate
            deletedIDs = tombstones
            storageError = nil
        } catch {
            storageError = "保存失败，尚未确认本次更改：\(error.localizedDescription)"
            throw error
        }
    }

    enum StoreError: LocalizedError {
        case unavailable
        var errorDescription: String? { "本地索引不可用，请先解决存储错误；不会覆盖现有索引。" }
    }
}
