import Foundation
import AVFoundation
import Speech

enum SpeechFailure: LocalizedError {
    case permission, unavailable, timeout, export, emptyAudio, noLocalModel
    var errorDescription: String? {
        switch self {
        case .permission: return "请在设置中允许语音识别，并在 App 内确认识别方式。"
        case .unavailable: return "中文识别器暂不可用，请稍后重试。"
        case .timeout: return "本段识别超时，已保留音频及之前的分段结果。"
        case .export: return "音频分段导出失败，原录音已保留。"
        case .emptyAudio: return "音频为空或时长无效。"
        case .noLocalModel: return "此设备没有可用的中文本地识别模型。可联网下载模型或明确允许 Apple 在线识别。"
        }
    }
}

// Own the continuation and task together; cancellation/timeout/result may race, but finish only once.
@MainActor
private final class RecognitionJob {
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var timer: Timer?
    private var finished = false

    func run(recognizer: SFSpeechRecognizer, request: SFSpeechRecognitionRequest) async throws -> String {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            guard !finished else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                guard !finished else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                self.recognizer = recognizer
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    Task { @MainActor in
                        if let text { self?.finish(.success(text)) }
                        else if let error { self?.finish(.failure(error)) }
                    }
                }
                timer = Timer.scheduledTimer(withTimeInterval: 65, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.finish(.failure(SpeechFailure.timeout)) }
                }
            }
        }, onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } })
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        timer = nil
        let pending = continuation
        self.continuation = nil
        task?.cancel()
        task = nil
        recognizer = nil
        pending?.resume(with: result)
    }

    func cancel() { finish(.failure(CancellationError())) }
}

@MainActor
final class SpeechTranscriptionService {
    var allowOnline = false
    private var activeJob: RecognitionJob?

    // Synchronous on MainActor: release the file recognition request before opening a live request.
    func cancelActiveRecognition() { activeJob?.cancel() }

    func recognizer() throws -> SFSpeechRecognizer {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw SpeechFailure.permission }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable
        else { throw SpeechFailure.unavailable }
        if !allowOnline && !recognizer.supportsOnDeviceRecognition { throw SpeechFailure.noLocalModel }
        return recognizer
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func transcribe(url: URL, completed: [String], checkpoint: @escaping ([String]) throws -> Void) async throws -> String {
        let recognizer = try recognizer()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw SpeechFailure.emptyAudio }
        let ranges = SegmentPlan.ranges(duration: duration)
        var segments = Array(completed.prefix(ranges.count))
        for range in ranges.dropFirst(segments.count) {
            try Task.checkCancellation()
            let segment = try await export(asset: asset, range: range)
            do {
                defer { try? FileManager.default.removeItem(at: segment) }
                let request = SFSpeechURLRecognitionRequest(url: segment)
                request.requiresOnDeviceRecognition = !allowOnline
                request.shouldReportPartialResults = false
                request.taskHint = .dictation
                let job = RecognitionJob()
                activeJob = job
                defer { activeJob = nil }
                let text = try await job.run(recognizer: recognizer, request: request)
                try Task.checkCancellation()
                segments.append(text)
                try checkpoint(segments)
            }
        }
        return segments.joined(separator: "\n")
    }

    private func export(asset: AVAsset, range: Range<Double>) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("segment-\(UUID()).m4a")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw SpeechFailure.export }
        session.outputURL = url
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                       duration: CMTime(seconds: range.countSeconds, preferredTimescale: 600))
        do {
            try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    session.exportAsynchronously { continuation.resume() }
                }
                try Task.checkCancellation()
                guard session.status == .completed else { throw session.error ?? SpeechFailure.export }
            }, onCancel: { session.cancelExport() })
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

private extension Range where Bound == Double {
    var countSeconds: Double { upperBound - lowerBound }
}
