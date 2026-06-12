import AppKit

@MainActor
final class SpeechService: NSObject, NSSpeechSynthesizerDelegate {
    private let synthesizer = NSSpeechSynthesizer()
    var onSpeakingChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        if let voice = NSSpeechSynthesizer.availableVoices.first(where: {
            $0.rawValue.localizedCaseInsensitiveContains("en")
        }) {
            synthesizer.setVoice(voice)
        }
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    func speak(_ text: String) -> Bool {
        synthesizer.stopSpeaking()
        let started = synthesizer.startSpeaking(text)
        onSpeakingChanged?(started)
        return started
    }

    func stop() {
        synthesizer.stopSpeaking()
        onSpeakingChanged?(false)
    }

    func speechSynthesizer(
        _ sender: NSSpeechSynthesizer,
        didFinishSpeaking finishedSpeaking: Bool
    ) {
        onSpeakingChanged?(false)
    }
}
