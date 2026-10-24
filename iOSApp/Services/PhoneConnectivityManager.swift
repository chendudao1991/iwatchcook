import Foundation
import WatchConnectivity
import Combine

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var connection = "正在连接手表"
    @Published var liveSubtitle = ""
    @Published var error: String?
    var onImport: ((UUID) -> Void)?
    var onLivePacket: ((LivePacket) throws -> Void)?
    private let store: RecordingStore

    init(store: RecordingStore) {
        self.store = store
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        } else { connection = "此设备不支持手表连接" }
    }

    func send(_ packet: LivePacket) {
        if packet.kind == .subtitle { liveSubtitle = packet.text ?? "" }
        guard WCSession.default.isReachable, let data = try? packet.encoded() else { return }
        WCSession.default.sendMessage(["packet": data], replyHandler: nil) { [weak self] failure in
            Task { @MainActor in self?.error = failure.localizedDescription }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let info = file.metadata, let metadata = RecordingMetadata(transferInfo: info) else {
            Task { @MainActor in self.error = "收到不支持的录音元数据，未确认接收。" }
            return
        }
        do {
            let staged = try RecordingStore.stageIncomingFile(file.fileURL)
            Task { @MainActor in
                do {
                    let imported = try self.store.importAudio(staged, metadata: metadata)
                    // Durable acknowledgement is queued even when the Watch is currently unreachable.
                    session.transferUserInfo(["ack": metadata.id.uuidString])
                    if imported { self.onImport?(metadata.id) }
                } catch { self.error = "录音接收失败：\(error.localizedDescription)" }
            }
        } catch { Task { @MainActor in self.error = error.localizedDescription } }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["packet"] as? Data, let packet = LivePacket.decode(data) else {
            replyHandler(["ok": false]); return
        }
        Task { @MainActor in
            do {
                guard let handler = self.onLivePacket else { throw SpeechFailure.unavailable }
                try handler(packet)
                replyHandler(["ok": true])
            } catch {
                self.error = error.localizedDescription
                self.send(LivePacket(kind: .unavailable, recordingID: packet.recordingID,
                                     sequence: packet.sequence, text: error.localizedDescription, streamID: packet.streamID))
                replyHandler(["ok": false])
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        refresh(session, error: error)
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { refresh(session, error: nil) }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    private nonisolated func refresh(_ session: WCSession, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.connection = reachable ? "手表实时可达" : "手表暂不可达，文件可后台排队同步"
            if let error { self.error = error.localizedDescription }
        }
    }
}
