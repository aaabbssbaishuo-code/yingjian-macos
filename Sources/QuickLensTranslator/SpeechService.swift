import AppKit

@MainActor
final class SpeechService: NSObject, NSSpeechSynthesizerDelegate {
    enum State {
        case idle
        case speaking
        case paused
    }

    private struct SpeechItem {
        let text: String
        let paragraphIndex: Int
        let sourceRangeOffset: Int
    }

    private let synthesizer = NSSpeechSynthesizer()
    private var speechQueue: [SpeechItem] = []
    private var currentQueueIndex = 0
    private var pendingAdvanceTask: Task<Void, Never>?
    private(set) var state: State = .idle {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?
    var onActiveParagraphChanged: ((Int?) -> Void)?
    var onActiveWordRangeChanged: ((Int?, NSRange?) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self

        if let voice = Self.preferredEnglishVoice() {
            synthesizer.setVoice(voice)
        }
        synthesizer.rate = 140
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

        speechQueue = paragraphs.enumerated().compactMap { index, paragraph in
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SpeechItem(text: text, paragraphIndex: index, sourceRangeOffset: 0)
        }
        currentQueueIndex = 0

        guard !speechQueue.isEmpty else {
            return false
        }

        configureRate(for: speechQueue.map(\.text))
        return startCurrentItem()
    }

    func speakWord(_ word: String, paragraphIndex: Int, sourceRange: NSRange) -> Bool {
        stop()

        let text = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        speechQueue = [
            SpeechItem(
                text: text,
                paragraphIndex: paragraphIndex,
                sourceRangeOffset: sourceRange.location
            )
        ]
        currentQueueIndex = 0
        synthesizer.rate = 134
        return startCurrentItem()
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
        speechQueue.removeAll()
        currentQueueIndex = 0
        synthesizer.stopSpeaking()
        onActiveParagraphChanged?(nil)
        onActiveWordRangeChanged?(nil, nil)
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

        currentQueueIndex += 1
        guard currentQueueIndex < speechQueue.count else {
            speechQueue.removeAll()
            onActiveParagraphChanged?(nil)
            onActiveWordRangeChanged?(nil, nil)
            state = .idle
            return
        }

        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.state != .paused else { return }
                _ = self.startCurrentItem()
            }
        }
    }

    private func startCurrentItem() -> Bool {
        guard speechQueue.indices.contains(currentQueueIndex) else { return false }
        let item = speechQueue[currentQueueIndex]
        let started = synthesizer.startSpeaking(item.text)
        if started {
            onActiveParagraphChanged?(item.paragraphIndex)
            onActiveWordRangeChanged?(item.paragraphIndex, nil)
            state = .speaking
        } else {
            stop()
        }
        return started
    }

    func speechSynthesizer(
        _ sender: NSSpeechSynthesizer,
        willSpeakWord characterRange: NSRange,
        of string: String
    ) {
        guard speechQueue.indices.contains(currentQueueIndex) else { return }
        let item = speechQueue[currentQueueIndex]
        let sourceRange = NSRange(
            location: item.sourceRangeOffset + characterRange.location,
            length: characterRange.length
        )
        onActiveWordRangeChanged?(item.paragraphIndex, sourceRange)
    }

    private func configureRate(for paragraphs: [String]) {
        let totalCharacters = paragraphs.reduce(0) { $0 + $1.count }
        let paragraphPenalty = max(0, paragraphs.count - 1) * 2
        let lengthPenalty = min(totalCharacters / 220, 14)
        synthesizer.rate = Float(max(130, 146 - paragraphPenalty - lengthPenalty))
    }

    private static func preferredEnglishVoice() -> NSSpeechSynthesizer.VoiceName? {
        let availableVoices = NSSpeechSynthesizer.availableVoices
        let preferredNames = [
            "Samantha",
            "Ava",
            "Nicky",
            "Zoe",
            "Susan",
            "Allison",
            "Tom",
            "Daniel"
        ]

        for name in preferredNames {
            if let voice = availableVoices.first(where: { voice in
                let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
                let voiceName = attributes[.name] as? String
                let locale = attributes[.localeIdentifier] as? String

                return locale?.replacingOccurrences(of: "_", with: "-") == "en-US"
                    && voiceName?.localizedCaseInsensitiveContains(name) == true
            }) {
                return voice
            }
        }

        return availableVoices.first(where: { voice in
            let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
            let locale = attributes[.localeIdentifier] as? String
            let voiceName = attributes[.name] as? String ?? ""
            let identifier = voice.rawValue.lowercased()

            guard locale?.lowercased().hasPrefix("en") == true else {
                return false
            }

            return !identifier.contains("speech.synthesis.voice")
                && !voiceName.localizedCaseInsensitiveContains("Eddy")
                && !voiceName.localizedCaseInsensitiveContains("Flo")
                && !voiceName.localizedCaseInsensitiveContains("Grand")
                && !voiceName.localizedCaseInsensitiveContains("Reed")
                && !voiceName.localizedCaseInsensitiveContains("Rocko")
                && !voiceName.localizedCaseInsensitiveContains("Sandy")
                && !voiceName.localizedCaseInsensitiveContains("Shelley")
        })
    }
}
