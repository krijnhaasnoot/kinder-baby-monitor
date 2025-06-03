import SwiftUI
import AVFoundation
import WebRTC
import AudioToolbox

// ----------------------------------------------------------------
// MARK: - ICE State Delegate Class
// ----------------------------------------------------------------
final class ICEStateDelegate: CloudNetworkManagerDelegate {
    var onIceStateChange: ((RTCIceConnectionState) -> Void)?
    
    func cloudNetworkManager(_ manager: CloudNetworkManager, didChangeIceState state: RTCIceConnectionState) {
        print("ICE verbinding status veranderd: \(state.rawValue)")
        onIceStateChange?(state)
    }
}

// ----------------------------------------------------------------
// MARK: - Main View
// ----------------------------------------------------------------
struct BabyMonitorViewer: View {
    @ObservedObject var signalingClient: SignalingClient
    @State private var cloudNetworkManager: CloudNetworkManager?
    @State private var iceDelegate = ICEStateDelegate()  // Delegate object

    @State private var connectionCode = ""
    @State private var isConnected = false
    @State private var isConnecting = false

    // live dB-waarde van baby
    @State private var remoteDB: Float = -90

    // UI-alert
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // Audio status tracking
    @State private var receivedAudioTrack = false
    @State private var lastAudioLevelReceived = Date()
    
    // Voor opgeslagen codes
    @State private var usingSavedCode = false
    
    // Debug logging
    @State private var debugLogs: [String] = []
    @State private var showDebugView = true
    @State private var autoScroll = true
    
    // Scroll view reader voor automatisch scrollen
    @Namespace private var bottomID

    var body: some View {
        VStack(spacing: 24) {
            if isConnected {
                HStack {
                    AudioWaveView(db: remoteDB)
                        .frame(height: 200)
                        .padding(.horizontal)
                    
                    // Debug-toggle aan de rechterkant
                    VStack {
                        Button(action: {
                            showDebugView.toggle()
                        }) {
                            Image(systemName: showDebugView ? "terminal.fill" : "terminal")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            addDebugLog("Test Audio knop ingedrukt")
                            playTestSound()
                        }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 8)
                        
                        Button(action: {
                            debugLogs.removeAll()
                        }) {
                            Image(systemName: "trash")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 8)
                    }
                }
                
                // Status indicator
                Group {
                    if receivedAudioTrack {
                        Text("✅ Audio verbinding actief")
                            .foregroundColor(.green)
                    } else {
                        Text("⚠️ Wachten op audio...")
                            .foregroundColor(.orange)
                    }
                    
                    if Date().timeIntervalSince(lastAudioLevelReceived) > 5 {
                        Text("⚠️ Geen recente dB updates")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                
                // Debug logs view
                if showDebugView {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Debug Logs")
                                .font(.headline)
                            
                            Spacer()
                            
                            Toggle("Auto-scroll", isOn: $autoScroll)
                                .labelsHidden()
                        }
                        .padding(.horizontal)
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(0..<debugLogs.count, id: \.self) { index in
                                        Text(debugLogs[index])
                                            .font(.system(size: 12, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(index % 2 == 0 ? Color.gray.opacity(0.1) : Color.clear)
                                            .cornerRadius(4)
                                    }
                                    
                                    // Invisible view at the bottom for scrolling
                                    Color.clear.frame(height: 1).id(bottomID)
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 150)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                            .onChange(of: debugLogs) { newLogs in
                                if autoScroll {
                                    withAnimation {
                                        proxy.scrollTo(bottomID, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button("Verbinding verbreken", role: .destructive) {
                    cleanup()
                }
                .buttonStyle(.borderedProminent)

            } else {
                VStack(spacing: 20) {
                    // Toon een knop voor opgeslagen code als die er is
                    if signalingClient.hasSavedPairingCode && !usingSavedCode {
                        Button {
                            usingSavedCode = true
                            if let savedCode = signalingClient.getLastPairingCode() {
                                connectionCode = savedCode
                                connectWithCode()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                Text("Verbind met laatst gebruikte apparaat")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        Text("OF")
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                    }
                    
                    TextField("Verbindingscode", text: $connectionCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .padding(.horizontal)

                    Button("Verbind met code") { connectWithCode() }
                        .buttonStyle(.borderedProminent)

                    ConnectionIndicator(isConnected: false,
                                        isConnecting: isConnecting)
                }
            }
        }
        .padding()
        .alert("Fout", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: { Text(alertMessage) }
        .onAppear {
            signalingClient.connect()
            configureAudioSession()
            
            // Debug logs weergeven
            addDebugLog("App gestart, SignalingClient verbinding...")
            
            // Check of er een opgeslagen code is
            if signalingClient.hasSavedPairingCode {
                addDebugLog("Opgeslagen verbindingscode gevonden: \(signalingClient.getLastPairingCode() ?? "none")")
            }
        }
        .onDisappear {
            cleanup()
            signalingClient.disconnect()
        }
    }
    
    // Helper om debug logs toe te voegen
    private func addDebugLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        debugLogs.append(logEntry)
        
        // Beperk het aantal logs (optioneel)
        if debugLogs.count > 100 {
            debugLogs.removeFirst()
        }
    }

    // ----------------------------------------------------------------
    // MARK: Audio Setup
    // ----------------------------------------------------------------
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        // Stap voor stap configuratie met error handling
        do {
            addDebugLog("Stap 1: AVAudioSession categorie instellen")
            
            // Probeer een eenvoudigere configuratie zonder alle opties
            try session.setCategory(.playback)
            
            addDebugLog("Stap 2: AVAudioSession activeren")
            try session.setActive(true)
            
            addDebugLog("Stap 3: Audio route controleren")
            if let output = session.currentRoute.outputs.first {
                addDebugLog("Huidige audio output: \(output.portName) (\(output.portType.rawValue))")
            }
            
            addDebugLog("Stap 4: Poging om audio naar speaker te routeren")
            // Deze stap kan de -50 error veroorzaken, dus proberen we het voorzichtig
            do {
                try session.overrideOutputAudioPort(.speaker)
                addDebugLog("✅ Audio met succes naar speaker gerouteerd")
            } catch {
                // Als deze specifieke stap mislukt, loggen we het maar gaan we door
                addDebugLog("❌ Kon audio niet direct naar speaker routeren: \(error.localizedDescription)")
                addDebugLog("De app zal proberen de standaard audio-uitvoer te gebruiken")
            }
            
            // Test audio om te controleren of het werkt
            playTestSound()
        } catch {
            addDebugLog("❌ AVAudioSession configuratie fout: \(error.localizedDescription)")
            alertMessage = "Fout bij audio-configuratie: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func playTestSound() {
        addDebugLog("Poging om testtoon af te spelen...")
        
        // Systeem geluid
        let systemSoundID: UInt32 = 1000 // Standaard systeemgeluid
        AudioServicesPlaySystemSound(systemSoundID)
        addDebugLog("✅ Systeem testtoon afgespeeld")
    }
    
    // ----------------------------------------------------------------
    // MARK: Acties
    // ----------------------------------------------------------------
    private func connectWithCode() {
        guard !connectionCode.isEmpty else {
            alertMessage = "Voer een verbindingscode in"
            showAlert    = true
            return
        }

        addDebugLog("Verbinden met code: \(connectionCode)")
        isConnecting = true
        signalingClient.joinWithCode(connectionCode)
        
        // Sla de code op voor toekomstig gebruik
        signalingClient.saveLastPairingCode(connectionCode)
        addDebugLog("Verbindingscode opgeslagen voor toekomstig gebruik")
        
        setupNetworkManager()
    }

    private func setupNetworkManager() {
        addDebugLog("NetworkManager opzetten...")
        let manager = CloudNetworkManager(signalingClient: signalingClient)

        // Configure audio level callback
        manager.onRemoteAudioLevel = { db in
            // Update UI op de main thread
            DispatchQueue.main.async {
                self.lastAudioLevelReceived = Date()
                self.remoteDB = db
                
                // Log niet elke dB-waarde om spam te voorkomen, alleen significante veranderingen
                if abs(db - self.remoteDB) > 5 {
                    self.addDebugLog("dB update: \(String(format: "%.1f", db)) dB")
                }
            }
        }
        
        // Configure remote track callback
        manager.onRemoteTrack = { audioTrack in
            DispatchQueue.main.async {
                self.addDebugLog("🎵 Remote audio track ontvangen: ID=\(audioTrack.trackId)")
                self.receivedAudioTrack = true
                
                // Voor extra zekerheid, forceer audio naar speaker en check volume
                do {
                    // Voorzichtige poging om audio naar speaker te routeren
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                    self.addDebugLog("Audio naar speaker gerouteerd na track ontvangst")
                    
                    // Test audio na ontvangst van track
                    self.playTestSound()
                } catch {
                    self.addDebugLog("❌ Kon audio niet naar speaker routeren: \(error.localizedDescription)")
                    // Ga door, zelfs als we de route niet kunnen veranderen
                }
            }
        }
        
        // Configure ICE state delegate
        iceDelegate.onIceStateChange = { state in
            DispatchQueue.main.async {
                self.addDebugLog("🧊 ICE status: \(state.rawValue)")
                
                switch state {
                case .checking:
                    self.addDebugLog("ICE checking - zoekt naar verbinding...")
                    
                case .connected, .completed:
                    self.addDebugLog("✅ ICE verbonden! Audio zou nu moeten werken.")
                    
                    // Extra check: Force audio route naar speaker
                    do {
                        // Voorzichtige poging om audio naar speaker te routeren
                        try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                        self.addDebugLog("Audio naar speaker gerouteerd na ICE verbinding")
                    } catch {
                        self.addDebugLog("❌ Kon audio niet naar speaker routeren: \(error.localizedDescription)")
                        // Ga door, zelfs als we de route niet kunnen veranderen
                    }
                    
                case .failed:
                    self.addDebugLog("❌ ICE verbinding mislukt!")
                    self.alertMessage = "Verbindingsfout. Probeer opnieuw te verbinden."
                    self.showAlert = true
                    
                case .disconnected:
                    self.addDebugLog("⚠️ ICE verbinding verbroken")
                    
                case .closed:
                    self.addDebugLog("ICE verbinding gesloten")
                    
                default:
                    self.addDebugLog("ICE status gewijzigd: \(state.rawValue)")
                }
            }
        }
        
        manager.delegate = iceDelegate
        cloudNetworkManager = manager
        manager.startAsViewer()
        addDebugLog("NetworkManager gestart als viewer")

        // markeer als verbonden na ICE-stabilisatie
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isConnected  = true
            self.isConnecting = false
            self.addDebugLog("UI gemarkeerd als verbonden")
            
            // Test nog een keer of audio werkt
            self.playTestSound()
        }
    }

    private func cleanup() {
        addDebugLog("Opruimen...")
        cloudNetworkManager = nil
        isConnected  = false
        isConnecting = false
        receivedAudioTrack = false
        addDebugLog("Verbinding verbroken")
    }
}

// --------------------------------------------------------------------
// MARK: – Wave-visualisatie
// --------------------------------------------------------------------
private struct AudioWaveView: View {

    var db: Float                                      // input

    @State private var phase:  CGFloat = 0
    @State private var level:  CGFloat = 0
    private let timer = Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {

            GeometryReader { geo in
                Canvas { ctx, size in
                    let w = size.width
                    let h = size.height / 2
                    var path = Path()
                    path.move(to: .zero)
                    for x in stride(from: 0, to: w, by: 1) {
                        let p = x / w
                        let y = h + sin(p * 2 * .pi + phase) * h * level
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    ctx.stroke(path, with: .color(.blue), lineWidth: 3)
                }
            }

            Text(statusText(for: db))
                .font(.title2.bold())
                .foregroundColor(color(for: db))
        }
        .onReceive(timer) { _ in
            phase += .pi / 16
            level  = mapped(from: db)
        }
        .animation(.easeOut(duration: 0.05), value: level)
    }

    // helpers ---------------------------------------------------------
    private func mapped(from db: Float) -> CGFloat {
        CGFloat(max(0, min(1, (90 + db) / 60)))
    }
    private func statusText(for db: Float) -> String {
        switch db {
        case ..<(-50):     return "Baby slaapt"
        case -50 ... -30:  return "Baby is wakker"
        default:           return "Baby huilt"
        }
    }
    private func color(for db: Float) -> Color {
        switch db {
        case ..<(-50):     return .green
        case -50 ... -30:  return .orange
        default:           return .red
        }
    }
}

// --------------------------------------------------------------------
// MARK: Preview
// --------------------------------------------------------------------
#Preview {
    BabyMonitorViewer(signalingClient: SignalingClient())
}
