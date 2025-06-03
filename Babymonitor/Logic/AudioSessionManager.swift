//
//  AudioSessionManager.swift
//  Babymonitor
//
//  Gecentraliseerde audio sessie management om conflicten te voorkomen
//

import Foundation
import AVFoundation

/// Singleton klasse om alle AVAudioSession configuratie te centraliseren
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private let session = AVAudioSession.sharedInstance()
    private var isConfigured = false
    private var currentMode: AudioMode = .inactive
    
    enum AudioMode {
        case inactive
        case monitoring    // Voor baby unit (opname)
        case listening     // Voor parent unit (afspelen)
        case testing       // Voor audio tests
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    func configureForMonitoring() throws {
        print("🔧 AudioSessionManager: Configureren voor monitoring (baby unit)")
        try configureSession(for: .monitoring)
    }
    
    func configureForListening() throws {
        print("🔧 AudioSessionManager: Configureren voor listening (parent unit)")
        try configureSession(for: .listening)
    }
    
    func configureForTesting() throws {
        print("🔧 AudioSessionManager: Configureren voor testen")
        try configureSession(for: .testing)
    }
    
    func deactivate() throws {
        print("🔧 AudioSessionManager: Deactiveren audio sessie")
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        isConfigured = false
        currentMode = .inactive
    }
    
    func checkPermissions() -> Bool {
        if #available(iOS 17.0, *) {
            // Correctie: Gebruik de specifieke recordPermission op AVAudioApplication
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return session.recordPermission == .granted
        }
    }
    
    func requestPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                // Correctie: Gebruik de specifieke requestRecordPermission op AVAudioApplication
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func configureSession(for mode: AudioMode) throws {
        if isConfigured && currentMode == mode {
            print("✅ AudioSessionManager: Al geconfigureerd voor \(mode)")
            return
        }
        
        if isConfigured {
            print("🔄 AudioSessionManager: Deactiveren huidige sessie voor nieuwe configuratie")
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        switch mode {
        case .inactive:
            return
            
        case .monitoring:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            
        case .listening:
            try session.setCategory(
                .playback,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            
        case .testing:
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker]
            )
        }
        
        try session.setActive(true)
        
        isConfigured = true
        currentMode = mode
        
        logCurrentConfiguration()
        
        print("✅ AudioSessionManager: Succesvol geconfigureerd voor \(mode)")
    }
    
    private func logCurrentConfiguration() {
        print("📊 AudioSessionManager huidige configuratie:")
        print("   - Category: \(session.category.rawValue)")
        print("   - Mode: \(session.mode.rawValue)")
        print("   - Options: \(session.categoryOptions)")
        print("   - Sample Rate: \(session.sampleRate)")
        print("   - Input Channels: \(session.inputNumberOfChannels)")
        print("   - Output Channels: \(session.outputNumberOfChannels)")
        
        if let route = session.currentRoute.inputs.first {
            print("   - Input: \(route.portName) (\(route.portType.rawValue))")
        }
        if let route = session.currentRoute.outputs.first {
            print("   - Output: \(route.portName) (\(route.portType.rawValue))")
        }
    }
}

// MARK: - Error Helper
extension AudioSessionManager {
    static func errorDescription(for status: OSStatus) -> String {
        switch status {
        case 560030580: return "AVAudioSessionErrorCodeCannotInterruptOthers"
        case 561017449: return "AVAudioSessionErrorCodeCannotStartPlaying"
        case 561145203: return "AVAudioSessionErrorCodeCannotStartRecording"
        case 561210739: return "AVAudioSessionErrorCodeBadParam"
        case 1768843636: return "AVAudioSessionErrorCodeIncompatibleCategory"
        default: return "Unknown AVAudioSession error: \(status)"
        }
    }
}
