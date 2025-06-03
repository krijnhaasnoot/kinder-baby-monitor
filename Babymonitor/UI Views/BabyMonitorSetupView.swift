//
//  BabyMonitorSetupView.swift
//  Babymonitor
//
//  Updated: 27-05-2025
//

import SwiftUI
import AVFoundation

struct BabyMonitorSetupView: View {

    // --------------------------------------------------------------------
    // MARK: Dependencies & State
    // --------------------------------------------------------------------
    @ObservedObject var signalingClient: SignalingClient
    @State private var cloudNetworkManager: CloudNetworkManager?

    @State private var isMonitoring = false
    @State private var showAlert   = false
    @State private var alertMessage = ""
    
    // Nieuwe state voor het gebruik van een opgeslagen code
    @State private var usingSavedCode = false

    // --------------------------------------------------------------------
    // MARK: UI
    // --------------------------------------------------------------------
    var body: some View {
        VStack(spacing: 20) {
            if signalingClient.isConnected {
                connectedSection
            } else {
                Text("Verbinding maken met server...")
                    .font(.headline)
                ConnectionIndicator(isConnected: false, isConnecting: true)
            }
        }
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Fout"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
        .onAppear {
            setupConnection()
            requestMicrophonePermission()
        }
        .onDisappear { cleanup() }
    }

    // MARK: – Sub-view wanneer we al verbonden zijn
    @ViewBuilder
    private var connectedSection: some View {
        if let code = signalingClient.generatedCode {
            Text("Verbindingscode")
                .font(.headline)

            Text(code)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                
            // Sla de code op wanneer deze wordt gegenereerd
            .onAppear {
                signalingClient.saveLastPairingCode(code)
            }

            Text("Deel deze code met een ander apparaat om te verbinden")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if signalingClient.viewerJoined {
                Text("Apparaat verbonden! 🎉")
                    .font(.headline)
                    .foregroundColor(.green)

                Button(action: toggleMonitoring) {
                    HStack {
                        Image(systemName: isMonitoring ? "mic.fill" : "mic.slash.fill")
                        Text(isMonitoring ? "Monitoring stoppen" : "Monitoring starten")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(isMonitoring ? Color.red : Color.green)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top)

            } else {
                Text("Wachten op verbinding…")
                    .font(.subheadline)
                    .foregroundColor(.orange)

                ConnectionIndicator(isConnected: false, isConnecting: true)
            }
        } else {
            VStack(spacing: 20) {
                Text("Druk op de knop om een verbindingscode te genereren")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                
                // Toon knop voor opgeslagen code als die er is
                if signalingClient.hasSavedPairingCode && !usingSavedCode {
                    Button {
                        usingSavedCode = true
                        if let savedCode = signalingClient.getLastPairingCode() {
                            // Gebruik de opgeslagen code
                            signalingClient.joinWithCode(savedCode)
                        }
                    } label: {
                        Text("Gebruik laatste verbinding")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    signalingClient.generateCode()
                } label: {
                    Text("Nieuwe code genereren")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // --------------------------------------------------------------------
    // MARK: Setup & Permissions
    // --------------------------------------------------------------------
    private func setupConnection() {
        signalingClient.connect()
    }

    private func requestMicrophonePermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                handleMicPermission(granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                handleMicPermission(granted)
            }
        }
    }

    private func handleMicPermission(_ granted: Bool) {
        if !granted {
            DispatchQueue.main.async {
                alertMessage = "Microfoon toegang is nodig voor de baby-monitor."
                showAlert = true
            }
        }
    }

    // --------------------------------------------------------------------
    // MARK: Monitoring start/stop
    // --------------------------------------------------------------------
    private func toggleMonitoring() {
        isMonitoring.toggle()

        if isMonitoring {
            startMonitoring()
        } else {
            stopMonitoring()
        }

        signalingClient.sendMonitoringStatus(isActive: isMonitoring)
    }

    private func startMonitoring() {
        guard cloudNetworkManager == nil else { return }

        let manager = CloudNetworkManager(signalingClient: signalingClient)
        manager.startAsMonitor()
        cloudNetworkManager = manager
    }

    private func stopMonitoring() {
        cloudNetworkManager = nil          // ARC ruimt de verbinding op
    }

    private func cleanup() {
        stopMonitoring()
        signalingClient.disconnect()
    }
}
