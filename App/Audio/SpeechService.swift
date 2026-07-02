import AVFoundation
import Foundation

@MainActor
protocol SpeechService {
    /// An offline en-US voice is present; when false the listening exercise
    /// drops out of the rotation and speak buttons disappear.
    var isAvailable: Bool { get }
    func speak(_ text: String)
    func stop()
}

@MainActor
final class SystemSpeechService: SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")
    private var audioSessionConfigured = false

    var isAvailable: Bool { voice != nil }

    func speak(_ text: String) {
        guard let voice else { return }
        configureAudioSessionIfNeeded()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Playback category so pronunciation is audible with the silent switch
    /// on. Best-effort: a failure here must not disable speech entirely —
    /// the synthesizer still works with the default session.
    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        } catch {
            assertionFailure("Audio session configuration failed: \(error)")
        }
    }
}
