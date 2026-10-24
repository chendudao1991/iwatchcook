import XCTest
#if SWIFT_PACKAGE
@testable import WristNoteCore
#endif

final class RecordingModelsTests: XCTestCase {
    func testMetadataRoundTripAndRejectInvalidDuration() {
        let metadata = RecordingMetadata(createdAt: Date(timeIntervalSince1970: 1_700_000_000), duration: 60, mode: .live)
        XCTAssertEqual(RecordingMetadata(transferInfo: metadata.transferInfo), metadata)
        var invalid = metadata.transferInfo
        invalid["duration"] = Double.nan
        XCTAssertNil(RecordingMetadata(transferInfo: invalid))
        invalid["duration"] = -1.0
        XCTAssertNil(RecordingMetadata(transferInfo: invalid))
        invalid = metadata.transferInfo
        invalid["version"] = 999
        XCTAssertNil(RecordingMetadata(transferInfo: invalid))
    }

    func testLongAudioSegmentsAreContiguousAndBounded() {
        for duration in [1.0, 40.0, 40.01, 300, 1800, 3600] {
            let ranges = SegmentPlan.ranges(duration: duration)
            XCTAssertEqual(ranges.first?.lowerBound, 0)
            XCTAssertEqual(ranges.last?.upperBound, duration)
            for (index, range) in ranges.enumerated() {
                XCTAssertLessThanOrEqual(range.upperBound - range.lowerBound, 40)
                if index > 0 { XCTAssertEqual(ranges[index - 1].upperBound, range.lowerBound) }
            }
        }
        XCTAssertTrue(SegmentPlan.ranges(duration: .infinity).isEmpty)
        XCTAssertTrue(SegmentPlan.ranges(duration: 0).isEmpty)
    }

    func testLiveProtocolRejectsOversizedAndOddPCM() throws {
        let id = UUID()
        let valid = LivePacket(kind: .audio, recordingID: id, sequence: 0, pcm: Data(count: 32_000))
        XCTAssertEqual(LivePacket.decode(try valid.encoded())?.recordingID, id)
        let odd = LivePacket(kind: .audio, recordingID: id, sequence: 1, pcm: Data(count: 3))
        XCTAssertNil(LivePacket.decode(try odd.encoded()))
        let huge = LivePacket(kind: .audio, recordingID: id, sequence: 2, pcm: Data(count: 64_000))
        XCTAssertNil(LivePacket.decode(try huge.encoded()))
    }

    func testSequenceGateRejectsStaleSessionsDuplicatesAndGaps() {
        let id = UUID()
        var gate = LiveSequenceGate()
        gate.begin(id, sequence: 0)
        XCTAssertTrue(gate.accept(id, sequence: 1))
        XCTAssertFalse(gate.accept(id, sequence: 1))
        XCTAssertFalse(gate.accept(UUID(), sequence: 2))
        XCTAssertFalse(gate.accept(id, sequence: 3))
        XCTAssertTrue(gate.accept(id, sequence: 2))
        gate.begin(id, sequence: 90) // Reconnect with the sender's current sequence.
        XCTAssertTrue(gate.accept(id, sequence: 91))
        gate.end()
        XCTAssertFalse(gate.accept(id, sequence: 92))
        gate.begin(id, sequence: Int.max)
        XCTAssertFalse(gate.accept(id, sequence: 0))
    }

    func testCheckpointAndEditedChineseTextSurviveDiskRoundTrip() throws {
        var record = Recording(metadata: RecordingMetadata(duration: 300, mode: .afterRecording))
        record.segments = ["第一段中文。", "第二段保留标点。"]
        record.transcript = "用户编辑后的文字\n第二行"
        record.state = .failed
        record.error = "网络中断"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        let restored = try JSONDecoder().decode(Recording.self, from: Data(contentsOf: url))
        XCTAssertEqual(restored.id, record.id)
        XCTAssertEqual(restored.segments, record.segments)
        XCTAssertEqual(restored.transcript, record.transcript)
        XCTAssertEqual(restored.state, .failed)
        XCTAssertEqual(restored.error, record.error)
    }

    func testReconnectRejectsPacketsFromPreviousStreamOfSameRecording() throws {
        let id = UUID()
        let oldStream = UUID()
        let newStream = UUID()
        var gate = LiveSequenceGate()
        gate.begin(id, sequence: 10, streamID: newStream)
        XCTAssertFalse(gate.accept(id, sequence: 11, streamID: oldStream))
        XCTAssertFalse(gate.accept(id, sequence: 11))
        XCTAssertTrue(gate.accept(id, sequence: 11, streamID: newStream))
        let packet = LivePacket(kind: .subtitle, recordingID: id, sequence: 11, text: "新字幕", streamID: newStream)
        XCTAssertEqual(LivePacket.decode(try packet.encoded())?.streamID, newStream)
    }
}
