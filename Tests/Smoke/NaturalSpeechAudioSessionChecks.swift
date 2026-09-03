import Foundation

private actor GenerationProbe {
    private var counts: [NaturalSpeechRequest: Int] = [:]

    func generate(_ request: NaturalSpeechRequest) async throws -> NaturalSpeechAudio {
        counts[request, default: 0] += 1
        try await Task.sleep(for: .milliseconds(60))
        return NaturalSpeechAudio(samples: [0, 0.1, 0.2, 0], sampleRate: 24_000)
    }

    func count(for request: NaturalSpeechRequest) -> Int { counts[request, default: 0] }
}

private actor PlaybackProbe {
    private(set) var count = 0

    func generate(_ request: NaturalSpeechRequest) async throws -> NaturalSpeechAudio {
        count += 1
        try await Task.sleep(for: .milliseconds(60))
        return NaturalSpeechAudio(samples: Array(repeating: 0, count: 4_800), sampleRate: 24_000)
    }
}

@main
struct NaturalSpeechAudioSessionChecks {
    @MainActor
    static func main() async throws {
        let files = NaturalVoiceModelFiles(
            model: URL(fileURLWithPath: "/test/model"),
            voices: URL(fileURLWithPath: "/test/voices"),
            tokens: URL(fileURLWithPath: "/test/tokens"),
            dataDirectory: URL(fileURLWithPath: "/test/data"),
            dictionaryDirectory: nil,
            lexicon: URL(fileURLWithPath: "/test/lexicon")
        )
        func request(_ text: String, rate: Float = 120, voice: String = "am_michael") -> NaturalSpeechRequest {
            NaturalSpeechRequest(
                text: text,
                files: files,
                voice: NaturalVoiceOption.resolve(voice),
                wordsPerMinute: rate
            )
        }
        let probe = GenerationProbe()
        let session = NaturalSpeechAudioSession { try await probe.generate($0) }
        let click = request("Click")
        let first = try await session.audio(for: click)
        let replay = try await session.audio(for: click)
        require(first.samples == replay.samples, "Replay must reuse the generated samples")
        require(await probe.count(for: click) == 1, "Replay must not run inference again")

        let shared = request("Same pending request")
        async let prefetch = session.audio(for: shared)
        async let playback = session.audio(for: shared)
        _ = try await (prefetch, playback)
        require(await probe.count(for: shared) == 1, "Prefetch and playback must share one inference")

        let interrupted = request("Cancelled waiter")
        let oldWaiter = Task { try await session.audio(for: interrupted) }
        try await Task.sleep(for: .milliseconds(15))
        oldWaiter.cancel()
        _ = try await session.audio(for: interrupted)
        _ = try? await oldWaiter.value
        require(await probe.count(for: interrupted) == 1, "A cancelled click must not force duplicate inference")

        for variation in [request("Click", rate: 100), request("Click", voice: "af_heart")] {
            _ = try await session.audio(for: variation)
            require(await probe.count(for: variation) == 1, "Voice/rate must be part of the audio key")
        }
        let stale = request("Old panel")
        let oldPanel = Task { try await session.audio(for: stale) }
        try await Task.sleep(for: .milliseconds(15))
        session.clear()
        do {
            _ = try await oldPanel.value
            fatalError("Cleared panel must reject stale audio")
        } catch is CancellationError {}
        require(session.cachedByteCount == 0, "Closing a panel must clear its audio")
        _ = try await session.audio(for: click)
        require(await probe.count(for: click) == 2, "A new panel must not retain the previous panel's text")

        let limitedProbe = GenerationProbe()
        let limited = NaturalSpeechAudioSession(byteLimit: 32, entryLimit: 2) {
            try await limitedProbe.generate($0)
        }
        let a = request("A"), b = request("B"), c = request("C")
        for key in [a, b, a, c, a, b] {
            _ = try await limited.audio(for: key)
            require(limited.cachedByteCount <= 32, "Cache exceeded its byte limit")
        }
        require(await limitedProbe.count(for: a) == 1, "LRU must keep recently replayed audio")
        require(await limitedProbe.count(for: b) == 2, "LRU must evict the oldest audio")

        let superseded = request("Superseded voice")
        let pending = Task { try await limited.audio(for: superseded) }
        try await Task.sleep(for: .milliseconds(15))
        limited.cancelPending(except: [a])
        do {
            _ = try await pending.value
            fatalError("A superseded voice request must be cancelled")
        } catch is CancellationError {}

        print("PASS: replay, in-flight deduplication, cancellation, voice/rate keys, privacy cleanup, LRU bounds")
        if CommandLine.arguments.contains("--real-model") {
            try await checkRealModel()
        }
        if CommandLine.arguments.contains("--playback") {
            try await checkSpeechReplay()
        }
    }

    private static func require(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    @MainActor
    private static func checkRealModel() async throws {
        guard let files = NaturalVoicePackManager.standard.modelFiles else {
            fatalError("Install the natural voice pack before running --real-model")
        }
        let session = NaturalSpeechAudioSession()
        let request = NaturalSpeechRequest(
            text: "Translate what you see, one clear word at a time.",
            files: files,
            voice: NaturalVoiceOption.resolve("am_michael"),
            wordsPerMinute: 120
        )
        let firstStart = ContinuousClock.now
        let first = try await session.audio(for: request)
        print("real first generation: \(firstStart.duration(to: .now)); audio: \(first.duration)s")
        for index in 1...3 {
            let start = ContinuousClock.now
            let replay = try await session.audio(for: request)
            require(replay.samples == first.samples, "Real replay samples changed")
            print("real replay \(index): \(start.duration(to: .now)) (audio ready, no inference)")
        }
        session.clear()
        await KokoroSpeechSynthesizer.shared.unload()
    }

    @MainActor
    private static func checkSpeechReplay() async throws {
        let suite = "NaturalSpeechChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.register(defaults: [
            "speechRate": 120,
            "speechEngine": "natural",
            "naturalSpeechVoiceIdentifier": "am_michael"
        ])
        let settings = SpeechSettingsStore(defaults: defaults)
        let probe = PlaybackProbe()
        let audioSession = NaturalSpeechAudioSession { try await probe.generate($0) }
        let service = SpeechService(
            settingsStore: settings,
            voicePackManager: .standard,
            naturalAudioSession: audioSession
        )
        let text = "These FAQs are general in nature. The information given does not take personal or specific circumstances into account and should therefore not be considered as constituting personal, professional or legal advice to the user."
        var failure: String?
        service.onError = { failure = $0 }
        service.onActiveWordRangeChanged = { _, range in
            if let range {
                require(NSMaxRange(range) <= (text as NSString).length, "Highlight range is outside the source")
            }
        }
        service.prepareNaturalVoiceIfNeeded(paragraphs: [text])
        try await Task.sleep(for: .seconds(0.5))
        var firstPassCount = 0
        for cycle in 1...2 {
            let start = ContinuousClock.now
            require(service.speak(paragraphs: [text]), "Speech did not start")
            try await waitUntil { service.isSpeaking }
            print("silent SpeechService cycle \(cycle), playback started: \(start.duration(to: .now))")
            if cycle == 1 {
                service.pause()
                require(service.isPaused, "Pause did not preserve speech state")
                try await Task.sleep(for: .milliseconds(100))
                service.resume()
                require(service.isSpeaking, "Resume did not restart the player")
            }
            try await waitUntil { service.state == .idle }
            require(failure == nil, "Speech failed: \(failure ?? "")")
            if cycle == 1 { firstPassCount = await probe.count }
        }
        let calls = await probe.count
        require(firstPassCount > 0 && calls == firstPassCount, "Replay generated the long sentence twice")
        service.stop()
        service.releaseNaturalResources()
        require(audioSession.cachedByteCount == 0, "Dismissal left speech audio cached")
        print("PASS: silent SpeechService prefetch/replay, pause/resume, range bounds and dismissal")
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        require(condition(), "Timed out waiting for speech state")
    }
}
