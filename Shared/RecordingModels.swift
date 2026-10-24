import Foundation

enum RecordingMode: String, Codable, CaseIterable, Identifiable {
    case live, afterRecording
    var id: String { rawValue }
    var label: String { self == .live ? "实时字幕" : "录后转写" }
}

enum TranscriptionState: String, Codable {
    case waiting, transcribing, completed, failed
    var label: String {
        switch self {
        case .waiting: return "等待转写"
        case .transcribing: return "转写中"
        case .completed: return "已完成"
        case .failed: return "需重试"
        }
    }
}

struct RecordingMetadata: Codable, Equatable {
    static let version = 1
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let mode: RecordingMode

    var transferInfo: [String: Any] {
        ["version": Self.version, "id": id.uuidString,
         "createdAt": createdAt.timeIntervalSince1970, "duration": duration, "mode": mode.rawValue]
    }

    init(id: UUID = UUID(), createdAt: Date = Date(), duration: TimeInterval = 0, mode: RecordingMode) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.mode = mode
    }

    init?(transferInfo: [String: Any]) {
        guard (transferInfo["version"] as? Int) == Self.version,
              let rawID = transferInfo["id"] as? String, let id = UUID(uuidString: rawID),
              let time = transferInfo["createdAt"] as? Double, time.isFinite,
              let duration = transferInfo["duration"] as? Double, duration.isFinite, duration >= 0,
              let rawMode = transferInfo["mode"] as? String, let mode = RecordingMode(rawValue: rawMode)
        else { return nil }
        self.init(id: id, createdAt: Date(timeIntervalSince1970: time), duration: duration, mode: mode)
    }
}

struct Recording: Codable, Identifiable {
    let metadata: RecordingMetadata
    var id: UUID { metadata.id }
    var title: String = "录音"
    var transcript = ""
    var segments: [String] = []
    var state: TranscriptionState = .waiting
    var error: String?
    var fileName: String { "\(id.uuidString).caf" }
}

// Each live session is explicitly identified. Old packets/subtitles cannot contaminate a new recording.
struct LivePacket: Codable {
    enum Kind: String, Codable { case start, audio, stop, subtitle, unavailable }
    let kind: Kind
    let recordingID: UUID
    let sequence: Int
    var pcm: Data?
    var text: String?

    static let sampleRate: Double = 16_000
    static let maxAudioBytes = 32_000  // One second, mono signed Int16 PCM.
    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> LivePacket? {
        guard data.count <= 50_000, let packet = try? JSONDecoder().decode(Self.self, from: data),
              packet.sequence >= 0, (packet.pcm?.count ?? 0) <= maxAudioBytes,
              (packet.pcm?.count ?? 0) % 2 == 0 else { return nil }
        return packet
    }
}

enum SegmentPlan {
    static let seconds: Double = 40
    static func ranges(duration: Double) -> [Range<Double>] {
        guard duration.isFinite, duration > 0 else { return [] }
        return stride(from: 0.0, to: duration, by: seconds).map { $0..<min($0 + seconds, duration) }
    }
}

struct LiveSequenceGate {
    private(set) var recordingID: UUID?
    private(set) var lastSequence = 0
    mutating func begin(_ id: UUID, sequence: Int) {
        recordingID = id
        lastSequence = sequence
    }
    mutating func accept(_ id: UUID, sequence: Int) -> Bool {
        guard recordingID == id, sequence == lastSequence + 1 else { return false }
        lastSequence = sequence
        return true
    }
    mutating func end() { recordingID = nil }
}
