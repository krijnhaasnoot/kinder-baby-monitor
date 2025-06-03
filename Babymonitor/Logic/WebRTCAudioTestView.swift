//
//  WebRTCAudioTestView.swift
//  Babymonitor
//
//  Test de volledige WebRTC audio-overdracht tussen twee units
//

import SwiftUI
import WebRTC
import AVFoundation // Added AVFoundation import for AudioSessionManager usage
import Combine // Added Combine import for managing subscriptions

// Separate class voor CloudNetworkManagerDelegate
class WebRTCTestDelegate: NSObject, CloudNetworkManagerDelegate {
    var onIceStateChange: ((RTCIceConnectionState) -> Void)?
    
    func cloudNetworkManager(_ manager: CloudNetworkManager, didChangeIceState state: RTCIceConnectionState) {
        onIceStateChange?(state)
    }
}

struct WebRTCAudioTestView: View {
    @StateObject private var signalingClient = SignalingClient()
    @State private var networkManager: CloudNetworkManager?
    @State private var networkDelegate = WebRTCTestDelegate()
    @State private var localAudioMonitor: AudioMonitor?
    @State private var testMode: TestMode = .none
    @State private var connectionStatus = "Niet gestart"
    @State private var audioStatus = "Niet actief"
    @State private var lastAudioLevel: Float = 0.0
    @State private var generatedCode: String = ""
    @State private var inputCode: String = ""
    @State private var debugLogs: [String] = []
    
    // Combine cancellables for managing subscriptions
    @State private var cancellables = Set<AnyCancellable>() // Toegevoegd

    enum TestMode {
        case none, babyUnit, parentUnit
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🎵 WebRTC Audio Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Status indicators
            VStack(spacing: 12) {
                StatusRow(title: "Socket.IO", status: signalingClient.isConnected ? "Verbonden ✅" : "Niet verbonden ❌")
                StatusRow(title: "Test Mode", status: testMode == .none ? "Niet gekozen" : testMode == .babyUnit ? "Baby Unit 👶" : "Parent Unit 👨‍👩‍👧‍👦")
                StatusRow(title: "Verbinding", status: connectionStatus)
                StatusRow(title: "Audio", status: audioStatus)
            }
            
            // Mode selection
            if testMode == .none {
                VStack(spacing: 15) {
                    Text("Kies test modus:")
                        .font(.headline)
                    
                    Button("Test als Baby Unit") {
                        startBabyUnit()
                    }
                    .buttonStyle(TestButtonStyle(color: .blue))
                    
                    Button("Test als Parent Unit") {
                        startParentUnit()
                    }
                    .buttonStyle(TestButtonStyle(color: .green))
                }
            }
            
            // Baby Unit Interface
            if testMode == .babyUnit {
                VStack(spacing: 15) {
                    Text("Baby Unit Mode 👶")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if !generatedCode.isEmpty {
                        VStack {
                            Text("Deel deze code met Parent Unit:")
                                .font(.headline)
                            Text(generatedCode)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                    
                    Text("Audio Level: \(String(format: "%.1f", lastAudioLevel)) dB")
                        .font(.title3)
                        .foregroundColor(colorForLevel(lastAudioLevel))
                    
                    Button("Reset Test") {
                        resetTest()
                    }
                    .buttonStyle(TestButtonStyle(color: .red))
                }
            }
            
            // Parent Unit Interface
            if testMode == .parentUnit {
                VStack(spacing: 15) {
                    Text("Parent Unit Mode 👨‍👩‍👧‍👦")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack {
                        Text("Voer Baby Unit code in:")
                            .font(.headline)
                        TextField("Code van Baby Unit", text: $inputCode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.title2)
                            .multilineTextAlignment(.center)
                        
                        Button("Verbind met Baby Unit") {
                            connectToParent()
                        }
                        .buttonStyle(TestButtonStyle(color: .green))
                        .disabled(inputCode.isEmpty)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    Text("Ontvangen Audio: \(String(format: "%.1f", lastAudioLevel)) dB")
                        .font(.title3)
                        .foregroundColor(colorForLevel(lastAudioLevel))
                    
                    Button("Reset Test") {
                        resetTest()
                    }
                    .buttonStyle(TestButtonStyle(color: .red))
                }
            }
            
            // Debug logs
            if !debugLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Debug Logs:")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(debugLogs.indices, id: \.self) { index in
                                Text(debugLogs[index])
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("WebRTC Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupNetworkManager()
            // Zorg ervoor dat de SignalingClient verbinding maakt bij het opstarten van deze view
            signalingClient.connect()
        }
        .onDisappear {
            resetTest() // Zorg ervoor dat de sessie wordt opgeruimd bij het verlaten van de view
        }
    }
    
    // MARK: - Setup
    private func setupNetworkManager() {
        // Maak NetworkManager aan met SignalingClient
        let manager = CloudNetworkManager(signalingClient: signalingClient)
        networkManager = manager
        
        // Setup delegate callback
        networkDelegate.onIceStateChange = { state in
            // Gebruik rawValue voor RTCIceConnectionState
            let stateString = state.rawValue
            self.addLog("🧊 ICE State: \(stateString)")
            
            DispatchQueue.main.async {
                switch state {
                case .connected, .completed:
                    if self.testMode == .parentUnit {
                        self.connectionStatus = "WebRTC Audio Verbonden ✅"
                        self.audioStatus = "Klaar om audio te ontvangen"
                    } else if self.testMode == .babyUnit {
                        self.connectionStatus = "Parent Unit WebRTC Verbonden ✅"
                        self.audioStatus = "Audio streaming actief"
                    }
                case .failed:
                    self.connectionStatus = "WebRTC Verbinding mislukt ❌"
                    self.addLog("❌ WebRTC ICE verbinding mislukt - mogelijk firewall/NAT probleem")
                case .disconnected:
                    self.connectionStatus = "WebRTC Verbinding verbroken ❌"
                case .checking:
                    if self.testMode == .babyUnit {
                        self.connectionStatus = "WebRTC verbinding opzetten..."
                    }
                case .new:
                    self.addLog("🔄 ICE State: Nieuwe verbinding")
                default:
                    if self.testMode == .babyUnit {
                        self.connectionStatus = "WebRTC: \(stateString)"
                    }
                    self.addLog("🔄 ICE State: \(stateString)")
                }
            }
        }
        
        manager.delegate = networkDelegate
        
        // Setup SignalingClient callbacks
        signalingClient.onRemoteAudioLevel = { level in
            self.addLog("📥 Ontvangen audio level (Signaling): \(level) dB")
            DispatchQueue.main.async {
                self.lastAudioLevel = level
                if self.testMode == .parentUnit {
                    self.audioStatus = "Ontvangen: \(String(format: "%.1f", level)) dB"
                }
            }
        }
        
        // Callback voor daadwerkelijke WebRTC remote audio track (geluid)
        manager.onRemoteTrack = { track in
            self.addLog("✅ Remote WebRTC audio track ontvangen!")
            // De CloudNetworkManager beheert het afspelen van de WebRTC audio track zelf.
            DispatchQueue.main.async {
                self.audioStatus = "WebRTC Audio Track actief"
            }
        }
        
        // Setup pairing success callback met Combine
        signalingClient.$pairingSuccess
            .receive(on: DispatchQueue.main)
            .sink { success in
                if success && self.testMode == .babyUnit {
                    self.connectionStatus = "Parent Unit gekoppeld ✅"
                    self.addLog("✅ Parent Unit heeft zich gekoppeld via Signaling")
                }
            }
            .store(in: &cancellables)
        
        // Setup viewer joined callback met Combine
        signalingClient.$viewerJoined
            .receive(on: DispatchQueue.main)
            .sink { joined in
                if joined && self.testMode == .babyUnit {
                    self.addLog("🎉 Viewer Joined event ontvangen. Start WebRTC als monitor.")
                    self.networkManager?.startAsMonitor() // Start WebRTC hier na viewer join
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    private func startBabyUnit() {
        addLog("👶 Start Baby Unit mode")
        testMode = .babyUnit
        connectionStatus = "Verbinden met server..."
        
        // SignalingClient is al verbonden via onAppear
        // Genereer code zodra verbonden
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Geef connect tijd
            if self.signalingClient.isConnected {
                self.addLog("✅ SignalingClient verbonden - genereer code")
                self.signalingClient.generateCode()
                
                // Luister naar codeGenerated event met Combine
                self.signalingClient.$generatedCode
                    .compactMap { $0 } // Alleen als code niet nil is
                    .first() // Alleen de eerste keer
                    .sink { code in
                        self.generatedCode = code
                        self.addLog("✅ Code gegenereerd: \(code)")
                        self.connectionStatus = "Wacht op Parent Unit..."
                        self.audioStatus = "Audio monitoring actief (dB via signaling)"
                        // We starten networkManager.startAsMonitor() PAS als viewerJoined.
                        // Dit is belangrijke timing voor WebRTC handshake.
                        self.addLog("🎤 Audio monitoring gestart (locale dB voor UI)")
                        
                        // Start aparte AudioMonitor voor lokale dB weergave
                        self.startLocalAudioMonitoring()
                    }
                    .store(in: &cancellables)
            } else {
                self.connectionStatus = "Server verbinding mislukt"
                self.addLog("❌ Server verbinding mislukt")
            }
        }
    }
    
    private func startParentUnit() {
        addLog("👨‍👩‍👧‍👦 Start Parent Unit mode")
        testMode = .parentUnit
        connectionStatus = "Klaar om te verbinden"
        
        // SignalingClient is al verbonden via onAppear
        // Start als viewer
        self.networkManager?.startAsViewer() // Start WebRTC als viewer
        self.addLog("👂 CloudNetworkManager gestart als viewer")
    }
    
    private func connectToParent() {
        guard !inputCode.isEmpty else { return }
        
        addLog("🔗 Verbinden met Baby Unit code: \(inputCode)")
        connectionStatus = "Socket.IO koppeling..."
        
        signalingClient.joinWithCode(inputCode)
        
        // Monitoring van pairing success is nu via signalingClient.$pairingSuccess.sink
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // Geef tijd voor pairing
            if self.signalingClient.pairingSuccess {
                self.addLog("✅ Socket.IO koppeling succesvol. WebRTC handshake start.")
                self.connectionStatus = "WebRTC verbinding opzetten..."
                self.audioStatus = "Wachten op WebRTC audio..."
            } else {
                self.connectionStatus = "Socket.IO koppeling mislukt ❌"
                self.addLog("❌ Socket.IO koppeling mislukt")
            }
        }
    }
        
    private func resetTest() {
        addLog("🔄 Reset test")
        // Invalidate all Combine cancellables
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        testMode = .none
        connectionStatus = "Niet gestart"
        audioStatus = "Niet actief"
        lastAudioLevel = 0.0
        generatedCode = ""
        inputCode = ""
        debugLogs.removeAll()
        
        // Stop lokale audio monitoring
        localAudioMonitor?.stop()
        localAudioMonitor = nil
        
        // Deactiveer AVAudioSession via de manager
        do {
            try AudioSessionManager.shared.deactivate()
            addLog("✅ AVAudioSession gedeactiveerd bij reset")
        } catch {
            addLog("❌ Fout bij deactiveren AVAudioSession: \(error.localizedDescription)")
        }

        signalingClient.disconnect()
        networkManager = nil // Laat CloudNetworkManager deinit doen
    }
    
    // MARK: - Local Audio Monitoring
    private func startLocalAudioMonitoring() {
        addLog("🎤 Start lokale audio monitoring voor UI weergave")
        
        let monitor = AudioMonitor()
        monitor.onLevel = { level in
            self.addLog("🔊 Lokaal audio level: \(String(format: "%.1f", level)) dB (voor UI)")
            
            DispatchQueue.main.async {
                if self.testMode == .babyUnit {
                    self.lastAudioLevel = level
                }
            }
        }
        
        monitor.start()
        localAudioMonitor = monitor
        
        addLog("✅ Lokale audio monitoring gestart")
    }
    
    // MARK: - Helpers
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        debugLogs.append(logEntry)
        print(logEntry)
        
        // Hou logs beperkt
        if debugLogs.count > 50 {
            debugLogs.removeFirst()
        }
    }
    
    private func colorForLevel(_ level: Float) -> Color {
        if level > -40 {
            return .red
        } else if level > -60 {
            return .orange
        } else if level > -80 {
            return .green
        } else {
            return .gray
        }
    }
}

// MARK: - UI Components
struct StatusRow: View {
    let title: String
    let status: String
    
    var body: some View {
        HStack {
            Text("\(title):")
                .font(.headline)
            Spacer()
            Text(status)
                .font(.subheadline)
                .foregroundColor(status.contains("✅") ? .green : status.contains("❌") ? .red : .blue)
        }
        .padding(.horizontal)
    }
}

struct TestButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .cornerRadius(12)
    }
}

// MARK: - Preview
struct WebRTCAudioTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WebRTCAudioTestView()
        }
    }
}
