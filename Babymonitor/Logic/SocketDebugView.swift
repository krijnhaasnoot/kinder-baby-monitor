//
//  SocketDebugView.swift
//  Babymonitor
//
//  Debug view voor Socket.IO verbindingsproblemen - GECORRIGEERD
//

import SwiftUI
import SocketIO

struct SocketDebugView: View {
    @StateObject private var signalingClient = SignalingClient()
    @State private var debugLogs: [String] = []
    @State private var connectionStatus = "Niet gestart"
    @State private var serverURL = "https://kinder-baby-monitor-production.up.railway.app"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🔍 Socket.IO Debug")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Server URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Server URL:")
                    .font(.headline)
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)
            }
            
            // Status
            VStack(spacing: 8) {
                Text("Verbindingsstatus:")
                    .font(.headline)
                Text(connectionStatus)
                    .font(.subheadline)
                    .foregroundColor(getStatusColor())
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Control buttons
            HStack(spacing: 15) {
                Button(action: testConnection) {
                    Text("Test Verbinding")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                
                Button(action: clearLogs) {
                    Text("Wis Logs")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                }
            }
            
            // Debug logs
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug Logs:")
                    .font(.headline)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(debugLogs.indices, id: \.self) { index in
                            Text(debugLogs[index])
                                .font(.system(size: 10))
                                .foregroundColor(getLogColor(debugLogs[index]))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Socket Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Actions
    private func testConnection() {
        debugLogs.removeAll()
        addLog("🚀 Start verbindingstest naar: \(serverURL)")
        connectionStatus = "Verbinden..."
        
        // Test basis connectiviteit
        testServerReachability()
        
        // Test Socket.IO verbinding
        testSocketIOConnection()
    }
    
    private func testServerReachability() {
        addLog("🌐 Test server bereikbaarheid...")
        
        guard let url = URL(string: serverURL) else {
            addLog("❌ Ongeldige URL: \(serverURL)")
            connectionStatus = "Ongeldige URL"
            return
        }
        
        // Maak een basis HTTP request om te zien of de server bereikbaar is
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.addLog("❌ Server niet bereikbaar: \(error.localizedDescription)")
                    if error.localizedDescription.contains("offline") {
                        self.addLog("💡 Tip: Controleer je internetverbinding")
                    } else if error.localizedDescription.contains("timed out") {
                        self.addLog("💡 Tip: Server reageert niet binnen 10 seconden")
                    }
                } else if let httpResponse = response as? HTTPURLResponse {
                    self.addLog("✅ Server bereikbaar - HTTP Status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode == 200 {
                        self.addLog("✅ Server reageert normaal")
                    } else {
                        self.addLog("⚠️ Server geeft onverwachte status code")
                    }
                } else {
                    self.addLog("⚠️ Onverwacht response type")
                }
            }
        }.resume()
    }
    
    private func testSocketIOConnection() {
        addLog("🔌 Test Socket.IO verbinding...")
        
        guard let url = URL(string: serverURL) else {
            addLog("❌ Kan Socket.IO niet starten - ongeldige URL")
            return
        }
        
        // Maak een tijdelijke socket manager voor test
        let manager = SocketManager(
            socketURL: url,
            config: [
                .log(true),
                .compress,
                .reconnects(true),
                .reconnectAttempts(3),
                .reconnectWait(2),
                .connectParams(["transport": "websocket"])
            ]
        )
        
        let socket = manager.defaultSocket
        
        // Setup event handlers voor debugging
        socket.on(clientEvent: .connect) { data, ack in
            DispatchQueue.main.async {
                self.addLog("✅ Socket.IO verbonden!")
                self.connectionStatus = "Verbonden ✅"
            }
        }
        
        socket.on(clientEvent: .disconnect) { data, ack in
            DispatchQueue.main.async {
                self.addLog("🔌 Socket.IO verbinding verbroken")
                self.connectionStatus = "Verbinding verbroken"
            }
        }
        
        socket.on(clientEvent: .error) { data, ack in
            DispatchQueue.main.async {
                self.addLog("❌ Socket.IO fout: \(data)")
                self.connectionStatus = "Verbindingsfout"
            }
        }
        
        socket.on(clientEvent: .reconnect) { data, ack in
            DispatchQueue.main.async {
                self.addLog("🔄 Socket.IO herverbonden")
            }
        }
        
        socket.on(clientEvent: .reconnectAttempt) { data, ack in
            DispatchQueue.main.async {
                self.addLog("🔄 Socket.IO poging tot herverbinding...")
            }
        }
        
        // Start verbinding
        addLog("🔌 Socket.IO verbinding starten...")
        socket.connect()
        
        // Timeout na 15 seconden
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            if socket.status != .connected {
                self.addLog("⏰ Timeout: Socket.IO verbinding mislukt na 15 seconden")
                self.addLog("📊 Socket status: \(socket.status.description)")
                self.connectionStatus = "Timeout ❌"
                socket.disconnect()
            }
        }
    }
    
    private func clearLogs() {
        debugLogs.removeAll()
        connectionStatus = "Logs gewist"
    }
    
    // MARK: - Helpers
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        debugLogs.append(logEntry)
        print(logEntry) // Ook naar console
    }
    
    private func getStatusColor() -> Color {
        if connectionStatus.contains("✅") {
            return .green
        } else if connectionStatus.contains("❌") || connectionStatus.contains("mislukt") {
            return .red
        } else if connectionStatus.contains("⚠️") {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func getLogColor(_ log: String) -> Color {
        if log.contains("✅") {
            return .green
        } else if log.contains("❌") {
            return .red
        } else if log.contains("⚠️") {
            return .orange
        } else if log.contains("🔌") || log.contains("🌐") {
            return .blue
        } else {
            return .primary
        }
    }
}

// Extension voor SocketIOStatus beschrijving
extension SocketIOStatus {
    var description: String {
        switch self {
        case .notConnected: return "notConnected"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Preview
struct SocketDebugView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SocketDebugView()
        }
    }
}
