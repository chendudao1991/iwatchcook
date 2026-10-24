import SwiftUI

@MainActor
struct WatchHomeView: View {
    @ObservedObject var recorder: WatchRecordingService
    @ObservedObject var library: WatchLibrary
    @ObservedObject var connectivity: WatchConnectivityManager
    @State private var mode: RecordingMode = .afterRecording
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text(connectivity.connection).font(.caption2)
                    if !recorder.recording {
                        Picker("模式", selection: $mode) {
                            ForEach(RecordingMode.allCases) { Text($0.label).tag($0) }
                        }
                        Button(recorder.starting ? "正在准备…" : "开始录音", systemImage: "mic.fill") {
                            Task { await recorder.start(mode: mode) }
                        }.disabled(recorder.starting || library.error != nil)
                    } else {
                        Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                            .font(.title2).monospacedDigit()
                        Button("结束并保存", systemImage: "stop.fill", role: .destructive) { recorder.stop() }
                        if mode == .live {
                            Text(connectivity.liveStatus).font(.caption2)
                            Text(connectivity.subtitle.isEmpty ? "等待字幕…" : connectivity.subtitle).font(.caption)
                            Button("重连实时字幕") { connectivity.resumeLive() }
                        }
                    }
                    Text(recorder.status).font(.caption2)
                    if let error = library.error { Text(error).foregroundStyle(.red).font(.caption2) }
                    if !recorder.recording {
                        Button("重试同步") { connectivity.retryTransfers() }
                        NavigationLink("本地录音（\(library.items.count)）") {
                            List {
                                ForEach(library.items) { item in
                                    VStack(alignment: .leading) {
                                        Text(item.metadata.createdAt, style: .date)
                                        Text("\(Int(item.metadata.duration)) 秒").font(.caption2)
                                        Text(item.acknowledged ? "iPhone 已确认接收" : "等待同步确认").font(.caption2)
                                        if let error = item.syncError { Text(error).font(.caption2).foregroundStyle(.orange) }
                                        if item.acknowledged {
                                            Button("删除手表副本", role: .destructive) {
                                                do { try library.removeAcknowledged(item.id) }
                                                catch { library.error = error.localizedDescription }
                                            }
                                        }
                                    }
                                }
                            }.navigationTitle("本地录音")
                        }
                    }
                }
            }.navigationTitle("腕录 AI")
        }
        .onChange(of: phase) { _, phase in if phase == .active { connectivity.retryTransfers() } }
    }
}
