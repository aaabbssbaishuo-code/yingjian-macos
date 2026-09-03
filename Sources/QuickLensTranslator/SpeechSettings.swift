import AVFoundation
import Foundation

enum SpeechEngineKind: String, CaseIterable, Identifiable {
    case system
    case natural

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "系统声音"
        case .natural: return "自然语音"
        }
    }
}

struct SpeechSettings: Equatable {
    static let defaultRate: Float = 120
    static let minimumRate: Float = 90
    static let maximumRate: Float = 160

    var rate: Float
    var engine: SpeechEngineKind
    var voiceIdentifier: String?
    var naturalVoiceIdentifier: String

    static let `default` = SpeechSettings(
        rate: defaultRate,
        engine: .system,
        voiceIdentifier: nil,
        naturalVoiceIdentifier: NaturalVoiceOption.defaultVoice.id
    )
}

struct NaturalVoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let accent: String
    let speakerID: Int

    var menuTitle: String {
        "\(name)（\(accent)）"
    }

    static let available: [NaturalVoiceOption] = [
        NaturalVoiceOption(id: "af_heart", name: "Heart", accent: "美式女声 · 推荐", speakerID: 3),
        NaturalVoiceOption(id: "af_bella", name: "Bella", accent: "美式女声", speakerID: 2),
        NaturalVoiceOption(id: "af_sarah", name: "Sarah", accent: "美式女声", speakerID: 9),
        NaturalVoiceOption(id: "af_sky", name: "Sky", accent: "美式女声", speakerID: 10),
        NaturalVoiceOption(id: "am_michael", name: "Michael", accent: "美式男声", speakerID: 16),
        NaturalVoiceOption(id: "bf_emma", name: "Emma", accent: "英式女声", speakerID: 21),
        NaturalVoiceOption(id: "bm_george", name: "George", accent: "英式男声", speakerID: 26)
    ]

    static let defaultVoice = available[0]

    static func resolve(_ identifier: String) -> NaturalVoiceOption {
        available.first(where: { $0.id == identifier }) ?? defaultVoice
    }
}

struct EnglishVoiceOption: Identifiable, Equatable {
    enum Quality: Int, Comparable {
        case standard = 0
        case enhanced = 1
        case premium = 2

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id: String
    let name: String
    let language: String
    let quality: Quality

    var menuTitle: String {
        let qualityText: String
        switch quality {
        case .standard:
            qualityText = ""
        case .enhanced:
            qualityText = " · 增强"
        case .premium:
            qualityText = " · 高级"
        }
        return "\(name)（\(accentName)）\(qualityText)"
    }

    private var accentName: String {
        switch language.replacingOccurrences(of: "_", with: "-") {
        case "en-US": return "美式"
        case "en-GB": return "英式"
        case "en-AU": return "澳式"
        case "en-IE": return "爱尔兰"
        case "en-IN": return "印度"
        case "en-ZA": return "南非"
        default: return "英语"
        }
    }
}

enum EnglishVoiceCatalog {
    static func availableVoices() -> [EnglishVoiceOption] {
        let preferredNames = ["Samantha", "Ava", "Zoe", "Allison", "Daniel", "Karen", "Moira", "Tessa", "Rishi"]

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .filter { voice in
                let identifier = voice.identifier.lowercased()
                return !identifier.contains("eloquence")
                    && !identifier.contains("speech.synthesis.voice")
            }
            .map { voice in
                let quality: EnglishVoiceOption.Quality
                switch voice.quality {
                case .premium:
                    quality = .premium
                case .enhanced:
                    quality = .enhanced
                default:
                    quality = .standard
                }
                return EnglishVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: quality
                )
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                let lhsAmerican = lhs.language.replacingOccurrences(of: "_", with: "-") == "en-US"
                let rhsAmerican = rhs.language.replacingOccurrences(of: "_", with: "-") == "en-US"
                if lhsAmerican != rhsAmerican {
                    return lhsAmerican
                }
                let lhsRank = preferredNames.firstIndex(of: lhs.name) ?? preferredNames.count
                let rhsRank = preferredNames.firstIndex(of: rhs.name) ?? preferredNames.count
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return lhs.menuTitle.localizedStandardCompare(rhs.menuTitle) == .orderedAscending
            }
    }

    static func resolvedVoiceIdentifier(for requestedIdentifier: String?) -> String? {
        let voices = availableVoices()
        if let requestedIdentifier,
           voices.contains(where: { $0.id == requestedIdentifier }) {
            return requestedIdentifier
        }
        return voices.first?.id
    }
}

@MainActor
final class SpeechSettingsStore {
    static let standard = SpeechSettingsStore()

    private enum Key {
        static let rate = "speechRate"
        static let engine = "speechEngine"
        static let voiceIdentifier = "speechVoiceIdentifier"
        static let naturalVoiceIdentifier = "naturalSpeechVoiceIdentifier"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: SpeechSettings {
        let storedRate = (defaults.object(forKey: Key.rate) as? NSNumber)?.floatValue
            ?? SpeechSettings.defaultRate
        let rate = min(max(storedRate, SpeechSettings.minimumRate), SpeechSettings.maximumRate)
        let engine = defaults.string(forKey: Key.engine)
            .flatMap(SpeechEngineKind.init(rawValue:)) ?? .system
        let voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier)
        let naturalVoiceIdentifier = defaults.string(forKey: Key.naturalVoiceIdentifier)
            ?? NaturalVoiceOption.defaultVoice.id
        return SpeechSettings(
            rate: rate,
            engine: engine,
            voiceIdentifier: voiceIdentifier,
            naturalVoiceIdentifier: NaturalVoiceOption.resolve(naturalVoiceIdentifier).id
        )
    }

    func save(_ settings: SpeechSettings) {
        let rate = min(max(settings.rate, SpeechSettings.minimumRate), SpeechSettings.maximumRate)
        defaults.set(rate, forKey: Key.rate)
        defaults.set(settings.engine.rawValue, forKey: Key.engine)
        if let voiceIdentifier = settings.voiceIdentifier, !voiceIdentifier.isEmpty {
            defaults.set(voiceIdentifier, forKey: Key.voiceIdentifier)
        } else {
            defaults.removeObject(forKey: Key.voiceIdentifier)
        }
        defaults.set(
            NaturalVoiceOption.resolve(settings.naturalVoiceIdentifier).id,
            forKey: Key.naturalVoiceIdentifier
        )
    }
}
