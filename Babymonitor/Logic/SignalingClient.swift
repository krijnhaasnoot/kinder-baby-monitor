//
//  SignalingClient.swift
//  Babymonitor
//
//  27-05-2025 - VERBETERD met betere Socket.IO configuratie
//

import Foundation
import WebRTC
import SocketIO
import ObjectiveC.runtime    // voor associatedObject
import Combine // Importeer Combine voor @Published en AnyCancellable

// MARK: - SignalingClient -------------------------------------------------
final class SignalingClient: NSObject, ObservableObject {

    // --------------------------------------------------------------------
    // Socket
    // --------------------------------------------------------------------
    private var socketManager: SocketManager?
    private var socket: SocketIOClient?

    // --------------------------------------------------------------------
    // Pairing- & UI-state
    // --------------------------------------------------------------------
    @Published var generatedCode: String?
    @Published var isConnected    = false
    @Published var pairingSuccess = false
    @Published var viewerJoined   = false

    // --------------------------------------------------------------------
    // Callbacks naar RTC-laag
    // --------------------------------------------------------------------
    var onOffer:     ((RTCSessionDescription) -> Void)?
    var onAnswer:    ((RTCSessionDescription) -> Void)?
    var onCandidate: ((RTCIceCandidate)      -> Void)?
    var onMonitoringStatusChanged: ((Bool)   -> Void)?

    // viewer-kant: dB-updates (toegevoegd via extensie onderaan)
    // var onRemoteAudioLevel: ((Float) -> Void)? // Deze is gedeclareerd in de extension

    // Voor debuggen
    private var connectionTimer: Timer?
    private var audioLevelTimer: Timer?
    private var cancellables = Set<AnyCancellable>() // Voor Combine subscriptions


    // --------------------------------------------------------------------
    // MARK: Connect / Disconnect - VERBETERD
    // --------------------------------------------------------------------
    func connect(to url: String = "https://kinder-baby-monitor-production.up.railway.app") {
        print("SignalingClient: Connecting to \(url)")
        
        // Voorkom dubbele connectie
        if socket?.status == .connected {
            print("SignalingClient: Already connected.")
            return
        }
        if socket?.status == .connecting {
            print("SignalingClient: Already connecting.")
            return
        }

        // VERBETERDE Socket.IO configuratie voor iOS
        socketManager = SocketManager(
            socketURL: URL(string: url)!,
            config: [
                .log(true),                    // Debug logging
                .compress,                     // Compressie
                .reconnects(true),             // Auto-reconnect
                .reconnectAttempts(5),         // Minder pogingen voor sneller feedback
                .reconnectWait(2),             // Sneller herverbinden
                .connectParams(["transport": "websocket"]), // Forceer WebSocket
                .forceWebsockets(true),        // 👈 BELANGRIJK: Forceer WebSocket transport
                .secure(true),                 // HTTPS verbinding
                .enableSOCKSProxy(false)       // Disable SOCKS proxy
            ]
        )
        
        socket = socketManager?.defaultSocket
        
        // EXTRA debug event handlers
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            print("✅ SignalingClient: Socket.IO CONNECTED successfully")
            print("   Connection established with Railway server")
            DispatchQueue.main.async {
                self?.isConnected = true
            }
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("🔌 SignalingClient: Socket.IO DISCONNECTED")
            print("   Reason: \(data)")
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.generatedCode = nil // Reset code bij disconnect
                self?.pairingSuccess = false
                self?.viewerJoined = false
            }
        }
        
        socket?.on(clientEvent: .error) { data, ack in
            print("❌ SignalingClient: Socket.IO ERROR")
            print("   Error data: \(data)")
        }
        
        socket?.on(clientEvent: .reconnect) { data, ack in
            print("🔄 SignalingClient: Socket.IO RECONNECTED")
        }
        
        socket?.on(clientEvent: .reconnectAttempt) { data, ack in
            print("🔄 SignalingClient: Socket.IO reconnect attempt... (\(data.first ?? "unknown"))")
        }
        
        socket?.on(clientEvent: .statusChange) { data, ack in
            print("📊 SignalingClient: Socket.IO status change: \(data)")
        }
        
        setupEventHandlers()
        socket?.connect()
        
        // Controleer regelmatig verbindingsstatus en stuur heartbeats
        startConnectionChecking()
    }

    func disconnect() {
        print("SignalingClient: Disconnecting from server")
        stopConnectionChecking()
        socket?.disconnect()
        socketManager = nil
        socket = nil
        cancellables.forEach { $0.cancel() } // Annuleer Combine subscriptions
        cancellables.removeAll()
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.generatedCode = nil
            self.pairingSuccess = false
            self.viewerJoined = false
        }
    }
    
    // Heartbeat en verbindingscontrole - VERBETERD
    private func startConnectionChecking() {
        connectionTimer?.invalidate() // Invalidate any existing timer
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let socket = self.socket else { return }
            
            print("🔍 Connection check - Socket status: \(socket.status)")
            
            if socket.status == .connected {
                print("SignalingClient: Still connected to server - sending heartbeat")
                socket.emit("heartbeat")
            } else {
                print("❌ SignalingClient: Socket not connected (status: \(socket.status)) - attempting reconnect")
                socket.connect() // Probeer opnieuw te verbinden
            }
        }
    }
    
    private func stopConnectionChecking() {
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    // --------------------------------------------------------------------
    // MARK: Pairing-API
    // --------------------------------------------------------------------
    func generateCode() {
        print("SignalingClient: Generating pairing code")
        guard socket?.status == .connected else {
            print("❌ SignalingClient: Cannot generate code - socket not connected")
            return
        }
        socket?.emit("generateCode")
    }
    
    func joinWithCode(_ code: String) {
        print("SignalingClient: Joining with code: \(code)")
        guard socket?.status == .connected else {
            print("❌ SignalingClient: Cannot join with code - socket not connected")
            return
        }
        socket?.emit("joinWithCode", code)
    }

    // --------------------------------------------------------------------
    // MARK: WebRTC-sen­ders
    // --------------------------------------------------------------------
    func sendOffer(_ offer: RTCSessionDescription) {
        print("SignalingClient: Sending offer")
        sendSDP("offer", offer)
    }
    
    func sendAnswer(_ answer: RTCSessionDescription) {
        print("SignalingClient: Sending answer")
        sendSDP("answer", answer)
    }

    func sendCandidate(_ cand: RTCIceCandidate) {
        guard let code = generatedCode else {
            print("SignalingClient: Cannot send candidate - no generated code")
            return
        }
        guard socket?.status == .connected else {
            print("❌ SignalingClient: Cannot send candidate - socket not connected")
            return
        }
        
        let dict: [String: Any] = [
            "candidate":     cand.sdp,
            "sdpMLineIndex": cand.sdpMLineIndex,
            "sdpMid":        cand.sdpMid ?? ""
        ]
        print("SignalingClient: Sending ICE candidate: \(cand.sdp)")
        socket?.emit("candidate", code, dict)
    }

    func sendMonitoringStatus(isActive: Bool) {
        guard let code = generatedCode else {
            print("SignalingClient: Cannot send monitoring status - no generated code")
            return
        }
        guard socket?.status == .connected else {
            print("❌ SignalingClient: Cannot send monitoring status - socket not connected")
            return
        }
        print("SignalingClient: Sending monitoring status: \(isActive)")
        socket?.emit("sendMonitoringStatus", code, isActive)
    }

    /// Baby-kant: verstuur dB-waarde - VERBETERD
    func postLocalAudioLevel(_ db: Float) {
        guard let code = generatedCode else {
            print("SignalingClient: Cannot send audio level - no generated code")
            return
        }
        guard socket?.status == .connected else {
            // print("❌ SignalingClient: Cannot send audio level - socket not connected") // Kan veel spammen
            return
        }
        
        // Minder spam in logs
        if Int.random(in: 1...20) == 1 {  // Log 5% van de berichten
            print("SignalingClient: Sending audio level: \(db) dB")
        }
        socket?.emit("audioLevel", code, ["value": db])
    }
    
    // Start een timer die regelmatig test-audiolevels stuurt (voor debugging)
    func startDebugAudioLevelSending() {
        guard audioLevelTimer == nil else { return }
        guard socket?.status == .connected else {
            print("❌ SignalingClient: Cannot start debug audio - socket not connected")
            return
        }
        
        print("SignalingClient: Starting debug audio level timer")
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Genereer een willekeurige dB-waarde voor testen
            let randomDB = Float.random(in: -80...(-30))
            print("SignalingClient: Sending debug audio level: \(randomDB) dB")
            self?.postLocalAudioLevel(randomDB)
        }
    }

    // --------------------------------------------------------------------
    // MARK: Event-handlers - VERBETERD
    // --------------------------------------------------------------------
    private func setupEventHandlers() {
        guard let socket else { return }

        // Connection events zijn al hierboven ingesteld in connect()

        // Pairing
        socket.on("codeGenerated") { [weak self] data,_ in
            if let code = data[0] as? String {
                print("SignalingClient: Code generated: \(code)")
                DispatchQueue.main.async {
                    self?.generatedCode = code
                }
            } else {
                print("❌ SignalingClient: Invalid code generated response: \(data)")
            }
        }
        
        socket.on("pairingSuccess") { [weak self] _,_ in
            print("SignalingClient: Pairing successful")
            DispatchQueue.main.async {
                self?.pairingSuccess = true
            }
        }
        
        socket.on("viewerJoined") { [weak self] _,_ in
            print("SignalingClient: Viewer joined")
            DispatchQueue.main.async {
                self?.viewerJoined = true
            }
        }

        // WebRTC signaling
        socket.on("offer") { [weak self] data,_ in
            print("SignalingClient: Received offer")
            self?.handleSDP(data, offer: true)
        }
        
        socket.on("answer") { [weak self] data,_ in
            print("SignalingClient: Received answer")
            self?.handleSDP(data, offer: false)
        }
        
        socket.on("candidate") { [weak self] data,_ in
            print("SignalingClient: Received ICE candidate")
            self?.handleCandidate(data)
        }

        // Monitoring-status
        socket.on("monitoringStatus") { [weak self] data,_ in
            if let on = data[0] as? Bool {
                print("SignalingClient: Received monitoring status: \(on)")
                self?.onMonitoringStatusChanged?(on)
            }
        }

        // Audio-level
        enableAudioLevelListener()          // viewer-kant callback
    }

    // --------------------------------------------------------------------
    // MARK: Helpers
    // --------------------------------------------------------------------
    private func handleSDP(_ data: [Any], offer: Bool) {
        guard
            let dict = data[0] as? [String: Any],
            let sdp  = dict["sdp"]  as? String,
            let typ  = dict["type"] as? String,
            let kind = RTCSdpType(from: typ)
        else {
            print("SignalingClient: Failed to parse SDP from data: \(data)")
            return
        }

        print("SignalingClient: Parsed SDP of type \(kind.stringValue)")
        let desc = RTCSessionDescription(type: kind, sdp: sdp)
        offer ? onOffer?(desc) : onAnswer?(desc)
    }

    private func handleCandidate(_ data: [Any]) {
        guard
            let dict = data[0] as? [String: Any],
            let sdp  = dict["candidate"]     as? String,
            let idx  = dict["sdpMLineIndex"] as? Int32,
            let mid  = dict["sdpMid"]        as? String
        else {
            print("SignalingClient: Failed to parse ICE candidate from data: \(data)")
            return
        }

        print("SignalingClient: Parsed ICE candidate with mid: \(mid), index: \(idx)")
        let cand = RTCIceCandidate(sdp: sdp, sdpMLineIndex: idx, sdpMid: mid)
        onCandidate?(cand)
    }

    private func sendSDP(_ evt: String, _ desc: RTCSessionDescription) {
        guard let code = generatedCode else {
            print("SignalingClient: Cannot send SDP - no generated code")
            return
        }
        guard socket?.status == .connected else {
            print("❌ SignalingClient: Cannot send SDP - socket not connected")
            return
        }
        
        let dict: [String: Any] = ["type": desc.type.stringValue,
                                   "sdp":  desc.sdp]
        print("SignalingClient: Sending SDP event: \(evt) of type: \(desc.type.stringValue)")
        socket?.emit(evt, code, dict)
    }
}

// --------------------------------------------------------------------
// MARK: RTCSdpType helpers
// --------------------------------------------------------------------
extension RTCSdpType {
    init?(from str: String) {
        switch str {
        case "offer":    self = .offer
        case "answer":   self = .answer
        case "prAnswer": self = .prAnswer
        default:         return nil
        }
    }
    var stringValue: String {
        switch self {
        case .offer:    return "offer"
        case .answer:   return "answer"
        case .prAnswer: return "prAnswer"
        case .rollback: return "rollback"
        @unknown default: return "unknown"
        }
    }
}

// --------------------------------------------------------------------
// MARK: Audio-level extensie (associatedObject)
// --------------------------------------------------------------------
private enum LevelKey { static var cb = 0 }

extension SignalingClient {

    /// Viewer-kant callback
    var onRemoteAudioLevel: ((Float) -> Void)? {
        get { objc_getAssociatedObject(self, &LevelKey.cb) as? (Float) -> Void }
        set { objc_setAssociatedObject(self, &LevelKey.cb, newValue, .OBJC_ASSOCIATION_COPY) } // Corrected: Use OBJC_ASSOCIATION_COPY, not NONATOMIC
    }

    /// Luister voor "audioLevel" berichten
    func enableAudioLevelListener() {
        print("SignalingClient: Enabling audio level listener")
        socket?.on("audioLevel") { [weak self] data, _ in
            if let dict = data[0] as? [String: Any],
               let v = dict["value"] as? Double {
                let level = Float(v)
                if Int.random(in: 1...20) == 1 {  // Log 5% van de berichten
                    print("SignalingClient: Received audio level: \(level) dB")
                }
                self?.onRemoteAudioLevel?(level)
            } else {
                print("SignalingClient: Received malformed audio level data: \(data)")
            }
        }
    }
}

// --------------------------------------------------------------------
// MARK: Persistente apparaatkoppeling
// --------------------------------------------------------------------
extension SignalingClient {
    /// Sla de huidige koppelcode op in UserDefaults
    func saveLastPairingCode(_ code: String) {
        print("SignalingClient: Saving pairing code: \(code)")
        UserDefaults.standard.set(code, forKey: "lastPairingCode")
    }
    
    /// Haal de laatst gebruikte koppelcode op uit UserDefaults
    func getLastPairingCode() -> String? {
        let code = UserDefaults.standard.string(forKey: "lastPairingCode")
        print("SignalingClient: Retrieved pairing code: \(code ?? "nil")")
        return code
    }
    
    /// Controleer of er een opgeslagen koppelcode is
    var hasSavedPairingCode: Bool {
        return getLastPairingCode() != nil
    }
    
    /// Wis de opgeslagen koppelcode
    func clearSavedPairingCode() {
        print("SignalingClient: Clearing saved pairing code")
        UserDefaults.standard.removeObject(forKey: "lastPairingCode")
    }
}
