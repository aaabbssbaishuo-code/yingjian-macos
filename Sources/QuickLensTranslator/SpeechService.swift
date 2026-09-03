import AVFoundation
import Foundation

@MainActor
final class SpeechService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    enum State {
        case idle
        case preparing
        case speaking
        case paused
    }

    private enum Backend {
        case system
        case natural
    }

    private struct SpeechItem {
        let text: String
        let paragraphIndex: Int
        let sourceRangeOffset: Int
    }

    private struct WeightedWord {
        let range: NSRange
        let cumulativeWeight: Double
    }

    private struct NaturalSpeechChunk {
        let text: String
        let sourceRange: NSRange
    }

    private struct NaturalTimelineSegment {
        let paragraphIndex: Int
        let sourceRangeOffset: Int
        let playbackStart: TimeInterval
        let duration: TimeInterval
        let words: [WeightedWord]
    }

    private let systemSynthesizer = AVSpeechSynthesizer()
    private let naturalAudioSession: NaturalSpeechAudioSession
    private let naturalPlayer = NaturalSpeechAudioPlayer()
    private let settingsStore: SpeechSettingsStore
    private let voicePackManager: NaturalVoicePackManager
    private var activeBackend: Backend = .system
    private var speechQueue: [SpeechItem] = []
    private var currentQueueIndex = 0
    private var currentUtterance: AVSpeechUtterance?
    private var configuredWordsPerMinute = SpeechSettings.defaultRate
    private var naturalPreparationRequest: NaturalSpeechRequest?
    private var naturalPreparationTask: Task<Void, Never>?
    private var naturalGenerationTask: Task<Void, Never>?
    private var naturalProgressTask: Task<Void, Never>?
    private var naturalTimeline: [NaturalTimelineSegment] = []
    private var pendingAdvanceTask: Task<Void, Never>?
    private var playbackToken = UUID()
    private var isWaitingBetweenItems = false
    private let naturalPrebufferDuration: TimeInterval = 4
    private(set) var state: State = .idle {
        didSet { onStateChanged?(state) }
    }

    var onStateChanged: ((State) -> Void)?
    var onActiveParagraphChanged: ((Int?) -> Void)?
    var onActiveWordRangeChanged: ((Int?, NSRange?) -> Void)?
    var onError: ((String) -> Void)?

    init(
        settingsStore: SpeechSettingsStore,
        voicePackManager: NaturalVoicePackManager,
        naturalAudioSession: NaturalSpeechAudioSession? = nil
    ) {
        self.settingsStore = settingsStore
        self.voicePackManager = voicePackManager
        self.naturalAudioSession = naturalAudioSession ?? NaturalSpeechAudioSession()
        super.init()
        systemSynthesizer.delegate = self
    }

    var isSpeaking: Bool {
        state == .speaking
    }

    var isPreparing: Bool {
        state == .preparing
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

        guard !speechQueue.isEmpty, configureBackend() else {
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
        guard configureBackend() else { return false }
        configuredWordsPerMinute = max(
            SpeechSettings.minimumRate,
            settingsStore.settings.rate - 4
        )
        return startCurrentItem()
    }

    func pause() {
        guard state == .speaking || state == .preparing else { return }

        if isWaitingBetweenItems {
            pendingAdvanceTask?.cancel()
            pendingAdvanceTask = nil
            state = .paused
            return
        }

        switch activeBackend {
        case .system:
            guard systemSynthesizer.pauseSpeaking(at: .word) else { return }
        case .natural:
            naturalPlayer.pause()
        }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }

        if isWaitingBetweenItems {
            isWaitingBetweenItems = false
            state = .speaking
            _ = startCurrentItem()
            return
        }

        switch activeBackend {
        case .system:
            guard systemSynthesizer.continueSpeaking() else { return }
            state = .speaking
        case .natural:
            if naturalPlayer.hasStartedPlayback {
                naturalPlayer.resume()
                state = .speaking
            } else {
                state = .preparing
            }
        }
    }

    func toggle(paragraphs: [String]) -> Bool {
        switch state {
        case .idle:
            return speak(paragraphs: paragraphs)
        case .preparing:
            stop()
            return true
        case .speaking:
            pause()
            return true
        case .paused:
            resume()
            return true
        }
    }

    func stop() {
        playbackToken = UUID()
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        naturalGenerationTask?.cancel()
        naturalGenerationTask = nil
        naturalProgressTask?.cancel()
        naturalProgressTask = nil
        naturalTimeline.removeAll()
        currentUtterance = nil
        isWaitingBetweenItems = false
        speechQueue.removeAll()
        currentQueueIndex = 0
        systemSynthesizer.stopSpeaking(at: .immediate)
        naturalPlayer.stop()
        onActiveParagraphChanged?(nil)
        onActiveWordRangeChanged?(nil, nil)
        state = .idle
    }

    func prepareNaturalVoiceIfNeeded(paragraphs: [String]) {
        guard settingsStore.settings.engine == .natural,
              let files = voicePackManager.modelFiles,
              let firstParagraph = paragraphs.first(where: {
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else { return }
        let trimmedParagraph = firstParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = naturalSpeechChunks(in: trimmedParagraph)
        guard !chunks.isEmpty else { return }

        let settings = settingsStore.settings
        let voice = NaturalVoiceOption.resolve(settings.naturalVoiceIdentifier)
        let wordsPerMinute = configuredRate(for: paragraphs)
        let preparationRequest = NaturalSpeechRequest(
            text: trimmedParagraph,
            files: files,
            voice: voice,
            wordsPerMinute: wordsPerMinute
        )
        guard naturalPreparationRequest != preparationRequest else { return }

        releaseNaturalResources()
        naturalPreparationRequest = preparationRequest
        let requests = naturalRequests(
            for: chunks,
            files: files,
            voice: voice,
            wordsPerMinute: wordsPerMinute
        )
        naturalPreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                var bufferedDuration: TimeInterval = 0
                for (index, request) in requests.enumerated() {
                    try Task.checkCancellation()
                    let generated = try await naturalAudioSession.audio(for: request)
                    try Task.checkCancellation()
                    bufferedDuration += trimmedNaturalAudio(
                        generated,
                        for: chunks[index],
                        index: index,
                        chunkCount: chunks.count
                    ).duration
                    if bufferedDuration >= naturalPrebufferDuration { break }
                }
            } catch {
                // A failed prefetch can be retried when the user requests playback.
            }
        }
    }

    func releaseNaturalResources() {
        naturalPreparationTask?.cancel()
        naturalPreparationTask = nil
        naturalPreparationRequest = nil
        naturalAudioSession.clear()
    }

    private func configureBackend() -> Bool {
        if settingsStore.settings.engine == .natural {
            guard voicePackManager.modelFiles != nil else {
                onError?("自然语音包尚未安装，请先在设置中下载。")
                return false
            }
            activeBackend = .natural
        } else {
            activeBackend = .system
        }
        return true
    }

    private func startCurrentItem() -> Bool {
        guard speechQueue.indices.contains(currentQueueIndex) else { return false }
        isWaitingBetweenItems = false
        let item = speechQueue[currentQueueIndex]

        onActiveParagraphChanged?(item.paragraphIndex)
        onActiveWordRangeChanged?(item.paragraphIndex, nil)

        switch activeBackend {
        case .system:
            state = state == .paused ? .paused : .speaking
            return startSystemItem(item)
        case .natural:
            state = state == .paused ? .paused : .preparing
            return startNaturalItem(item)
        }
    }

    private func startSystemItem(_ item: SpeechItem) -> Bool {
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = resolvedSystemVoice()
        utterance.rate = avSpeechRate(for: configuredWordsPerMinute)
        utterance.pitchMultiplier = 1
        utterance.volume = 1
        currentUtterance = utterance
        systemSynthesizer.speak(utterance)
        return true
    }

    private func startNaturalItem(_ item: SpeechItem) -> Bool {
        guard let files = voicePackManager.modelFiles else { return false }
        let settings = settingsStore.settings
        let voice = NaturalVoiceOption.resolve(settings.naturalVoiceIdentifier)
        let chunks = naturalSpeechChunks(in: item.text)
        guard !chunks.isEmpty else { return false }
        let requests = naturalRequests(
            for: chunks,
            files: files,
            voice: voice,
            wordsPerMinute: configuredWordsPerMinute
        )
        naturalPreparationTask?.cancel()
        naturalPreparationTask = nil
        naturalAudioSession.cancelPending(except: Set(requests))
        let token = UUID()
        playbackToken = token
        naturalTimeline.removeAll()

        naturalPlayer.beginStream(
            startPaused: state == .paused,
            autoplay: false
        ) { [weak self] in
            self?.naturalItemDidFinish(token: token)
        }
        startNaturalWordProgress(token: token)

        naturalGenerationTask?.cancel()
        naturalGenerationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    let generatedAudio = try await naturalAudioSession.audio(for: requests[index])
                    guard !Task.isCancelled, playbackToken == token else { return }
                    let isLastChunk = index == chunks.count - 1
                    let audio = trimmedNaturalAudio(
                        generatedAudio,
                        for: chunk,
                        index: index,
                        chunkCount: chunks.count
                    )
                    let playbackStart = try naturalPlayer.enqueue(audio)
                    naturalTimeline.append(
                        NaturalTimelineSegment(
                            paragraphIndex: item.paragraphIndex,
                            sourceRangeOffset: item.sourceRangeOffset + chunk.sourceRange.location,
                            playbackStart: playbackStart,
                            duration: audio.duration,
                            words: weightedWords(in: chunk.text)
                        )
                    )
                    if !naturalPlayer.hasStartedPlayback,
                       (naturalPlayer.duration >= naturalPrebufferDuration || isLastChunk) {
                        try naturalPlayer.startPlayback()
                        if state == .preparing {
                            state = .speaking
                        }
                    }
                }
                guard !Task.isCancelled, playbackToken == token else { return }
                if !naturalPlayer.hasStartedPlayback {
                    try naturalPlayer.startPlayback()
                    if state == .preparing {
                        state = .speaking
                    }
                }
                naturalPlayer.finishEnqueuing()
            } catch {
                guard !Task.isCancelled, playbackToken == token else { return }
                stop()
                onError?(error.localizedDescription)
            }
        }
        return true
    }

    private func startNaturalWordProgress(token: UUID) {
        naturalProgressTask?.cancel()
        naturalProgressTask = Task { [weak self] in
            guard let self else { return }
            var lastParagraphIndex: Int?
            var lastRange: NSRange?
            while !Task.isCancelled, playbackToken == token {
                if state == .speaking,
                   let segment = naturalTimelineSegment(at: naturalPlayer.currentTime),
                   let totalWeight = segment.words.last?.cumulativeWeight,
                   totalWeight > 0 {
                    let localTime = max(
                        0,
                        naturalPlayer.currentTime - segment.playbackStart + 0.08
                    )
                    let progress = min(0.999, localTime / segment.duration)
                    let targetWeight = progress * totalWeight
                    if let word = segment.words.first(where: { $0.cumulativeWeight >= targetWeight }) {
                        let sourceRange = NSRange(
                            location: segment.sourceRangeOffset + word.range.location,
                            length: word.range.length
                        )
                        if lastParagraphIndex != segment.paragraphIndex || lastRange != sourceRange {
                            lastParagraphIndex = segment.paragraphIndex
                            lastRange = sourceRange
                            onActiveWordRangeChanged?(segment.paragraphIndex, sourceRange)
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }

    private func naturalItemDidFinish(token: UUID) {
        guard playbackToken == token else { return }
        naturalProgressTask?.cancel()
        naturalProgressTask = nil
        naturalGenerationTask = nil
        naturalTimeline.removeAll()
        advanceToNextItem()
    }

    private func advanceToNextItem() {
        currentQueueIndex += 1
        guard currentQueueIndex < speechQueue.count else {
            speechQueue.removeAll()
            naturalTimeline.removeAll()
            onActiveParagraphChanged?(nil)
            onActiveWordRangeChanged?(nil, nil)
            state = .idle
            return
        }

        isWaitingBetweenItems = true
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled,
                  let self,
                  self.state != .paused else { return }
            self.isWaitingBetweenItems = false
            _ = self.startCurrentItem()
        }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        guard activeBackend == .system,
              utterance === currentUtterance else { return }
        currentUtterance = nil
        advanceToNextItem()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        guard activeBackend == .system,
              utterance === currentUtterance else { return }
        stop()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        guard activeBackend == .system,
              utterance === currentUtterance,
              speechQueue.indices.contains(currentQueueIndex) else { return }
        let item = speechQueue[currentQueueIndex]
        let sourceRange = NSRange(
            location: item.sourceRangeOffset + characterRange.location,
            length: characterRange.length
        )
        onActiveWordRangeChanged?(item.paragraphIndex, sourceRange)
    }

    private func configureRate(for paragraphs: [String]) {
        configuredWordsPerMinute = configuredRate(for: paragraphs)
    }

    private func configuredRate(for paragraphs: [String]) -> Float {
        let preferredRate = settingsStore.settings.rate
        let totalCharacters = paragraphs.reduce(0) { $0 + $1.count }
        let paragraphPenalty = min(max(0, paragraphs.count - 1), 5)
        let lengthPenalty = min(totalCharacters / 300, 5)
        return max(
            SpeechSettings.minimumRate,
            preferredRate - Float(paragraphPenalty + lengthPenalty)
        )
    }

    private func resolvedSystemVoice() -> AVSpeechSynthesisVoice? {
        guard let identifier = EnglishVoiceCatalog.resolvedVoiceIdentifier(
            for: settingsStore.settings.voiceIdentifier
        ) else { return AVSpeechSynthesisVoice(language: "en-US") }
        return AVSpeechSynthesisVoice(identifier: identifier)
    }

    private func avSpeechRate(for wordsPerMinute: Float) -> Float {
        let clampedRate = min(
            max(wordsPerMinute, SpeechSettings.minimumRate),
            SpeechSettings.maximumRate
        )
        let progress = (clampedRate - SpeechSettings.minimumRate)
            / (SpeechSettings.maximumRate - SpeechSettings.minimumRate)
        return 0.36 + progress * 0.14
    }

    private func weightedWords(in text: String) -> [WeightedWord] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            ranges.append(NSRange(range, in: text))
        }

        let nsText = text as NSString
        var words: [WeightedWord] = []
        var cumulativeWeight = 0.0
        for (index, range) in ranges.enumerated() {
            let word = nsText.substring(with: range)
            let syllables = estimatedSyllableCount(in: word)
            let nextLocation = index + 1 < ranges.count
                ? ranges[index + 1].location
                : nsText.length
            let trailingLength = max(0, nextLocation - NSMaxRange(range))
            let trailingText = trailingLength > 0
                ? nsText.substring(
                    with: NSRange(location: NSMaxRange(range), length: trailingLength)
                )
                : ""
            let punctuationWeight: Double
            if trailingText.contains(where: { ".!?".contains($0) }) {
                punctuationWeight = 0.8
            } else if trailingText.contains(where: { ",;:".contains($0) }) {
                punctuationWeight = 0.38
            } else {
                punctuationWeight = 0
            }
            cumulativeWeight += 0.72 + Double(syllables) * 0.38 + punctuationWeight
            words.append(
                WeightedWord(range: range, cumulativeWeight: cumulativeWeight)
            )
        }
        return words
    }

    private func naturalTimelineSegment(at playbackTime: TimeInterval) -> NaturalTimelineSegment? {
        if let activeSegment = naturalTimeline.first(where: { segment in
            playbackTime >= segment.playbackStart
                && playbackTime < segment.playbackStart + segment.duration
        }) {
            return activeSegment
        }
        return naturalTimeline.last(where: { $0.playbackStart <= playbackTime })
    }

    private func naturalRequests(
        for chunks: [NaturalSpeechChunk],
        files: NaturalVoiceModelFiles,
        voice: NaturalVoiceOption,
        wordsPerMinute: Float
    ) -> [NaturalSpeechRequest] {
        chunks.enumerated().map { index, chunk in
            NaturalSpeechRequest(
                text: naturalSynthesisText(for: chunk, needsContinuation: index < chunks.count - 1),
                files: files,
                voice: voice,
                wordsPerMinute: wordsPerMinute
            )
        }
    }

    private func trimmedNaturalAudio(
        _ audio: NaturalSpeechAudio,
        for chunk: NaturalSpeechChunk,
        index: Int,
        chunkCount: Int
    ) -> NaturalSpeechAudio {
        audio.trimmingSilence(
            leadingPadding: index == 0 ? 0.06 : 0.025,
            trailingPadding: naturalTrailingPadding(
                for: chunk.text,
                isLastChunk: index == chunkCount - 1
            )
        )
    }

    private func estimatedSyllableCount(in word: String) -> Int {
        let letters = word.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return 1 }

        let vowels = CharacterSet(charactersIn: "aeiouy")
        var count = 0
        var previousWasVowel = false
        for scalar in letters.unicodeScalars {
            let isVowel = vowels.contains(scalar)
            if isVowel, !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }
        if letters.count > 2, letters.hasSuffix("e"), count > 1 {
            count -= 1
        }
        return max(1, count)
    }

    private func naturalTrailingPadding(
        for text: String,
        isLastChunk: Bool
    ) -> TimeInterval {
        guard !isLastChunk else { return 0.16 }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).last {
        case ".", "!", "?":
            return 0.16
        case ",", ";", ":":
            return 0.1
        default:
            return 0.045
        }
    }

    private func naturalSynthesisText(
        for chunk: NaturalSpeechChunk,
        needsContinuation: Bool
    ) -> String {
        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needsContinuation,
              let lastCharacter = text.last,
              !".,;:!?".contains(lastCharacter) else { return text }
        return text + ","
    }

    private func naturalSpeechChunks(in text: String) -> [NaturalSpeechChunk] {
        var wordRanges: [NSRange] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            wordRanges.append(NSRange(range, in: text))
        }
        guard !wordRanges.isEmpty else { return [] }

        let nsText = text as NSString
        var chunks: [NaturalSpeechChunk] = []
        var wordIndex = 0
        var isFirstChunk = true

        while wordIndex < wordRanges.count {
            let targetWordCount = isFirstChunk ? 4 : 8
            let targetEndWordIndex = min(wordIndex + targetWordCount, wordRanges.count)
            let endWordIndex = preferredChunkEndWordIndex(
                from: wordIndex,
                target: targetEndWordIndex,
                wordRanges: wordRanges,
                text: nsText
            )
            let startLocation = wordRanges[wordIndex].location
            let endLocation = endWordIndex < wordRanges.count
                ? wordRanges[endWordIndex].location
                : nsText.length
            let rawRange = NSRange(
                location: startLocation,
                length: max(0, endLocation - startLocation)
            )
            let rawText = nsText.substring(with: rawRange) as NSString
            let contentCharacters = CharacterSet.whitespacesAndNewlines.inverted
            let firstContent = rawText.rangeOfCharacter(from: contentCharacters)
            let lastContent = rawText.rangeOfCharacter(
                from: contentCharacters,
                options: .backwards
            )

            if firstContent.location != NSNotFound, lastContent.location != NSNotFound {
                let sourceRange = NSRange(
                    location: rawRange.location + firstContent.location,
                    length: lastContent.location - firstContent.location + lastContent.length
                )
                chunks.append(
                    NaturalSpeechChunk(
                        text: nsText.substring(with: sourceRange),
                        sourceRange: sourceRange
                    )
                )
            }

            wordIndex = endWordIndex
            isFirstChunk = false
        }
        return chunks
    }

    private func preferredChunkEndWordIndex(
        from startWordIndex: Int,
        target targetWordIndex: Int,
        wordRanges: [NSRange],
        text: NSString
    ) -> Int {
        guard targetWordIndex < wordRanges.count else { return wordRanges.count }

        let minimumEnd = max(startWordIndex + 2, targetWordIndex - 2)
        let maximumEnd = min(wordRanges.count, targetWordIndex + 2)
        var bestEnd: Int?
        var bestScore = Int.max

        for candidateEnd in minimumEnd...maximumEnd {
            let previousWordEnd = NSMaxRange(wordRanges[candidateEnd - 1])
            let nextWordStart = candidateEnd < wordRanges.count
                ? wordRanges[candidateEnd].location
                : text.length
            guard nextWordStart > previousWordEnd else { continue }
            let separator = text.substring(
                with: NSRange(
                    location: previousWordEnd,
                    length: nextWordStart - previousWordEnd
                )
            )

            let punctuationScore: Int
            if separator.contains(where: { ".!?".contains($0) }) {
                punctuationScore = 0
            } else if separator.contains(where: { ",;:".contains($0) }) {
                punctuationScore = 3
            } else {
                continue
            }

            let score = punctuationScore + abs(candidateEnd - targetWordIndex)
            if score < bestScore {
                bestScore = score
                bestEnd = candidateEnd
            }
        }
        return bestEnd ?? targetWordIndex
    }
}
