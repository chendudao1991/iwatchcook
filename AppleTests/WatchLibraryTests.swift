import XCTest
import AVFoundation

// Exercises the actual Watch library using iOS AVFoundation. This is not a Watch hardware test.
@MainActor
final class WatchLibraryTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeAudio(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                                channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        let pointer = try XCTUnwrap(buffer.int16ChannelData?[0])
        for index in 0..<1_600 { pointer[index] = 0 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: false)
        try file.write(from: buffer)
    }

    func testUnfinishedRecordingRecoversReadableFramesAfterRelaunch() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WatchLibrary(directory: root)
        let metadata = RecordingMetadata(mode: .afterRecording)
        try library.register(metadata)
        try writeAudio(to: library.audioURL(metadata.id))
        let restarted = WatchLibrary(directory: root)
        let item = try XCTUnwrap(restarted.items.first)
        XCTAssertEqual(item.id, metadata.id)
        XCTAssertTrue(item.finalized)
        XCTAssertEqual(item.metadata.duration, 0.1, accuracy: 0.0001)
        XCTAssertFalse(item.acknowledged)
    }

    func testManualRetryPreservesUnreadableFileAndCanRecoverWhenReadable() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WatchLibrary(directory: root)
        let metadata = RecordingMetadata(mode: .live)
        try library.register(metadata)
        let url = library.audioURL(metadata.id)
        let original = Data("unreadable".utf8)
        try original.write(to: url)
        try library.retrySaving()
        XCTAssertFalse(try XCTUnwrap(library.items.first).finalized)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(library.items.first?.syncError)
        // Simulates a now-readable, closed CAF after a recoverable saving interruption.
        try FileManager.default.removeItem(at: url)
        try writeAudio(to: url)
        try library.retrySaving()
        XCTAssertTrue(try XCTUnwrap(library.items.first).finalized)
        XCTAssertNil(library.error)
    }

    func testCorruptManifestCannotBeOverwrittenByManualRetry() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.json")
        let bytes = Data("{broken-manifest".utf8)
        try bytes.write(to: index)
        let library = WatchLibrary(directory: root)
        XCTAssertNotNil(library.error)
        XCTAssertThrowsError(try library.retrySaving())
        XCTAssertEqual(try Data(contentsOf: index), bytes)
    }

    func testLocalAudioCannotBeRemovedBeforeDurablePhoneAcknowledgement() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = WatchLibrary(directory: root)
        let metadata = RecordingMetadata(mode: .afterRecording)
        try library.register(metadata)
        let url = library.audioURL(metadata.id)
        try writeAudio(to: url)
        try library.finish(metadata.id, duration: 0.1)
        try library.removeAcknowledged(metadata.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        library.acknowledge(metadata.id)
        XCTAssertTrue(try XCTUnwrap(WatchLibrary(directory: root).items.first).acknowledged)
        try library.removeAcknowledged(metadata.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(WatchLibrary(directory: root).items.isEmpty)
    }
}
