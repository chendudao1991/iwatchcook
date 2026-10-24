import Foundation
import WatchConnectivity
import Combine

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var connection = "正在连接 iPhone"
    @Published var subtitle = ""
    @Published var liveStatus = ""
    @Published private(set) var reachable = false
    private let library: WatchLibrary
    private var liveID: UUID?
    private var sequence = 0
    private var subtitleSequence = 0
    private var ready = false
    private var inFlight = false
    private var epoch = UUID()

    init(library: WatchLibrary) {
        self.library = library
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func retryTransfers() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let outstanding = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?["id"] as? String })
        for item in library.items where item.finalized && !item.acknowledged {
            guard !outstanding.contains(item.id.uuidString) else { continue }
            let url = library.audioURL(item.id)
            guard FileManager.default.fileExists(atPath: url.path) else {
                library.transferFailed(item.id, message: "本地音频不存在，未传输。")
                continue
            }
            session.transferFile(url, metadata: item.metadata.transferInfo)
        }
    }

    func beginLive(_ id: UUID) {
        liveID = id
        sequence = 0
        subtitleSequence = 0
        subtitle = ""
        resumeLive()
    }

    func resumeLive() {
        guard let id = liveID else { return }
        epoch = UUID()
        inFlight = false
        ready = false
        guard reachable else {
            liveStatus = "iPhone 暂不可达；本地录音继续"
            return
        }
        liveStatus = "正在请求实时识别"
        sequence += 1
        subtitleSequence = sequence
        let token = epoch
        transmit(LivePacket(kind: .start, recordingID: id, sequence: sequence, streamID: token), token: token) { [weak self] ok in
            self?.ready = ok
            self?.liveStatus = ok ? "实时字幕已连接" : "实时不可用；本地录音继续，可重连"
        }
    }

    func sendPCM(_ bytes: Data) {
        guard let id = liveID, ready else { return }
        guard !inFlight else {
            ready = false
            liveStatus = "实时链路拥塞；本地录音继续，可重连"
            return
        }
        sequence += 1
        inFlight = true
        transmit(LivePacket(kind: .audio, recordingID: id, sequence: sequence, pcm: bytes, streamID: epoch), token: epoch) { [weak self] ok in
            guard let self else { return }
            self.inFlight = false
            if !ok { self.ready = false; self.liveStatus = "实时发送失败；本地录音继续" }
        }
    }

    func endLive() {
        if let id = liveID, reachable {
            transmit(LivePacket(kind: .stop, recordingID: id, sequence: sequence, streamID: epoch), token: epoch) { _ in }
        }
        epoch = UUID()
        liveID = nil
        ready = false
        inFlight = false
    }

    private func transmit(_ packet: LivePacket, token: UUID, completion: @escaping (Bool) -> Void) {
        guard let bytes = try? packet.encoded(), WCSession.default.isReachable else { completion(false); return }
        WCSession.default.sendMessage(["packet": bytes], replyHandler: { [weak self] response in
            let ok = response["ok"] as? Bool == true
            Task { @MainActor in
                guard self?.epoch == token else { return }
                completion(ok)
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard self?.epoch == token else { return }
                completion(false)
            }
        })
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bytes = message["packet"] as? Data, let packet = LivePacket.decode(bytes) else { return }
        Task { @MainActor in
            guard packet.recordingID == self.liveID, packet.streamID == self.epoch,
                  packet.sequence >= self.subtitleSequence else { return }
            self.subtitleSequence = packet.sequence
            if packet.kind == .subtitle { self.subtitle = packet.text ?? "" }
            if packet.kind == .unavailable {
                self.ready = false
                self.liveStatus = packet.text ?? "实时不可用，本地录音继续"
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let raw = userInfo["ack"] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.library.acknowledge(id) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let error, let raw = fileTransfer.file.metadata?["id"] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.library.transferFailed(id, message: error.localizedDescription) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) { refresh(session) }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }

    private nonisolated func refresh(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            self.connection = reachable ? "iPhone 实时可达" : "iPhone 暂不可达"
            self.retryTransfers()
            self.resumeLive()
        }
    }
}
