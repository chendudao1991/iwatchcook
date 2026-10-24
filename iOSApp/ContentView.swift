import SwiftUI

@MainActor
struct ContentView: View {
    @ObservedObject var model: PhoneModel
    @ObservedObject var store: RecordingStore
    @ObservedObject var connectivity: PhoneConnectivityManager
    @State private var search = ""
    @State private var showPrivacy = false

    private var filtered: [Recording] {
        store.recordings.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            || $0.transcript.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("连接与实时字幕") {
                    Text(connectivity.connection).font(.caption)
                    if !connectivity.liveSubtitle.isEmpty { Text(connectivity.liveSubtitle).textSelection(.enabled) }
                    if let error = connectivity.error { Text(error).foregroundStyle(.orange) }
                }
                if !model.consent {
                    Section("开始转写前") {
                        Text("默认仅使用设备上的中文模型。你也可以在识别设置中允许 Apple 在线识别；届时音频可能发送给 Apple。录音保存和同步无需开启转写。")
                        Button("识别设置与授权") { showPrivacy = true }
                    }
                }
                if let error = store.storageError { Text(error).foregroundStyle(.red) }
                if let notice = model.notice { Text(notice).foregroundStyle(.orange) }
                Section("录音") {
                    if filtered.isEmpty { Text("暂无录音，请在 Apple Watch 上开始录音。").foregroundStyle(.secondary) }
                    ForEach(filtered) { record in
                        NavigationLink {
                            RecordingDetailView(id: record.id, model: model, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title)
                                Text(record.metadata.createdAt, style: .date).font(.caption)
                                Text("\(Int(record.metadata.duration)) 秒 · \(record.state.label)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { model.delete(record.id) }
                        }
                    }
                }
            }
            .navigationTitle("腕录 AI")
            .searchable(text: $search, prompt: "搜索标题或文字")
            .toolbar { Button("识别设置") { showPrivacy = true } }
            .sheet(isPresented: $showPrivacy) {
                NavigationStack {
                    Form {
                        Section("音频与识别") {
                            Text("录音先保存在手表，并通过 WatchConnectivity 发送到配对 iPhone。默认要求设备本地识别；若没有中文本地模型，转写会明确失败，原音频仍保留。")
                            Toggle("允许 Apple 在线识别", isOn: $model.allowOnline)
                            Text("开启后系统 Speech 框架可能将音频发送给 Apple。处理和保留规则遵循 Apple 的服务条款。本应用没有自建服务器、第三方 ASR 密钥或分析上传。")
                            Button("我已了解，申请语音识别授权") { Task { await model.authorize() } }
                        }
                        Section("数据管理") {
                            Text("可在录音详情导出音频和 TXT。删除 iPhone 录音不会自动删除手表副本；手表收到接收确认后，可单独删除其本地副本。导出文件由你选择的接收方管理。")
                        }
                    }
                    .navigationTitle("隐私与识别设置")
                    .toolbar { Button("完成") { showPrivacy = false } }
                }
            }
        }
    }
}
