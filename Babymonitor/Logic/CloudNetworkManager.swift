//
//  CloudNetworkManager.swift
//  Babymonitor
//
//  Updated: 27-05-2025 (Met TURN server integratie en verbeterde logging)
//

import Foundation
import WebRTC
import AVFoundation

// MARK: - Delegate
protocol CloudNetworkManagerDelegate: AnyObject {
    func cloudNetworkManager(_ manager: CloudNetworkManager,
                             didChangeIceState state: RTCIceConnectionState)
}

// MARK: - Klasse
final class CloudNetworkManager: NSObject, ObservableObject {

    // MARK: - Public Properties
    weak var delegate: CloudNetworkManagerDelegate?
    var onRemoteAudioLevel: ((Float) -> Void)?
    var onRemoteTrack: ((RTCAudioTrack) -> Void)?

    // MARK: - Private Properties
    private let factory = RTCPeerConnectionFactory()
    private var pc: RTCPeerConnection?
    private let signaling: SignalingClient

    private var isMonitor = false
    private var localAudioTrack: RTCAudioTrack?
    private var audioLevelMonitor: AudioMonitor?
    
    private var remoteAudioTrack: RTCAudioTrack? // Bijhouden van de remote track

    // ------------------------------------------------------------------
    // MARK: - Initialization
    // ------------------------------------------------------------------
    init(signalingClient: SignalingClient) {
        self.signaling = signalingClient
        super.init()
        
        configureSignalingCallbacks()
        print("CloudNetworkManager initialized.")
    }
    
    deinit {
        print("CloudNetworkManager deinit: Deactivating AVAudioSession...")
        do {
            try AudioSessionManager.shared.deactivate() // Gebruik de AudioSessionManager
            print("✅ CloudNetworkManager deinit: AVAudioSession gedeactiveerd")
        } catch {
            print("❌ CloudNetworkManager deinit: Kon AVAudioSession niet deactiveren: \(error.localizedDescription)")
        }
        pc?.close() // Sluit de peer connection af
        pc = nil
        print("CloudNetworkManager deinit: PeerConnection gesloten.")
    }

    // ------------------------------------------------------------------
    // MARK: - Role Management (Monitor/Viewer)
    // ------------------------------------------------------------------
    func startAsMonitor() {
        print("Starting as Monitor (Baby Unit)...")
        isMonitor = true
        do {
            try AudioSessionManager.shared.configureForMonitoring()
        } catch {
            print("ERROR: Failed to configure AVAudioSession for Monitor: \(error.localizedDescription)")
            return
        }
        createPeerConnectionIfNeeded()
        attachMicrophone()
        createAndSendOffer()
        startLocalAudioLevelMonitor()
    }

    func startAsViewer() {
        print("Starting as Viewer (Parent Unit)...")
        isMonitor = false
        do {
            try AudioSessionManager.shared.configureForListening()
        } catch {
            print("ERROR: Failed to configure AVAudioSession for Viewer: \(error.localizedDescription)")
            return
        }
        createPeerConnectionIfNeeded()
        // Viewer wacht op offer
    }

    // ------------------------------------------------------------------
    // MARK: - Signaling Callbacks
    // ------------------------------------------------------------------
    private func configureSignalingCallbacks() {
        signaling.onOffer = { [weak self] sdp in
            print("Signaling: Received Offer SDP (type: \(sdp.type.stringValue)).")
            print("SDP Content:\n\(sdp.sdp)") // Full SDP logging
            self?.handleRemoteSDP(sdp)
        }
        
        signaling.onAnswer = { [weak self] sdp in
            print("Signaling: Received Answer SDP (type: \(sdp.type.stringValue)).")
            print("SDP Content:\n\(sdp.sdp)") // Full SDP logging
            self?.handleRemoteSDP(sdp)
        }
        
        signaling.onCandidate = { [weak self] cand in
            print("Signaling: Received ICE Candidate: mid=\(cand.sdpMid ?? "nil"), index=\(cand.sdpMLineIndex)")
            print("Candidate SDP: \(cand.sdp)") // Full candidate SDP logging
            
            guard let self = self else { return }
            
            if #available(iOS 17.0, *) {
                self.pc?.add(cand) { error in
                    if let error = error {
                        print("ERROR: Failed to add ICE candidate: \(error.localizedDescription)")
                    } else {
                        print("ICE candidate added successfully")
                    }
                }
            } else {
                self.pc?.add(cand)
                print("ICE candidate added (pre-iOS 17)")
            }
        }
        
        signaling.enableAudioLevelListener()
        
        signaling.onRemoteAudioLevel = { [weak self] db in
            print("Remote audio level received: \(db) dB")
            self?.onRemoteAudioLevel?(db)
        }
        
        print("Signaling callbacks configured.")
    }

    // ------------------------------------------------------------------
    // MARK: - Peer Connection Management
    // ------------------------------------------------------------------
    private func createPeerConnectionIfNeeded() {
        guard pc == nil else {
            print("PeerConnection already exists. Skipping creation.")
            return
        }

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        
        // ICE parameters aanpassen voor robuustheid
        config.iceTransportPolicy = .all // Try all transports (UDP/TCP)
        config.bundlePolicy = .maxBundle // Bundle multiple media types into one RTP port
        config.rtcpMuxPolicy = .require // Require RTCP multiplexing
        config.tcpCandidatePolicy = .enabled // Allow TCP candidates
        config.candidateNetworkPolicy = .all // Use all available network interfaces

        // Jouw DigitalOcean TURN server credentials
        let turnServerIP = "165.232.87.137"
        let turnUsername = "babymonitor_user"
        let turnPassword = "K1nd3r Babymonitor"

        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]), // Extra STUN server
            RTCIceServer(urlStrings: ["turn:\(turnServerIP):3478"], // Hoofd TURN poort (UDP)
                         username: turnUsername,
                         credential: turnPassword),
            RTCIceServer(urlStrings: ["turn:\(turnServerIP):5349?transport=tcp"], // TURN over TCP (TLS)
                         username: turnUsername,
                         credential: turnPassword)
        ]
        
        print("RTCConfiguration ICE Servers set: \(config.iceServers.map { $0.urlStrings.joined(separator: ", ") })")
        print("WAARSCHUWING: TURN servers zijn geconfigureerd. Voor pure localhost (zelfde Wi-Fi) kun je de TURN-regels uitcommentariëren in de code als je daar test.")

        // Media constraints aanpassen
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true", // De monitor verwacht dat de viewer mogelijk audio ontvangt
                "OfferToReceiveVideo": "false" // Geen video
            ],
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true" // Belangrijk voor veiligheid
            ]
        )

        pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        print("RTCPeerConnection created. Role: \(isMonitor ? "Monitor" : "Viewer").")

        // voeg audio-transceiver toe
        let audioTransceiverInit = RTCRtpTransceiverInit()
        audioTransceiverInit.direction = isMonitor ? .sendOnly : .recvOnly
        _ = pc?.addTransceiver(of: .audio, init: audioTransceiverInit)
        
        // Correctie: Gebruik String(describing:) voor het loggen van de enum
        print("Audio Transceiver added with initial direction: \(String(describing: audioTransceiverInit.direction)).")

        // Log all transceivers after creation
        pc?.transceivers.forEach { transceiver in
            // Correctie: Gebruik .rawValue voor RTCRtpMediaType
            // Correctie: Gebruik String(describing:) voor RTCRtpTransceiverDirection
            print("  Transceiver state: mediaType=\(transceiver.mediaType.rawValue), direction=\(String(describing: transceiver.direction)), mid=\(transceiver.mid ?? "nil"), currentDirection=\(String(describing: transceiver.currentDirection)), stopped=\(transceiver.isStopped)")
        }
    }

    // ------------------------------------------------------------------
    // MARK: - Local Microphone Track (Baby Unit)
    // ------------------------------------------------------------------
    private func attachMicrophone() {
        guard isMonitor, localAudioTrack == nil, let peerConnection = pc else {
            if !isMonitor { print("Microphone attachment skipped: Not in Monitor role.") }
            if localAudioTrack != nil { print("Microphone attachment skipped: Local audio track already exists.") }
            if pc == nil { print("Microphone attachment skipped: PeerConnection not initialized.") }
            return
        }

        // Constraints voor de audio source (bijv. echo cancellation uitzetten)
        let audioSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "googEchoCancellation": "false",
                "googAutoGainControl": "false",
                "googNoiseSuppression": "false",
                "googHighpassFilter": "false"
            ],
            optionalConstraints: nil
        )
        
        let audioSource = factory.audioSource(with: audioSourceConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "mic0")
        audioTrack.isEnabled = true
        peerConnection.add(audioTrack, streamIds: ["s0"])
        localAudioTrack = audioTrack
        print("Local microphone track 'mic0' attached to PeerConnection. Enabled: \(audioTrack.isEnabled)")
    }

    // ------------------------------------------------------------------
    // MARK: - Local dB Meter (Baby Unit)
    // ------------------------------------------------------------------
    private func startLocalAudioLevelMonitor() {
        guard isMonitor else { return }
        let meter = AudioMonitor()
        meter.onLevel = { [weak self] db in
            guard let self = self else { return }
            print("Local audio level: \(db) dB (from AudioMonitor)")
            self.signaling.postLocalAudioLevel(db)
        }
        meter.start()
        audioLevelMonitor = meter
        print("Local AudioMonitor started to send dB levels.")
    }

    // ------------------------------------------------------------------
    // MARK: - SDP Offer / Answer Mechanism
    // ------------------------------------------------------------------
    private func createAndSendOffer() {
        guard let peerConnection = pc else {
            print("ERROR: PeerConnection not initialized, cannot create offer.")
            return
        }

        // Constraints voor offer/answer
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true", // De monitor verwacht dat de viewer mogelijk audio ontvangt
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self = self else { return }
            
            if let error = error {
                print("ERROR: Failed to create offer: \(error.localizedDescription)")
                return
            }
            
            guard let sessionDescription = sdp else {
                print("ERROR: Created Offer SDP is nil.")
                return
            }
            
            print("Successfully created Offer SDP (type: \(sessionDescription.type.stringValue)).")
            print("SDP Content:\n\(sessionDescription.sdp)") // Full SDP logging

            peerConnection.setLocalDescription(sessionDescription) { error in
                if let error = error {
                    print("ERROR: Failed to set local description (offer): \(error.localizedDescription)")
                    return
                }
                
                print("Local description (offer) set successfully. Sending offer via signaling.")
                self.signaling.sendOffer(sessionDescription)
            }
        }
    }

    private func createAndSendAnswer() {
        guard let peerConnection = pc else {
            print("ERROR: PeerConnection not initialized, cannot create answer.")
            return
        }

        // Constraints voor answer
        let answerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true", // De viewer is voor ontvangst, maar het antwoord kan ook 'sendonly' bevatten
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection.answer(for: answerConstraints) { [weak self] sdp, error in
            guard let self = self else { return }
            
            if let error = error {
                print("ERROR: Failed to create answer: \(error.localizedDescription)")
                return
            }
            
            guard let sessionDescription = sdp else {
                print("ERROR: Created Answer SDP is nil.")
                return
            }
            
            print("Successfully created Answer SDP (type: \(sessionDescription.type.stringValue)).")
            print("SDP Content:\n\(sessionDescription.sdp)") // Full SDP logging

            peerConnection.setLocalDescription(sessionDescription) { error in
                if let error = error {
                    print("ERROR: Failed to set local description (answer): \(error.localizedDescription)")
                    return
                }
                
                print("Local description (answer) set successfully. Sending answer via signaling.")
                self.signaling.sendAnswer(sessionDescription)
            }
        }
    }

    private func handleRemoteSDP(_ sdp: RTCSessionDescription) {
        print("Handling remote SDP (type: \(sdp.type.stringValue)).")
        createPeerConnectionIfNeeded()
        
        // Pas de SDP aan voor betere audio werking (optioneel, maar kan helpen bij specifieke problemen)
        var modifiedSdpString = sdp.sdp
        
        // Forceer stereo audio uit (WebRTC werkt vaak beter met mono voor stem)
        // Zoek naar m=audio sectie en verwijder stereo=1 als aanwezig
        modifiedSdpString = modifiedSdpString.replacingOccurrences(
            of: "a=fmtp:111 SPROP-stereo=1;stereo=1",
            with: "a=fmtp:111 stereo=0" // Dit is een voorbeeld, kan specifiek zijn voor codecs
        )
        modifiedSdpString = modifiedSdpString.replacingOccurrences(
            of: "stereo=1",
            with: "stereo=0"
        )
        
        // Zorg dat audio niet onbedoeld wordt uitgeschakeld ('a=inactive' kan in de verkeerde context staan)
        modifiedSdpString = modifiedSdpString.replacingOccurrences(
            of: "a=inactive", // Als de remote SDP dit bevat, kan het audio uitschakelen
            with: "a=sendrecv" // Forceer naar sendrecv als basis (wordt overschreven door transceiver richting)
        )
        
        let modifiedSDP = RTCSessionDescription(type: sdp.type, sdp: modifiedSdpString)

        pc?.setRemoteDescription(modifiedSDP) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("ERROR: Failed to set remote description: \(error.localizedDescription)")
                return
            }
            
            print("Remote description (type: \(modifiedSDP.type.stringValue)) set successfully.")
            
            if !self.isMonitor && modifiedSDP.type == .offer {
                print("Viewer received offer, creating and sending answer.")
                self.createAndSendAnswer()
            }
        }
    }
}

// --------------------------------------------------------------------
// MARK: - RTCPeerConnectionDelegate Extension
// --------------------------------------------------------------------
extension CloudNetworkManager: RTCPeerConnectionDelegate {

    func peerConnection(_ pc: RTCPeerConnection,
                        didChange newState: RTCIceConnectionState) {
        print("RTCPeerConnectionDelegate: ICE Connection State changed to: \(newState.rawValue)")
        delegate?.cloudNetworkManager(self, didChangeIceState: newState)
        
        // Verwerk verbindingsstatus
        switch newState {
        case .connected, .completed:
            print("ICE Connected! Audio should now be flowing.")
            
            // Voor de viewer-kant: forceer audio naar luidspreker (kan hier of na didAdd receiver)
            if !isMonitor {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.overrideOutputAudioPort(.speaker)
                    print("✅ Audio geforceerd naar luidspreker na ICE verbinding")
                } catch {
                    print("⚠️ Kon audio niet naar luidspreker routeren: \(error.localizedDescription)")
                }
            }
                        
        case .failed:
            print("ICE Connection Failed! Attempting ICE restart...")
            // Correctie: Verwijder pc.restartIce() hier, of voeg meer complexe logica toe.
            // Dit is vaak niet wenselijk als directe actie op 'failed', maar via een retry-mechanisme.
            // pc.restartIce()
            
        case .disconnected:
            print("ICE Disconnected. Media may have stopped.")

        case .checking:
            print("ICE is checking connectivity...")
            
        case .new:
            print("ICE is in new state, starting gathering...")
            
        default:
            break
        }
        
        // Log transceivers bij elke ICE state change voor debugging
        pc.transceivers.forEach { transceiver in
            // Correctie: Gebruik .rawValue voor RTCRtpMediaType
            // Correctie: Gebruik String(describing:) voor RTCRtpTransceiverDirection
            print("  Transceiver state: mediaType=\(transceiver.mediaType.rawValue), direction=\(String(describing: transceiver.direction)), mid=\(transceiver.mid ?? "nil"), currentDirection=\(String(describing: transceiver.currentDirection)), stopped=\(transceiver.isStopped)")
        }
    }

    func peerConnection(_ pc: RTCPeerConnection,
                        didGenerate candidate: RTCIceCandidate) {
        print("RTCPeerConnectionDelegate: Generated ICE Candidate: mid=\(candidate.sdpMid ?? "nil"), index=\(candidate.sdpMLineIndex).")
        print("Candidate SDP: \(candidate.sdp)") // Full candidate SDP logging
        signaling.sendCandidate(candidate)
    }

    func peerConnection(_ pc: RTCPeerConnection,
                        didAdd receiver: RTCRtpReceiver,
                        streams: [RTCMediaStream]) {
        // Correctie: Gebruik receiver.track?.kind ?? "unknown" voor mediaType
        print("RTCPeerConnectionDelegate: Did add receiver. Type: \(receiver.track?.kind ?? "unknown").")

        if let audioTrack = receiver.track as? RTCAudioTrack {
            print("Remote audio track received! Track ID: \(audioTrack.trackId)")
            
            // 1. Zorg ervoor dat de track is ingeschakeld
            audioTrack.isEnabled = true
            print("Setting remote track enabled: \(audioTrack.isEnabled)")
            
            // 2. Bewaar een sterke referentie om te voorkomen dat de track wordt opgeruimd door ARC
            self.remoteAudioTrack = audioTrack
            
            // 3. Informeer de delegate/callback
            if let callback = self.onRemoteTrack {
                callback(audioTrack)
            }
            
            print("Audio should now be playing through the system's output.")
            
            // Controleer AVAudioSession status en forceer naar luidspreker (dubbele check)
            let session = AVAudioSession.sharedInstance()
            print("Current AVAudioSession after track reception: category=\(session.category.rawValue), mode=\(session.mode.rawValue)")
            
            if !isMonitor { // Alleen voor de viewer-kant
                do {
                    try session.overrideOutputAudioPort(.speaker)
                    print("✅ Audio geforceerd naar luidspreker na track ontvangst (dubbele check)")
                } catch {
                    print("⚠️ Kon audio niet naar luidspreker routeren na track ontvangst: \(error.localizedDescription)")
                }
            }
        } else {
            // Correctie: Gebruik receiver.track?.kind ?? "unknown" voor mediaType
            print("Received a track that is not an RTCAudioTrack or track is nil (mediaType: \(receiver.track?.kind ?? "unknown")).")
        }
        
        streams.forEach { stream in
            print("Associated Stream ID: \(stream.streamId)")
        }
    }

    // MARK: - Unused Delegate Stubs (for completeness, with logging)
    func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("RTCPeerConnectionDelegate: Signaling State changed to: \(stateChanged.rawValue).")
    }
    
    func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("RTCPeerConnectionDelegate: Did add media stream: \(stream.streamId).")
    }
    
    func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("RTCPeerConnectionDelegate: Did remove media stream: \(stream.streamId).")
    }
    
    func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {
        print("RTCPeerConnectionDelegate: Peer connection should negotiate.")
    }
    
    func peerConnection(_ pc: RTCPeerConnection,
                        didChange newState: RTCIceGatheringState) {
        print("RTCPeerConnectionDelegate: ICE Gathering State changed to: \(newState.rawValue).")
    }
    
    func peerConnection(_ pc: RTCPeerConnection,
                        didRemove candidates: [RTCIceCandidate]) {
        print("RTCPeerConnectionDelegate: Did remove ICE candidates.")
    }
    func peerConnection(_ pc: RTCPeerConnection,
                        didOpen dataChannel: RTCDataChannel) {
        print("RTCPeerConnectionDelegate: Did open data channel: \(dataChannel.label).")
    }
}
