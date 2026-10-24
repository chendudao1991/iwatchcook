import Foundation
import AVFoundation
import Combine

// The tap writes the original PCM first. Conversion/transport failure never discards that file.
private final class AudioSink {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat?
    private(set) var frames: AVAudioFramePosition = 0
    private let sourceRate: Double

    init(url: URL, format: AVAudioFormat, live: Bool) throws {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        file = try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        sourceRate = format.sampleRate
        outputFormat = live ? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                            channels: 1, interleaved: false) : nil
        converter = outputFormat.flatMap { AVAudioConverter(from: format, to: $0) }
    }

    func consume(_ buffer: AVAudioPCMBuffer) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let file else { return nil }
        try file.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
        guard let converter, let outputFormat,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / sourceRate)) + 32)
        else { return nil }
        var provided = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true
            status.pointee = .haveData
            return buffer
        }
        // A resampling failure affects live captions only.
        guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return nil }
        return Data(bytes: samples, count: Int(output.frameLength) * 2)
    }

    func close() -> Double {
        lock.lock()
        defer { lock.unlock() }
        file = nil
        return Double(frames) / sourceRate
    }
}

@MainActor
final class WatchRecordingService: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var status = "录音将先保存在手表上"
    private let library: WatchLibrary
    private let connectivity: WatchConnectivityManager
    private var engine: AVAudioEngine?
    private var sink: AudioSink?
    private var metadata: RecordingMetadata?
    private var timer: Timer?
    private var pcm = Data()
    private var interruption: NSObjectProtocol?

    init(library: WatchLibrary, connectivity: WatchConnectivityManager) {
        self.library = library
        self.connectivity = connectivity
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                               object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.stop(reason: "录音被系统中断，已保存可用音频。") }
            }
        }
    }

    func start(mode: RecordingMode) async {
        guard !recording, !starting else { return }
        starting = true
        defer { starting = false }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { status = "麦克风权限被拒绝，请在系统设置中允许。"; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
            let metadata = RecordingMetadata(mode: mode)
            try library.register(metadata)
            self.metadata = metadata
            let sink = try AudioSink(url: library.audioURL(metadata.id), format: format, live: mode == .live)
            self.sink = sink
            self.engine = engine
            pcm.removeAll(keepingCapacity: true)
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                do {
                    let bytes = try sink.consume(buffer)
                    if let bytes {
                        Task { @MainActor in self?.receivePCM(bytes, id: metadata.id) }
                    }
                } catch {
                    Task { @MainActor in self?.stop(reason: "录音写入失败：\(error.localizedDescription)") }
                }
            }
            engine.prepare()
            try engine.start()
            recording = true
            elapsed = 0
            status = "正在本地录音"
            let started = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed = Date().timeIntervalSince(started) }
            }
            if mode == .live { connectivity.beginLive(metadata.id) }
        } catch {
            stop(reason: "无法开始录音：\(error.localizedDescription)")
            status = "无法开始录音：\(error.localizedDescription)"
        }
    }

    private func receivePCM(_ bytes: Data, id: UUID) {
        guard recording, metadata?.id == id else { return }
        pcm.append(bytes)
        while pcm.count >= LivePacket.maxAudioBytes {
            connectivity.sendPCM(Data(pcm.prefix(LivePacket.maxAudioBytes)))
            pcm.removeFirst(LivePacket.maxAudioBytes)
        }
    }

    func stop(reason: String? = nil) {
        timer?.invalidate()
        timer = nil
        engine?.stop()
        if engine != nil { engine?.inputNode.removeTap(onBus: 0) }
        engine = nil
        let duration = sink?.close() ?? 0
        sink = nil
        recording = false
        connectivity.endLive()
        pcm.removeAll()
        if let metadata {
            do {
                try library.finish(metadata.id, duration: duration)
                status = reason ?? "已保存到手表，等待 iPhone 确认接收"
            } catch { status = "音频已保留，保存索引失败：\(error.localizedDescription)" }
        }
        self.metadata = nil
        elapsed = duration
        try? AVAudioSession.sharedInstance().setActive(false)
        connectivity.retryTransfers()
    }

    enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? { "没有可用的麦克风输入。" }
    }
}
