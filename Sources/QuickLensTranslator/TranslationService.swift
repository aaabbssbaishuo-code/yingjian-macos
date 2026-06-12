import Foundation
import Translation

enum TranslationServiceError: Error {
    case emptyResult
}

struct TranslationService {
    static let sourceLanguage = Locale.Language(identifier: "en")
    static let targetLanguage = Locale.Language(identifier: "zh-Hans")

    private let interfaceGlossary = [
        "Apply": "应用",
        "Preferences": "偏好设置",
        "Something went wrong": "出现错误",
        "Sign in to continue": "请登录后继续"
    ]

    func translateParagraphs(
        _ paragraphs: [String],
        using session: TranslationSession
    ) async throws -> [String] {
        var results: [String] = []
        results.reserveCapacity(paragraphs.count)

        for paragraph in paragraphs {
            let response = try await session.translate(paragraph)
            let translated = response.targetText
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !translated.isEmpty else {
                throw TranslationServiceError.emptyResult
            }

            let source = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(interfaceGlossary[source] ?? translated)
        }

        return results
    }
}
