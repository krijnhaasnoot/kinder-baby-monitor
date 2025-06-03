import Foundation
import AVFoundation

/// Meet continu het geluidsniveau van de microfoon (baby-zijde).
final class AudioMonitor {

    // Publieke callbacks
    var onLevel: ((Float) -> Void)?          // dB-waarde (-90…0)
    weak var delegate: AudioMonitorDelegate?

    private let engine = AVAudioEngine()
    private var isRunning = false
    private var timer: Timer?
    private var debugCounter = 0

    // --------------------------------------------------------------------
    // MARK: – Control
    // --------------------------------------------------------------------
    func start() {
        guard !isRunning else {
            print("AudioMonitor: Al actief, start overgeslagen")
            return
        }
        
        print("AudioMonitor: Starting monitoring...")
        
        do {
            try AudioSessionManager.shared.configureForMonitoring()
            
            guard AudioSessionManager.shared.checkPermissions() else {
                print("❌ AudioMonitor: Geen microfoon permissie. Vraag permissies aan of handel af.")
                return
            }
            
            addTap()
            try engine.start()
            isRunning = true
            
            startRegularUpdates()
            
            print("✅ AudioMonitor: Monitoring successfully started")
        } catch let error as NSError {
            let statusCode = error.code
            let description = AudioSessionManager.errorDescription(for: OSStatus(statusCode))
            print("❌ AudioMonitor ERROR: \(description)")
            print("❌ AudioMonitor ERROR details: \(error.localizedDescription)")
            
            attemptRecovery()
        }
    }

    func stop() {
        guard isRunning else {
            print("AudioMonitor: Al gestopt, stop overgeslagen")
            return
        }
        
        print("AudioMonitor: Stopping monitoring...")
        stopRegularUpdates()
        
        if engine.isRunning {
            engine.stop()
        }
        
        // Specifieke controle voor tap, indien inputNode beschikbaar
        // Als isTapInstalled() niet bestaat, is deze check onnodig of moet robuuster
        if engine.inputNode.numberOfInputs > 0 && engine.inputNode.isTapInstalled(onBus: 0) {
             engine.inputNode.removeTap(onBus: 0)
             print("AudioMonitor: Tap op bus 0 verwijderd.")
        } else if engine.inputNode.numberOfInputs > 0 {
             // Als isTapInstalled() niet beschikbaar is, probeer dan direct te verwijderen.
             // Dit kan een crash veroorzaken als er geen tap is, maar is nodig zonder de check.
             // Meer robuuste code zou bijhouden of er een tap is geïnstalleerd met een bool.
             engine.inputNode.removeTap(onBus: 0)
             print("AudioMonitor: Tap op bus 0 verwijderd (geen isTapInstalled check).")
        }

        isRunning = false
        print("✅ AudioMonitor: Monitoring stopped")
    }
    
    deinit {
        print("AudioMonitor: Deinitializing...")
        stop()
    }

    // --------------------------------------------------------------------
    // MARK: – Recovery
    // --------------------------------------------------------------------
    private func attemptRecovery() {
        print("🔄 AudioMonitor: Attempting recovery...")
        
        if engine.isRunning {
            engine.stop()
        }
        
        Thread.sleep(forTimeInterval: 0.5)
        
        do {
            try AudioSessionManager.shared.configureForMonitoring()
            Thread.sleep(forTimeInterval: 0.2)
            
            addTap()
            try engine.start()
            isRunning = true
            startRegularUpdates()
            
            print("✅ AudioMonitor: Recovery successful")
        } catch {
            print("❌ AudioMonitor: Recovery failed: \(error.localizedDescription)")
        }
    }

    // --------------------------------------------------------------------
    // MARK: – Regular Updates
    // --------------------------------------------------------------------
    private func startRegularUpdates() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            if self?.isRunning == true {
                // Keep the timer running for consistent updates
            }
        }
    }
    
    private func stopRegularUpdates() {
        timer?.invalidate()
        timer = nil
    }

    // --------------------------------------------------------------------
    // MARK: – Tap
    // --------------------------------------------------------------------
    private func addTap() {
        let input  = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        print("AudioMonitor: Installing tap with format:")
        print("   - Sample rate: \(format.sampleRate)")
        print("   - Channels: \(format.channelCount)")
        print("   - Format: \(format)")

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            guard
                let self,
                let ch = buf.floatChannelData?.pointee
            else {
                print("⚠️ AudioMonitor: No audio data in buffer (or cannot access)")
                return
            }

            let frames = Int(buf.frameLength)
            guard frames > 0 else {
                return
            }
            
            var sum: Float = 0.0
            for i in 0..<frames {
                let sample = ch[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frames))
            
            let db = 20 * log10(max(rms, 0.0000001))
            
            let normalizedDb = max(min(db, 0), -90)
            
            self.debugCounter += 1
            if self.debugCounter % 20 == 0 {
                print("🔊 AudioMonitor: Level \(String(format: "%.1f", normalizedDb)) dB (raw: \(String(format: "%.1f", db)), rms: \(String(format: "%.6f", rms)))")
            }

            DispatchQueue.main.async {
                self.onLevel?(normalizedDb)
                self.delegate?.audioMonitor(self, didUpdate: normalizedDb)
            }
        }
        
        print("✅ AudioMonitor: Tap installed successfully")
    }
}

// optional delegate
protocol AudioMonitorDelegate: AnyObject {
    func audioMonitor(_ monitor: AudioMonitor, didUpdate avgPower: Float)
}
