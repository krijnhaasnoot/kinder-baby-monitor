//
//  ServerDebugView.swift
//  Babymonitor
//
//  Test wat de server precies doet - COMPLETE VERSIE MET MULTI-SERVER TEST
//

import SwiftUI
import SocketIO

struct ServerDebugView: View {
    @State private var serverStatus = "Niet getest"
    @State private var debugLogs: [String] = []
    @State private var socket: SocketIOClient?
    @State private var generatedCode: String = ""
    @State private var testCode: String = ""
    @State private var serverURL = "https://kinder-baby-monitor-production.up.railway.app"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🖥️ Server Debug Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Status: \(serverStatus)")
                .font(.headline)
                .foregroundColor(serverStatus.contains("✅") ? .green : .red)
            
            // Server URL configuratie
            VStack(alignment: .leading, spacing: 8) {
                Text("Server URL:")
                    .font(.headline)
                
                HStack {
                    Button("Jouw Server") {
                        serverURL = "https://kinder-baby-monitor-production.up.railway.app"
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Test Server") {
                        serverURL = "https://socket-io-chat.now.sh"
                    }
                    .buttonStyle(.bordered)
                }
                
                TextField("Server URL", text: $serverURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            VStack(spacing: 15) {
                Button("Test Server Basis") {
                    testServerBasics()
                }
                .buttonStyle(DebugButtonStyle(color: .blue))
                
                Button("Test Socket.IO Events") {
                    testSocketIOEvents()
                }
                .buttonStyle(DebugButtonStyle(color: .orange))
                
                // NIEUWE MULTI-SERVER TEST
                Button("Test Alle Servers") {
                    testMultipleServers()
                }
                .buttonStyle(DebugButtonStyle(color: .red))
                
                if !generatedCode.isEmpty {
                    VStack {
                        Text("Generated Code: \(generatedCode)")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        TextField("Test met deze code", text: $testCode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Test Code Join") {
                            testCodeJoin()
                        }
                        .buttonStyle(DebugButtonStyle(color: .green))
                    }
                }
                
                Button("Test SDP Exchange") {
                    testSDPExchange()
                }
                .buttonStyle(DebugButtonStyle(color: .purple))
                
                Button("Clear Logs") {
                    debugLogs.removeAll()
                }
                .buttonStyle(DebugButtonStyle(color: .gray))
            }
            
            // Debug logs
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
            .frame(maxHeight: 300)
            .padding(8)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Server Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Private Functions (Correctly placed outside of 'body')
    
    private func testServerBasics() {
        addLog("🧪 Test server: \(serverURL)")
        serverStatus = "Testen..."
        
        // HTTP test
        guard let url = URL(string: serverURL) else {
            addLog("❌ Invalid URL: \(serverURL)")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.addLog("❌ HTTP Error: \(error.localizedDescription)")
                    self.serverStatus = "HTTP Failed ❌"
                } else if let httpResponse = response as? HTTPURLResponse {
                    self.addLog("✅ HTTP Status: \(httpResponse.statusCode)")
                    if let data = data {
                        self.addLog("📄 Response size: \(data.count) bytes")
                        if let responseString = String(data: data, encoding: .utf8) {
                            self.addLog("📄 Response: \(responseString.prefix(100))...")
                        }
                    }
                    self.serverStatus = "HTTP OK ✅"
                    
                    // Nu Socket.IO testen
                    self.testSocketIOConnection()
                }
            }
        }.resume()
    }
    
    private func testSocketIOConnection() {
        addLog("🔌 Test Socket.IO verbinding naar: \(serverURL)")
        
        guard let url = URL(string: serverURL) else { return }
        
        let manager = SocketManager(socketURL: url, config: [.log(false), .compress])
        socket = manager.defaultSocket
        
        // Event handlers
        socket?.on(clientEvent: .connect) { data, ack in
            DispatchQueue.main.async {
                self.addLog("✅ Socket.IO verbonden")
                self.serverStatus = "Socket.IO Connected ✅"
            }
        }
        
        socket?.on(clientEvent: .disconnect) { data, ack in
            DispatchQueue.main.async {
                self.addLog("🔌 Socket.IO verbinding verbroken")
            }
        }
        
        socket?.on(clientEvent: .error) { data, ack in
            DispatchQueue.main.async {
                self.addLog("❌ Socket.IO error: \(data)")
                self.serverStatus = "Socket.IO Error ❌"
            }
        }
        
        socket?.connect()
        
        // Timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.socket?.status != .connected {
                self.addLog("⏰ Socket.IO timeout")
                self.serverStatus = "Socket.IO Timeout ❌"
            }
        }
    }
    
    // NIEUWE MULTI-SERVER TEST FUNCTIE
    private func testMultipleServers() {
        addLog("🧪 Testing multiple Socket.IO servers...")
        debugLogs.removeAll() // Start fresh
        
        let testServers = [
            ("Jouw Railway", "https://kinder-baby-monitor-production.up.railway.app"),
            ("Socket.IO Chat", "https://socket-io-chat.now.sh"),
            ("Socket.IO Demo", "https://admin.socket.io")
        ]
        
        for (index, server) in testServers.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index * 4)) {
                self.testSingleServer(server.0, url: server.1, index: index + 1)
            }
        }
    }
    
    private func testSingleServer(_ name: String, url urlString: String, index: Int) {
        addLog("🎯 Test \(index): \(name)")
        addLog("   URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            addLog("❌ Test \(index): Invalid URL")
            return
        }
        
        let manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .reconnects(false)  // Geen reconnect voor test
        ])
        let testSocket = manager.defaultSocket
        
        var connected = false
        var hasError = false
        
        testSocket.on(clientEvent: .connect) { data, ack in
            connected = true
            DispatchQueue.main.async {
                self.addLog("✅ Test \(index): SUCCESS - \(name) CONNECTED!")
                if index == 1 {
                    self.serverStatus = "\(name): Connected ✅"
                }
            }
            
            // Test basic functionality
            testSocket.emit("ping", ["test": "data"])
            
            // Disconnect after success
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                testSocket.disconnect()
            }
        }
        
        testSocket.on(clientEvent: .error) { data, ack in
            hasError = true
            DispatchQueue.main.async {
                self.addLog("❌ Test \(index): ERROR - \(name)")
                self.addLog("   Error: \(data)")
                if index == 1 {
                    self.serverStatus = "\(name): Error ❌"
                }
            }
        }
        
        testSocket.on(clientEvent: .disconnect) { data, ack in
            DispatchQueue.main.async {
                self.addLog("🔌 Test \(index): \(name) disconnected")
            }
        }
        
        addLog("🚀 Test \(index): Connecting to \(name)...")
        testSocket.connect()
        
        // Timeout na 12 seconden
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            if !connected && !hasError {
                self.addLog("⏰ Test \(index): TIMEOUT - \(name)")
                if index == 1 {
                    self.serverStatus = "\(name): Timeout ❌"
                }
                testSocket.disconnect()
            }
        }
    }
    
    private func testSocketIOEvents() {
        addLog("📡 Test Socket.IO events...")
        
        guard let socket = socket, socket.status == .connected else {
            addLog("❌ Socket niet verbonden")
            return
        }
        
        // Test generateCode
        addLog("📤 Sending generateCode...")
        
        socket.on("codeGenerated") { data, ack in
            DispatchQueue.main.async {
                if let code = data[0] as? String {
                    self.addLog("✅ Code ontvangen: \(code)")
                    self.generatedCode = code
                    self.testCode = code
                } else {
                    self.addLog("❌ Invalid code response: \(data)")
                }
            }
        }
        
        socket.emit("generateCode")
    }
    
    private func testCodeJoin() {
        guard !testCode.isEmpty else { return }
        
        addLog("🔗 Test joinWithCode: \(testCode)")
        
        socket?.on("pairingSuccess") { data, ack in
            DispatchQueue.main.async {
                self.addLog("✅ Pairing success ontvangen")
            }
        }
        
        socket?.on("viewerJoined") { data, ack in
            DispatchQueue.main.async {
                self.addLog("✅ Viewer joined ontvangen")
            }
        }
        
        socket?.emit("joinWithCode", testCode)
    }
    
    private func testSDPExchange() {
        addLog("🤝 Test SDP exchange...")
        
        guard !generatedCode.isEmpty else {
            addLog("❌ Geen code beschikbaar")
            return
        }
        
        // Luister naar SDP events
        socket?.on("offer") { data, ack in
            DispatchQueue.main.async {
                self.addLog("📥 Offer ontvangen: \(data)")
            }
        }
        
        socket?.on("answer") { data, ack in
            DispatchQueue.main.async {
                self.addLog("📥 Answer ontvangen: \(data)")
            }
        }
        
        socket?.on("candidate") { data, ack in
            DispatchQueue.main.async {
                self.addLog("📥 ICE candidate ontvangen: \(data)")
            }
        }
        
        // Verstuur test SDP
        let testSDP: [String: Any] = [
            "type": "offer",
            "sdp": "v=0\r\no=- 123456789 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
        ]
        
        addLog("📤 Sending test offer...")
        socket?.emit("offer", generatedCode, testSDP)
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        debugLogs.append(logEntry)
        print(logEntry)
        
        if debugLogs.count > 100 {
            debugLogs.removeFirst()
        }
    }
}

// MARK: - Button Style
struct DebugButtonStyle: ButtonStyle {
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
struct ServerDebugView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ServerDebugView()
        }
    }
}
