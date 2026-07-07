import AVFoundation
import Foundation

@MainActor
protocol VoiceProviderProtocol {
    func speak(_ text: String, preferences: VoicePreferences) async throws
    func stop()
}

@MainActor
protocol VoiceServicing {
    func speak(scene: Scene, preferences: VoicePreferences) async throws
    func speak(text: String, preferences: VoicePreferences) async throws
    func stop()
}

@MainActor
struct VoiceService: VoiceServicing {
    var provider: any VoiceProviderProtocol

    func speak(scene: Scene, preferences: VoicePreferences) async throws {
        try await provider.speak(scene.scriptText, preferences: preferences)
    }

    func speak(text: String, preferences: VoicePreferences) async throws {
        try await provider.speak(text, preferences: preferences)
    }

    func stop() {
        provider.stop()
    }
}

@MainActor
final class SystemVoiceProvider: NSObject, VoiceProviderProtocol, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, preferences: VoicePreferences) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            finish()
        }
        let utterance = AVSpeechUtterance(string: spokenText(text, pausesEnabled: preferences.pausesEnabled))
        utterance.rate = Float(0.5 * preferences.speed)
        utterance.pitchMultiplier = Float(preferences.pitch)
        if !preferences.voiceIdentifier.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(identifier: preferences.voiceIdentifier)
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume()
    }

    private func spokenText(_ text: String, pausesEnabled: Bool) -> String {
        guard !pausesEnabled else { return text }
        let punctuation = CharacterSet(charactersIn: ".,;:!?")
        return text.components(separatedBy: punctuation).joined(separator: " ")
    }
}
