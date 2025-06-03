//
//  AudioTestView.swift
//  Babymonitor
//
//  Test view voor de AudioMonitor klasse
//

import SwiftUI
import AVFoundation

struct AudioTestView: View {
    @State private var statusText = "Nog niet gestart"
    @State private var decibelValue: Float = 0.0
    @State private var isMonitoring = false
    @State private var audioMonitor: AudioMonitor?
    @State private var permissionStatus = "Controleren..."
    
    var body: some View {
        VStack(spacing: 30) {
            Text("🎤 AudioMonitor Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Permissie status
            VStack(spacing: 8) {
                Text("Microfoon Permissie:")
                    .font(.headline)
                Text(permissionStatus)
                    .font(.subheadline)
                    .foregroundColor(permissionStatus.contains("OK") ? .green : .red)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Status
            Text(statusText)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
            
            // Decibel waarde - groot en opvallend
            Text("\(String(format: "%.1f", decibelValue)) dB")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(colorForDecibel(decibelValue))
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(15)
            
            // Geluidsniveau indicator
            HStack {
                Text("Stil")
                    .font(.caption)
                Rectangle()
                    .fill(gradientForDecibel())
                    .frame(height: 20)
                    .cornerRadius(10)
                Text("Luid")
                    .font(.caption)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Control buttons
            HStack(spacing: 20) {
                Button(action: startTest) {
                    Text("Start Test")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMonitoring ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(isMonitoring)
                
                Button(action: stopTest) {
                    Text("Stop Test")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isMonitoring ? Color.red : Color.gray)
                        .cornerRadius(12)
                }
                .disabled(!isMonitoring)
            }
            .padding(.horizontal)
            
            // Instructies
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 Instructies:")
                    .font(.headline)
                Text("1. Druk op 'Start Test'")
                Text("2. Praat, klap of zet muziek aan")
                Text("3. Kijk of de dB waarde verandert")
                Text("4. Kijk naar de console output")
            }
            .font(.caption)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
        }
        .padding()
        .onAppear {
            checkMicrophonePermission()
        }
        .navigationTitle("Audio Test")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Permissie controle
    private func checkMicrophonePermission() {
        print("🎤 Controleer microfoon permissies...")
        
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                permissionStatus = "OK (iOS 17+)"
                print("✅ Microfoon permissie: Toegestaan (iOS 17+)")
            case .denied:
                permissionStatus = "GEWEIGERD"
                print("❌ Microfoon permissie: Geweigerd (iOS 17+)")
                requestPermission()
            case .undetermined:
                permissionStatus = "Nog niet gevraagd"
                print("⚠️ Microfoon permissie: Nog niet gevraagd (iOS 17+)")
                requestPermission()
            @unknown default:
                permissionStatus = "Onbekend"
                print("❓ Microfoon permissie: Onbekende status (iOS 17+)")
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                permissionStatus = "OK (iOS < 17)"
                print("✅ Microfoon permissie: Toegestaan (iOS < 17)")
            case .denied:
                permissionStatus = "GEWEIGERD"
                print("❌ Microfoon permissie: Geweigerd (iOS < 17)")
                requestPermission()
            case .undetermined:
                permissionStatus = "Nog niet gevraagd"
                print("⚠️ Microfoon permissie: Nog niet gevraagd (iOS < 17)")
                requestPermission()
            @unknown default:
                permissionStatus = "Onbekend"
                print("❓ Microfoon permissie: Onbekende status (iOS < 17)")
            }
        }
    }
    
    private func requestPermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        permissionStatus = "Verkregen (iOS 17+)"
                        print("✅ Microfoon permissie verkregen (iOS 17+)")
                    } else {
                        permissionStatus = "GEWEIGERD door gebruiker"
                        print("❌ Microfoon permissie geweigerd door gebruiker (iOS 17+)")
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        permissionStatus = "Verkregen (iOS < 17)"
                        print("✅ Microfoon permissie verkregen (iOS < 17)")
                    } else {
                        permissionStatus = "GEWEIGERD door gebruiker"
                        print("❌ Microfoon permissie geweigerd door gebruiker (iOS < 17)")
                    }
                }
            }
        }
    }
    
    // MARK: - Test functies
    private func startTest() {
        print("🎵 Start AudioMonitor test...")
        
        // Controleer permissies
        let hasPermission: Bool
        if #available(iOS 17.0, *) {
            hasPermission = AVAudioApplication.shared.recordPermission == .granted
        } else {
            hasPermission = AVAudioSession.sharedInstance().recordPermission == .granted
        }
        
        guard hasPermission else {
            print("❌ Geen microfoon permissie")
            statusText = "Geen microfoon permissie!"
            return
        }
        
        // Maak nieuwe AudioMonitor instantie (jouw bestaande klasse)
        let monitor = AudioMonitor()
        
        // Zet callback voor dB updates
        monitor.onLevel = { [self] decibels in
            print("🔊 AudioMonitor callback: \(decibels) dB")
            
            DispatchQueue.main.async {
                self.decibelValue = decibels
            }
        }
        
        // Start monitoring
        monitor.start()
        audioMonitor = monitor
        
        // Update UI
        isMonitoring = true
        statusText = "AudioMonitor actief - Maak geluid!"
        
        print("✅ AudioMonitor test gestart")
    }
    
    private func stopTest() {
        print("🛑 Stop AudioMonitor test")
        
        audioMonitor?.stop()
        audioMonitor = nil
        
        isMonitoring = false
        statusText = "AudioMonitor gestopt"
        decibelValue = 0.0
        
        print("🛑 AudioMonitor test gestopt")
    }
    
    // MARK: - UI helpers
    private func colorForDecibel(_ db: Float) -> Color {
        if db > -40 {
            return .red     // Zeer luid
        } else if db > -60 {
            return .orange  // Gemiddeld
        } else if db > -80 {
            return .green   // Zacht
        } else {
            return .gray    // Stil
        }
    }
    
    private func gradientForDecibel() -> LinearGradient {
        LinearGradient(
            colors: [.gray, .green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Preview
struct AudioTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AudioTestView()
        }
    }
}
