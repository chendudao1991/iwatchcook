import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct TranscriptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@MainActor
struct RecordingDetailView: View {
    let id: UUID
    @ObservedObject var model: PhoneModel
    @ObservedObject var store: RecordingStore
    @State private var draft = ""
    @State private var title = ""
    @State private var dirty = false
    @State private var loaded = false
    @State private var player: AVAudioPlayer?
    @State private var showExport = false
    @State private var showDelete = false
    @State private var showRestart = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var record: Recording? { store.recording(id) }

    var body: some View {
        Group {
            if let record {
                Form {
                    Section("原音频") {
                        TextField("录音标题", text: $title)
                        Text("\(Int(record.metadata.duration)) 秒 · \(record.state.label)")
                        HStack {
                            Button("播放") { play(record) }
                            Button("停止") { player?.stop() }
                            ShareLink("导出音频", item: store.audioURL(record))
                        }
                        if let failure = record.error { Text(failure).foregroundStyle(.orange) }
                        if record.state != .transcribing {
                            Button("继续／重试转写") { model.enqueue(id) }.disabled(!model.consent)
                            Button("从头重新转写") { showRestart = true }.disabled(!model.consent)
                        } else {
                            ProgressView("已完成 \(record.segments.count) 段，每段最多 40 秒")
                        }
                    }
                    Section("转写文字") {
                        TextEditor(text: Binding(get: { draft }, set: { draft = $0; dirty = true }))
                            .frame(minHeight: 240)
                            .disabled(record.state == .transcribing)
                        Button("保存标题与文字") {
                            store.update(id) { $0.title = title; $0.transcript = draft }
                            dirty = false
                        }.disabled(record.state == .transcribing)
                        Button("导出 TXT") { showExport = true }
                        ShareLink("分享文字", item: draft)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("删除录音与文字", role: .destructive) { showDelete = true }
                }
                .onAppear {
                    if !loaded { draft = record.transcript; title = record.title; loaded = true; dirty = false }
                }
                .onChange(of: record.transcript) { _, text in if !dirty { draft = text } }
            } else { ContentUnavailableView("录音已删除", systemImage: "waveform") }
        }
        .navigationTitle("录音详情")
        .onDisappear { player?.stop() }
        .fileExporter(isPresented: $showExport, document: TranscriptDocument(text: draft),
                      contentType: .plainText, defaultFilename: "WristNote-\(id.uuidString)") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .confirmationDialog("删除 iPhone 上的音频与文字？手表副本需单独删除。", isPresented: $showDelete) {
            Button("删除", role: .destructive) { player?.stop(); model.delete(id); if record == nil { dismiss() } }
        }
        .confirmationDialog("重新转写将覆盖已保存文字，是否继续？", isPresented: $showRestart) {
            Button("从头转写", role: .destructive) { dirty = false; model.enqueue(id, restart: true) }
        }
    }

    private func play(_ record: Recording) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: store.audioURL(record))
            guard player?.play() == true else { throw SpeechFailure.emptyAudio }
        } catch { self.error = error.localizedDescription }
    }
}
