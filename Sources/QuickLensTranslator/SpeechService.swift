import AppKit

@MainActor
final class SpeechService: NSObject, NSSpeechSynthesizerDelegate {
    enum State {
        case idle
        case speaking
        case paused
    }

    private let synthesizer = NSSpeechSynthesizer()
    private var paragraphQueue: [String] = []
    private var currentParagraphIndex = 0
    private var pendingAdvanceTask: Task<Void, Never>?
    private(set) var state: State = .idle {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?
    var onActiveParagraphChanged: ((Int?) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self

        if let voice = NSSpeechSynthesizer.availableVoices.first(where: {
            $0.rawValue.localizedCaseInsensitiveContains("en")
        }) {
            synthesizer.setVoice(voice)
        }
        synthesizer.rate = 175
        synthesizer.volume = 1.0
    }

    var isSpeaking: Bool {
        state == .speaking
    }

    var isPaused: Bool {
        state == .paused
    }

    func speak(paragraphs: [String]) -> Bool {
        stop()

        paragraphQueue = paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        currentParagraphIndex = 0

        guard !paragraphQueue.isEmpty else {
            return false
        }

        configureRate(for: paragraphQueue)
        return startCurrentParagraph()
    }

    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: NSSpeechSynthesizer.Boundary.wordBoundary)
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .speaking
    }

    func toggle(paragraphs: [String]) -> Bool {
        switch state {
        case .idle:
            return speak(paragraphs: paragraphs)
        case .speaking:
            pause()
            return true
        case .paused:
            resume()
            return true
        }
    }

    func stop() {
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        paragraphQueue.removeAll()
        currentParagraphIndex = 0
        synthesizer.stopSpeaking()
        onActiveParagraphChanged?(nil)
        state = .idle
    }

    func speechSynthesizer(
        _ sender: NSSpeechSynthesizer,
        didFinishSpeaking finishedSpeaking: Bool
    ) {
        guard finishedSpeaking else {
            stop()
            return
        }

        currentParagraphIndex += 1
        guard currentParagraphIndex < paragraphQueue.count else {
            paragraphQueue.removeAll()
            onActiveParagraphChanged?(nil)
            state = .idle
            return
        }

        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.state != .paused else { return }
                _ = self.startCurrentParagraph()
            }
        }
    }

    private func startCurrentParagraph() -> Bool {
        guard currentParagraphIndex < paragraphQueue.count else { return false }
        let started = synthesizer.startSpeaking(paragraphQueue[currentParagraphIndex])
        if started {
            onActiveParagraphChanged?(currentParagraphIndex)
            state = .speaking
        } else {
            stop()
        }
        return started
    }

    private func configureRate(for paragraphs: [String]) {
        let totalCharacters = paragraphs.reduce(0) { $0 + $1.count }
        let paragraphPenalty = max(0, paragraphs.count - 1) * 3
        let lengthPenalty = min(totalCharacters / 250, 20)
        synthesizer.rate = Float(max(150, 182 - paragraphPenalty - lengthPenalty))
    }
}
