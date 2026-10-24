import Foundation
import Combine

@MainActor
final class PhoneModel: ObservableObject {
    let store: RecordingStore
    let connectivity: PhoneConnectivityManager
    let speech: SpeechTranscriptionService
    private let live: LiveTranscriptionService
    @Published var consent: Bool
    @Published var allowOnline: Bool {
        didSet {
            UserDefaults.standard.set(allowOnline, forKey: "allowOnlineSpeech")
            speech.allowOnline = allowOnline
            if let currentID, !queue.contains(currentID) { queue.insert(currentID, at: 0) }
            worker?.cancel()
            live.stop()
        }
    }
    @Published var notice: String?
    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var currentID: UUID?

    init() {
        let store = RecordingStore()
        self.store = store
        connectivity = PhoneConnectivityManager(store: store)
        let speech = SpeechTranscriptionService()
        self.speech = speech
        live = LiveTranscriptionService(speech: speech)
        consent = UserDefaults.standard.bool(forKey: "speechConsent")
        allowOnline = UserDefaults.standard.bool(forKey: "allowOnlineSpeech")
        speech.allowOnline = allowOnline
        connectivity.onImport = { [weak self] id in self?.enqueue(id) }
        live.onSubtitle = { [weak self] packet in self?.connectivity.send(packet) }
        live.onEnd = { [weak self] in self?.drain() }
        connectivity.onLivePacket = { [weak self] packet in
            guard let self, self.consent else { throw SpeechFailure.permission }
            switch packet.kind {
            case .start:
                if let currentID = self.currentID, !self.queue.contains(currentID) { self.queue.insert(currentID, at: 0) }
                self.worker?.cancel()
                try self.live.start(packet)
            case .audio: try self.live.append(packet)
            case .stop:
                if self.live.recordingID == packet.recordingID { self.live.stop() }
            default: throw SpeechFailure.unavailable
            }
        }
        // Only unfinished imports are automatically resumed. Explicitly failed jobs remain visible for retry.
        queue = store.recordings.filter { $0.state == .waiting }.map(\.id)
        drain()
    }

    func authorize() async {
        if await SpeechTranscriptionService.requestPermission() {
            consent = true
            UserDefaults.standard.set(true, forKey: "speechConsent")
            for record in store.recordings where record.state != .completed { enqueue(record.id) }
        } else { notice = "语音识别权限被拒绝。原音频仍可播放和导出。" }
    }

    func enqueue(_ id: UUID, restart: Bool = false) {
        guard store.recording(id) != nil else { return }
        if restart {
            guard currentID != id else { return }
            store.update(id) { $0.segments = []; $0.state = .waiting; $0.error = nil }
        }
        if currentID != id && !queue.contains(id) { queue.append(id) }
        drain()
    }

    private func drain() {
        guard consent, worker == nil, live.recordingID == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let recording = store.recording(id) else { drain(); return }
        currentID = id
        worker = Task { [weak self] in
            guard let self else { return }
            self.store.update(id) { $0.state = .transcribing; $0.error = nil }
            do {
                let text = try await self.speech.transcribe(url: self.store.audioURL(recording),
                                                          completed: recording.segments) { [weak self] segments in
                    self?.store.update(id) { $0.segments = segments }
                }
                try Task.checkCancellation()
                self.store.update(id) { $0.transcript = text; $0.state = .completed; $0.error = nil }
            } catch is CancellationError {
                self.store.update(id) { $0.state = .waiting }
            } catch {
                self.store.update(id) { $0.state = .failed; $0.error = error.localizedDescription }
            }
            self.worker = nil
            self.currentID = nil
            self.drain()
        }
    }

    func delete(_ id: UUID) {
        queue.removeAll { $0 == id }
        if currentID == id { worker?.cancel() }
        do { try store.delete(id) } catch { notice = error.localizedDescription }
    }
}
