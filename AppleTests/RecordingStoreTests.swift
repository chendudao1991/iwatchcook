import XCTest
import AVFoundation

@MainActor
final class RecordingStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func audio(in directory: URL, frames: AVAudioFrameCount = 1_600) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let pointer = try XCTUnwrap(buffer.int16ChannelData?[0])
        for index in 0..<Int(frames) { pointer[index] = Int16(index % 100) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: false)
        try file.write(from: buffer)
        return url
    }

    func testImportedAudioIsDurableAndDuplicateDoesNotReplaceEditedText() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(directory: root.appendingPathComponent("catalog"))
        let metadata = RecordingMetadata(duration: 0.1, mode: .afterRecording)
        let staged = try audio(in: root)
        XCTAssertTrue(try store.importAudio(staged, metadata: metadata))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        try store.update(metadata.id) { $0.transcript = "编辑后的中文" }
        XCTAssertFalse(try store.importAudio(audio(in: root), metadata: metadata))
        XCTAssertEqual(store.recordings.count, 1)
        let restarted = RecordingStore(directory: root.appendingPathComponent("catalog"))
        XCTAssertEqual(restarted.recording(metadata.id)?.transcript, "编辑后的中文")
        let record = try XCTUnwrap(restarted.recording(metadata.id))
        XCTAssertEqual(try AVAudioFile(forReading: restarted.audioURL(record)).length, 1_600)
    }

    func testDeletedIDIsNotResurrectedByDelayedTransferAfterRelaunch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("catalog")
        let store = RecordingStore(directory: catalog)
        let metadata = RecordingMetadata(duration: 0.1, mode: .live)
        try store.importAudio(audio(in: root), metadata: metadata)
        let url = store.audioURL(try XCTUnwrap(store.recording(metadata.id)))
        try store.delete(metadata.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let restarted = RecordingStore(directory: catalog)
        XCTAssertFalse(try restarted.importAudio(audio(in: root), metadata: metadata))
        XCTAssertTrue(restarted.recordings.isEmpty)
    }

    func testOrphanAudioIsReplacedByCompleteRetransmission() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(directory: root.appendingPathComponent("catalog"))
        let metadata = RecordingMetadata(duration: 0.1, mode: .afterRecording)
        let target = store.audioURL(Recording(metadata: metadata))
        try FileManager.default.moveItem(at: audio(in: root, frames: 16), to: target)
        try store.importAudio(audio(in: root, frames: 1_600), metadata: metadata)
        XCTAssertEqual(try AVAudioFile(forReading: target).length, 1_600)
        XCTAssertEqual(store.recordings.count, 1)
    }

    func testInvalidAudioIsNotAcknowledgedOrCatalogued() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordingStore(directory: root.appendingPathComponent("catalog"))
        let staged = root.appendingPathComponent("invalid.caf")
        try Data("not audio".utf8).write(to: staged)
        XCTAssertThrowsError(try store.importAudio(staged, metadata: RecordingMetadata(mode: .live)))
        XCTAssertTrue(store.recordings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testCorruptIndexRemainsUntouchedWhenImportIsAttempted() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.json")
        let corrupt = Data("{broken-index".utf8)
        try corrupt.write(to: index)
        let store = RecordingStore(directory: root)
        XCTAssertNotNil(store.storageError)
        XCTAssertThrowsError(try store.importAudio(audio(in: root), metadata: RecordingMetadata(mode: .live)))
        XCTAssertEqual(try Data(contentsOf: index), corrupt)
    }

    func testInterruptedTranscriptionRestoresSavedSegmentsForRetry() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("catalog")
        let store = RecordingStore(directory: catalog)
        let metadata = RecordingMetadata(duration: 0.1, mode: .afterRecording)
        try store.importAudio(audio(in: root), metadata: metadata)
        try store.update(metadata.id) { $0.state = .transcribing; $0.segments = ["已保存第一段"] }
        let restarted = RecordingStore(directory: catalog)
        let record = try XCTUnwrap(restarted.recording(metadata.id))
        XCTAssertEqual(record.state, .failed)
        XCTAssertEqual(record.segments, ["已保存第一段"])
        XCTAssertNotNil(record.error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restarted.audioURL(record).path))
    }
}
