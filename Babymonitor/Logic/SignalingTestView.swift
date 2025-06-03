//
//  SignalingTestView.swift
//  Babymonitor
//
//  Test view voor SignalingClient dB-verzending
//

import SwiftUI
import AVFoundation

struct SignalingTestView: View {
    @StateObject private var signalingClient = SignalingClient()
    @State private var audioMonitor: AudioMonitor?
    @State private var isMonitoring = false
    @State private var connectionStatus = "Niet verbonden"
    @State private var lastSentDB: Float = 0.0
    @State private var lastReceivedDB: Float = 0.0
    @State private var sentCount = 0
    @State private var receivedCount = 0
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🌐 SignalingClient Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Verbindingsstatus
            VStack(spacing: 8) {
                Text("Socket.IO Status:")
                    .font(.headline)
                Text(connectionStatus)
                    .font(.subheadline)
                    .foregroundColor(signalingClient.isConnected ? .green : .red)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // dB Statistieken
            HStack(spacing: 20) {
                VStack {
                    Text("Verzonden")
                        .font(.headline)
                    Text("\(String(format: "%.1f", lastSentDB)) dB")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("(\(sentCount)x)")
                        .font(.caption)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                
                VStack {
                    Text("Ontvangen")
                        .font(.headline)
                    Text("\(String(format: "%.1f", lastReceivedDB)) dB")
                        .font(.title2)
                        .foregroundColor(.green)
                    Text("(\(receivedCount)x)")
                        .font(.caption)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Control buttons
            VStack(spacing: 15) {
                Button(action: connectToServer) {
                    Text("Verbind met Server")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(signalingClient.isConnected ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(signalingClient.isConnected)
                
                Button(action: generateTestCode) {
                    Text("Genereer Test Code")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                }
                .disabled(!signalingClient.isConnected)
                
                Button(action: startAudioAndSending) {
                    Text(isMonitoring ? "Stop Audio Test" : "Start Audio + Verzending")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMonitoring ? Color.red : Color.green)
                        .cornerRadius(12)
                }
                .disabled(!signalingClient.isConnected || signalingClient.generatedCode == nil)
                
                Button(action: sendTestLevels) {
                    Text("Stuur Test dB-waarden")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                }
                .disabled(!signalingClient.isConnected || signalingClient.generatedCode == nil)
            }
            
            // Status info
            VStack(alignment: .leading, spacing: 8) {
                if let code = signalingClient.generatedCode {
                    Text("Generated Code: \(code)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Text("Console Instructies:")
                    .font(.headline)
                Text("1. Verbind met server")
                Text("2. Genereer een test code")
                Text("3. Start audio + verzending")
                Text("4. Maak geluid en kijk naar console")
                Text("5. Controleer of dB-waarden worden verzonden")
            }
            .font(.caption)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Signaling Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupSignalingCallbacks()
        }
    }
    
    // MARK: - Setup
    private func setupSignalingCallbacks() {
        // Luister naar inkomende audio levels
        signalingClient.onRemoteAudioLevel = { [self] db in
            print("📥 Ontvangen audio level: \(db) dB")
            DispatchQueue.main.async {
                self.lastReceivedDB = db
                self.receivedCount += 1
            }
        }
    }
    
    // MARK: - Actions
    private func connectToServer() {
        print("🌐 Verbinden met server...")
        connectionStatus = "Verbinden..."
        
        signalingClient.connect()
        
        // Update status na korte delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if signalingClient.isConnected {
                connectionStatus = "Verbonden ✅"
                print("✅ Verbonden met server")
            } else {
                connectionStatus = "Verbinding mislukt ❌"
                print("❌ Verbinding met server mislukt")
            }
        }
    }
    
    private func generateTestCode() {
        print("🔢 Genereren van test code...")
        signalingClient.generateCode()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let code = signalingClient.generatedCode {
                print("✅ Test code gegenereerd: \(code)")
            } else {
                print("❌ Geen test code ontvangen")
            }
        }
    }
    
    private func startAudioAndSending() {
        if isMonitoring {
            // Stop alles
            print("🛑 Stoppen audio monitoring en verzending")
            audioMonitor?.stop()
            audioMonitor = nil
            isMonitoring = false
        } else {
            // Start audio monitoring met automatische verzending
            print("▶️ Starten audio monitoring met verzending")
            
            let monitor = AudioMonitor()
            monitor.onLevel = { [self] decibels in
                print("🎤 Audio level: \(decibels) dB - Verzenden...")
                
                // Verzend via SignalingClient
                signalingClient.postLocalAudioLevel(decibels)
                
                DispatchQueue.main.async {
                    self.lastSentDB = decibels
                    self.sentCount += 1
                }
            }
            
            monitor.start()
            audioMonitor = monitor
            isMonitoring = true
            
            print("✅ Audio monitoring + verzending gestart")
        }
    }
    
    private func sendTestLevels() {
        print("🧪 Verzenden van test dB-waarden...")
        
        // Verzend een reeks test-waarden
        let testValues: [Float] = [-80, -60, -40, -30, -50, -70]
        
        for (index, value) in testValues.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                print("📤 Verzenden test waarde: \(value) dB")
                signalingClient.postLocalAudioLevel(value)
                
                DispatchQueue.main.async {
                    self.lastSentDB = value
                    self.sentCount += 1
                }
            }
        }
    }
}

// MARK: - Preview
struct SignalingTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SignalingTestView()
        }
    }
}
