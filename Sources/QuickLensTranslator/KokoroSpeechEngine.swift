import AVFoundation
import Combine
import Foundation
import SherpaOnnx

struct NaturalSpeechAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }

    func trimmingSilence(
        leadingPadding: TimeInterval,
        trailingPadding: TimeInterval
    ) -> NaturalSpeechAudio {
        guard !samples.isEmpty, sampleRate > 0 else { return self }

        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        let threshold = max(0.0025, peak * 0.018)
        guard let firstAudible = samples.firstIndex(where: { abs($0) >= threshold }),
              let lastAudible = samples.lastIndex(where: { abs($0) >= threshold }) else {
            return self
        }

        let leadingFrames = Int(max(0, leadingPadding) * sampleRate)
        let trailingFrames = Int(max(0, trailingPadding) * sampleRate)
        let lowerBound = max(0, firstAudible - leadingFrames)
        let upperBound = min(samples.count, lastAudible + trailingFrames + 1)
        guard lowerBound < upperBound else { return self }

        return NaturalSpeechAudio(
            samples: Array(samples[lowerBound..<upperBound]),
            sampleRate: sampleRate
        )
    }
}

enum KokoroSpeechError: LocalizedError {
    case voicePackUnavailable
    case engineInitializationFailed
    case generationFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .voicePackUnavailable:
            return "自然语音包尚未安装。"
        case .engineInitializationFailed:
            return "自然语音引擎初始化失败。"
        case .generationFailed:
            return "自然语音生成失败。"
        case .playbackFailed:
            return "自然语音播放失败。"
        }
    }
}

actor KokoroSpeechSynthesizer {
    static let shared = KokoroSpeechSynthesizer()

    private var engine: SherpaOnnxOfflineTtsWrapper?
    private var loadedModelPath: String?
    private var idleUnloadTask: Task<Void, Never>?
    private var idleToken = UUID()

    private func keepWarmAfterUse() {
        idleUnloadTask?.cancel()
        let token = UUID()
        idleToken = token
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(90))
            } catch {
                return
            }
            await self?.unloadIfIdle(token: token)
        }
    }

    private func unloadIfIdle(token: UUID) {
        guard idleToken == token else { return }
        unload()
    }

    func prepare(files: NaturalVoiceModelFiles) throws {
        try Task.checkCancellation()
        defer { keepWarmAfterUse() }
        _ = try loadEngineIfNeeded(files: files)
    }

    func synthesize(
        text: String,
        files: NaturalVoiceModelFiles,
        voice: NaturalVoiceOption,
        wordsPerMinute: Float
    ) async throws -> NaturalSpeechAudio {
        try Task.checkCancellation()
        defer { keepWarmAfterUse() }
        let engine = try loadEngineIfNeeded(files: files)
        try Task.checkCancellation()
        let audio = engine.generate(
            text: text,
            sid: voice.speakerID,
            speed: speedMultiplier(for: wordsPerMinute)
        )
        try Task.checkCancellation()
        let samples = audio.samples
        guard !samples.isEmpty, audio.sampleRate > 0 else {
            throw KokoroSpeechError.generationFailed
        }
        return NaturalSpeechAudio(
            samples: samples,
            sampleRate: Double(audio.sampleRate)
        )
    }

    func unload() {
        idleToken = UUID()
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        engine = nil
        loadedModelPath = nil
    }

    private func loadEngineIfNeeded(
        files: NaturalVoiceModelFiles
    ) throws -> SherpaOnnxOfflineTtsWrapper {
        if let engine, loadedModelPath == files.model.path {
            return engine
        }

        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: files.model.path,
            voices: files.voices.path,
            tokens: files.tokens.path,
            dataDir: files.dataDirectory.path,
            dictDir: files.dictionaryDirectory?.path ?? "",
            lexicon: files.lexicon.path,
            lang: "en-us"
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoroConfig,
            numThreads: max(4, min(ProcessInfo.processInfo.activeProcessorCount, 12)),
            provider: "cpu"
        )
        var config = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            maxNumSentences: 1,
            silenceScale: 0.2
        )
        let wrapper = withUnsafePointer(to: &config) {
            SherpaOnnxOfflineTtsWrapper(config: $0)
        }
        guard wrapper.tts != nil else {
            throw KokoroSpeechError.engineInitializationFailed
        }
        engine = wrapper
        loadedModelPath = files.model.path
        return wrapper
    }

    private func speedMultiplier(for wordsPerMinute: Float) -> Float {
        let clamped = min(
            max(wordsPerMinute, SpeechSettings.minimumRate),
            SpeechSettings.maximumRate
        )
        let progress = (clamped - SpeechSettings.minimumRate)
            / (SpeechSettings.maximumRate - SpeechSettings.minimumRate)
        return 0.76 + progress * 0.34
    }
}

@MainActor
final class NaturalSpeechAudioPlayer {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playbackToken = UUID()
    private var streamCompletion: (() -> Void)?
    private var pendingBufferCount = 0
    private var hasFinishedEnqueuing = false
    private(set) var hasStartedPlayback = false
    private var shouldAutoplay = true
    private var streamIsPaused = false
    private var streamSampleRate: Double?
    private(set) var duration: TimeInterval = 0

    init() {
        audioEngine.attach(playerNode)
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    var currentTime: TimeInterval {
        guard let renderTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: renderTime),
              playerTime.sampleRate > 0 else { return 0 }
        return max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
    }

    func beginStream(
        startPaused: Bool = false,
        autoplay: Bool = true,
        completion: @escaping () -> Void
    ) {
        stop()
        streamCompletion = completion
        streamIsPaused = startPaused
        shouldAutoplay = autoplay
    }

    @discardableResult
    func enqueue(_ audio: NaturalSpeechAudio) throws -> TimeInterval {
        guard streamCompletion != nil else {
            throw KokoroSpeechError.playbackFailed
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audio.sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audio.samples.count)
        ),
        let channelData = buffer.floatChannelData?.pointee else {
            throw KokoroSpeechError.playbackFailed
        }

        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        audio.samples.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return }
            channelData.update(from: baseAddress, count: samples.count)
        }

        if streamSampleRate == nil {
            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            streamSampleRate = audio.sampleRate
        } else if streamSampleRate != audio.sampleRate {
            throw KokoroSpeechError.playbackFailed
        }

        if !audioEngine.isRunning {
            do {
                audioEngine.prepare()
                try audioEngine.start()
            } catch {
                throw KokoroSpeechError.playbackFailed
            }
        }

        let startTime = duration
        duration += audio.duration
        pendingBufferCount += 1
        let token = playbackToken
        playerNode.scheduleBuffer(
            buffer,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackToken == token else { return }
                self.bufferDidFinish()
            }
        }

        if !hasStartedPlayback, shouldAutoplay {
            try startPlayback()
        } else if !streamIsPaused, !playerNode.isPlaying {
            if hasStartedPlayback {
                playerNode.play()
            }
        }
        return startTime
    }

    func startPlayback() throws {
        guard !hasStartedPlayback, pendingBufferCount > 0 else { return }
        guard audioEngine.isRunning else {
            throw KokoroSpeechError.playbackFailed
        }
        hasStartedPlayback = true
        playerNode.play()
        guard playerNode.isPlaying else {
            hasStartedPlayback = false
            throw KokoroSpeechError.playbackFailed
        }
        if streamIsPaused {
            playerNode.pause()
        }
    }

    func finishEnqueuing() {
        hasFinishedEnqueuing = true
        finishStreamIfNeeded()
    }

    func pause() {
        streamIsPaused = true
        if hasStartedPlayback {
            playerNode.pause()
        }
    }

    func resume() {
        streamIsPaused = false
        guard hasStartedPlayback else { return }
        guard !playerNode.isPlaying else { return }
        playerNode.play()
    }

    func stop() {
        playbackToken = UUID()
        playerNode.stop()
        audioEngine.stop()
        audioEngine.reset()
        streamCompletion = nil
        pendingBufferCount = 0
        hasFinishedEnqueuing = false
        hasStartedPlayback = false
        shouldAutoplay = true
        streamIsPaused = false
        streamSampleRate = nil
        duration = 0
    }

    private func bufferDidFinish() {
        pendingBufferCount = max(0, pendingBufferCount - 1)
        finishStreamIfNeeded()
    }

    private func finishStreamIfNeeded() {
        guard hasFinishedEnqueuing, pendingBufferCount == 0 else { return }
        let completion = streamCompletion
        streamCompletion = nil
        completion?()
    }
}

@MainActor
final class NaturalSpeechPreviewController: ObservableObject {
    enum State {
        case idle
        case preparing
        case speaking
    }

    @Published private(set) var state: State = .idle
    private let audioSession = NaturalSpeechAudioSession()
    private let player = NaturalSpeechAudioPlayer()
    private var task: Task<Void, Never>?
    private var currentRequest: NaturalSpeechRequest?
    private var playbackToken = UUID()

    func prepare(_ request: NaturalSpeechRequest) async {
        if currentRequest != request {
            stop()
            currentRequest = request
            audioSession.cancelPending(except: [request])
        }
        _ = try? await audioSession.audio(for: request)
    }

    func speak(
        text: String,
        files: NaturalVoiceModelFiles,
        voice: NaturalVoiceOption,
        wordsPerMinute: Float,
        onError: @escaping (String) -> Void
    ) {
        stop()
        let request = NaturalSpeechRequest(
            text: text,
            files: files,
            voice: voice,
            wordsPerMinute: wordsPerMinute
        )
        currentRequest = request
        audioSession.cancelPending(except: [request])
        let token = playbackToken
        state = .preparing
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await audioSession.audio(for: request)
                guard !Task.isCancelled, playbackToken == token else { return }
                player.beginStream { [weak self] in
                    guard let self, self.playbackToken == token else { return }
                    self.state = .idle
                }
                try player.enqueue(audio)
                state = .speaking
                player.finishEnqueuing()
            } catch {
                guard !Task.isCancelled, playbackToken == token else { return }
                stop()
                onError(error.localizedDescription)
            }
        }
    }

    func stop() {
        playbackToken = UUID()
        task?.cancel()
        task = nil
        player.stop()
        state = .idle
    }

    func clear() {
        stop()
        currentRequest = nil
        audioSession.clear()
    }
}
