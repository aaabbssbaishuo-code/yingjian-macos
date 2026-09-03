import Foundation

struct NaturalSpeechRequest: Hashable, Sendable {
    let text: String
    let files: NaturalVoiceModelFiles
    let voice: NaturalVoiceOption
    let wordsPerMinute: Float
}

// Audio lives only for the current panel; the shared model never retains source text.
@MainActor
final class NaturalSpeechAudioSession {
    typealias Generator = @Sendable (NaturalSpeechRequest) async throws -> NaturalSpeechAudio

    private struct CachedAudio {
        let audio: NaturalSpeechAudio
        var lastAccess: UInt64

        var byteCount: Int { audio.samples.count * MemoryLayout<Float>.stride }
    }

    private struct PendingAudio {
        let id: UUID
        let task: Task<NaturalSpeechAudio, Error>
    }

    private let generate: Generator
    private let byteLimit: Int
    private let entryLimit: Int
    private var cache: [NaturalSpeechRequest: CachedAudio] = [:]
    private var pending: [NaturalSpeechRequest: PendingAudio] = [:]
    private var revision = UUID()
    private var accessCounter: UInt64 = 0
    private(set) var cachedByteCount = 0

    init(
        byteLimit: Int = 16 * 1_024 * 1_024,
        entryLimit: Int = 64,
        generate: @escaping Generator = { request in
            try await KokoroSpeechSynthesizer.shared.synthesize(
                text: request.text,
                files: request.files,
                voice: request.voice,
                wordsPerMinute: request.wordsPerMinute
            )
        }
    ) {
        self.byteLimit = max(0, byteLimit)
        self.entryLimit = max(0, entryLimit)
        self.generate = generate
    }

    func audio(for request: NaturalSpeechRequest) async throws -> NaturalSpeechAudio {
        try Task.checkCancellation()
        if var cached = cache[request] {
            accessCounter &+= 1
            cached.lastAccess = accessCounter
            cache[request] = cached
            return cached.audio
        }

        let requestRevision = revision
        let work: PendingAudio
        if let existing = pending[request] {
            work = existing
        } else {
            work = PendingAudio(
                id: UUID(),
                task: Task { [generate] in
                    try Task.checkCancellation()
                    return try await generate(request)
                }
            )
            pending[request] = work
        }

        do {
            let audio = try await work.task.value
            guard revision == requestRevision, !work.task.isCancelled else {
                throw CancellationError()
            }
            if pending[request]?.id == work.id {
                pending[request] = nil
                store(audio, for: request)
            }
            try Task.checkCancellation()
            return audio
        } catch {
            if pending[request]?.id == work.id {
                pending[request] = nil
            }
            throw error
        }
    }

    func cancelPending(except requests: Set<NaturalSpeechRequest>) {
        for key in Array(pending.keys) where !requests.contains(key) {
            pending.removeValue(forKey: key)?.task.cancel()
        }
    }

    func clear() {
        revision = UUID()
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
        cache.removeAll()
        cachedByteCount = 0
    }

    private func store(_ audio: NaturalSpeechAudio, for request: NaturalSpeechRequest) {
        let cost = audio.samples.count * MemoryLayout<Float>.stride
        guard cost <= byteLimit, entryLimit > 0 else { return }
        if let previous = cache.removeValue(forKey: request) {
            cachedByteCount -= previous.byteCount
        }
        while cachedByteCount + cost > byteLimit || cache.count >= entryLimit {
            guard let oldest = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
                break
            }
            cachedByteCount -= oldest.value.byteCount
            cache[oldest.key] = nil
        }
        accessCounter &+= 1
        cache[request] = CachedAudio(audio: audio, lastAccess: accessCounter)
        cachedByteCount += cost
    }
}
