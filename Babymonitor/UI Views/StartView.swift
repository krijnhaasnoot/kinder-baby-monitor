//
//  StartView.swift
//  Babymonitor
//
//  Created by Krijn Haasnoot on 25/03/2025.
//  Updated with all debug/test options
//

import SwiftUI

struct StartView: View {
    @State private var navigateTo: Role? = nil
    @StateObject private var signalingClient = SignalingClient()

    enum Role: String, Identifiable, CaseIterable {
        case babyMonitor, parentUnit, audioTest, signalingTest, socketDebug, webrtcTest, serverDebug

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("Select your role")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Als er een opgeslagen verbindingscode is, toon extra informatie
                if signalingClient.hasSavedPairingCode {
                    VStack(spacing: 8) {
                        Text("Er is een opgeslagen verbinding beschikbaar")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        
                        Text("Je kunt direct verbinden met je laatste apparaat")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }

                // ORIGINELE FUNCTIONALITEIT
                Button {
                    navigateTo = .babyMonitor
                } label: {
                    Label("Use as Baby Monitor", systemImage: "mic.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button {
                    navigateTo = .parentUnit
                } label: {
                    Label("Use as Parent Unit", systemImage: "eye.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                // DEBUG/TEST OPTIES
                Button {
                    navigateTo = .audioTest
                } label: {
                    Label("🔧 Test AudioMonitor", systemImage: "waveform")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    navigateTo = .signalingTest
                } label: {
                    Label("🌐 Test SignalingClient", systemImage: "network")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    navigateTo = .socketDebug
                } label: {
                    Label("🔍 Debug Socket.IO", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    navigateTo = .webrtcTest
                } label: {
                    Label("🎵 Test WebRTC Audio", systemImage: "waveform.path")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                Button {
                    navigateTo = .serverDebug
                } label: {
                    Label("🖥️ Debug Server", systemImage: "server.rack")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                // Optie om opgeslagen verbinding te wissen
                if signalingClient.hasSavedPairingCode {
                    Button {
                        signalingClient.clearSavedPairingCode()
                    } label: {
                        Text("Verwijder opgeslagen verbinding")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .padding(.top)
                }

                Spacer()
            }
            .padding()
            .navigationDestination(item: $navigateTo) { role in
                switch role {
                case .babyMonitor:
                    BabyMonitorSetupView(signalingClient: signalingClient)
                case .parentUnit:
                    BabyMonitorViewer(signalingClient: signalingClient)
                case .audioTest:
                    AudioTestView()
                case .signalingTest:
                    SignalingTestView()
                case .socketDebug:
                    SocketDebugView()
                case .webrtcTest:
                    WebRTCAudioTestView()
                case .serverDebug:
                    ServerDebugView()
                }
            }
            .navigationTitle("Baby Monitor")
        }
    }
}
