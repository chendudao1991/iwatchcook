import Foundation
import AVFoundation
import Speech

@MainActor
final class LiveTranscriptionService {
    private let speech: SpeechTranscriptionService
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var generation = UUID()
    private var prefix = ""
    private var partial = ""
    private var windowStarted = Date()
    private var watchdog: Timer?
    private var gate = LiveSequenceGate()
    var recordingID: UUID? { gate.recordingID }
    private var lastSequence: Int { gate.lastSequence }
    var onSubtitle: ((LivePacket) -> Void)?
    var onEnd: (() -> Void)?

    init(speech: SpeechTranscriptionService) { self.speech = speech }

    func start(_ packet: LivePacket) throws {
        stop(notify: false)
        _ = try speech.recognizer()
        gate.begin(packet.recordingID, sequence: packet.sequence)
        prefix = ""
        partial = ""
        try openWindow()
        touchWatchdog()
    }

    func append(_ packet: LivePacket) throws {
        guard let bytes = packet.pcm, !bytes.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: LivePacket.sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bytes.count / 2)),
              let pointer = buffer.int16ChannelData?[0],
              gate.accept(packet.recordingID, sequence: packet.sequence) else {
            throw SpeechFailure.unavailable
        }
        if Date().timeIntervalSince(windowStarted) > 45 {
            prefix += partial.isEmpty ? "" : partial + "\n"
            prefix = String(prefix.suffix(2_000))
            partial = ""
            try openWindow()
        }
        buffer.frameLength = buffer.frameCapacity
        bytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress { memcpy(pointer, base, bytes.count) }
        }
        request?.append(buffer)
        touchWatchdog()
    }

    private func openWindow() throws {
        generation = UUID()
        let token = generation
        task?.cancel()
        request?.endAudio()
        let recognizer = try speech.recognizer()
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = !speech.allowOnline
        self.request = request
        windowStarted = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            Task { @MainActor in
                guard let self, self.generation == token, let id = self.recordingID else { return }
                if let text {
                    self.partial = text
                    self.onSubtitle?(LivePacket(kind: .subtitle, recordingID: id, sequence: self.lastSequence,
                                               text: String((self.prefix + text).suffix(2_000))))
                }
                if error != nil {
                    self.onSubtitle?(LivePacket(kind: .unavailable, recordingID: id, sequence: self.lastSequence,
                                               text: "实时识别中断，完整录音将在同步后转写。"))
                    self.stop()
                } else if final {
                    self.prefix += self.partial.isEmpty ? "" : self.partial + "\n"
                    self.prefix = String(self.prefix.suffix(2_000))
                    self.partial = ""
                    do { try self.openWindow() } catch { self.stop() }
                }
            }
        }
    }

    private func touchWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop(notify: Bool = true) {
        let wasActive = recordingID != nil
        generation = UUID()
        gate.end()
        watchdog?.invalidate()
        watchdog = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recognizer = nil
        if wasActive && notify { onEnd?() }
    }
}
