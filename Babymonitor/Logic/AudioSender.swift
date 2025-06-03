import Foundation
import WebRTC
import AVFoundation

final class AudioSender: NSObject {

    private let factory: RTCPeerConnectionFactory
    private weak var peerConnection: RTCPeerConnection?

    private var audioSource: RTCAudioSource?
    private var audioTrack: RTCAudioTrack?

    // --------------------------------------------------------------------
    // MARK: Init
    // --------------------------------------------------------------------
    init(factory: RTCPeerConnectionFactory,
         peerConnection: RTCPeerConnection) {

        self.factory        = factory
        self.peerConnection = peerConnection
        super.init()

        configureAudioSession()
        requestMicPermissionAndCreateTrack()
    }

    // --------------------------------------------------------------------
    // MARK: Audio-sessie
    // --------------------------------------------------------------------
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord,
                                 mode: .voiceChat,
                                 options: [.allowBluetooth,
                                           .defaultToSpeaker])
        try? session.setActive(true)
    }

    // --------------------------------------------------------------------
    // MARK: Microfoon-toestemming (iOS 17+ compatible)
    // --------------------------------------------------------------------
    private func requestMicPermissionAndCreateTrack() {
        if #available(iOS 17.0, *) {
            // Gebruik nieuwe iOS 17+ API
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                guard granted else {
                    print("AudioSender: Microphone permission denied")
                    return
                }
                print("AudioSender: Microphone permission granted (iOS 17+)")
                self?.createLocalAudioTrack()
            }
        } else {
            // Gebruik oude API voor iOS < 17
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                guard granted else {
                    print("AudioSender: Microphone permission denied")
                    return
                }
                print("AudioSender: Microphone permission granted (iOS < 17)")
                self?.createLocalAudioTrack()
            }
        }
    }

    // --------------------------------------------------------------------
    // MARK: Track-aanmaak
    // --------------------------------------------------------------------
    private func createLocalAudioTrack() {
        print("AudioSender: Creating local audio track...")
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)

        let source = factory.audioSource(with: constraints)
        let track  = factory.audioTrack(with: source,
                                        trackId: "com.babymonitor.audio")

        audioSource = source
        audioTrack  = track

        peerConnection?.add(track, streamIds: ["s0"])
        track.isEnabled = true
        
        print("AudioSender: Local audio track created and added to peer connection")
    }
}
