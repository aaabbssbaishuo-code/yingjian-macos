import Foundation
import Translation

enum TranslationServiceError: Error {
    case emptyResult
}

struct TranslationService {
    static let sourceLanguage = Locale.Language(identifier: "en")
    static let targetLanguage = Locale.Language(identifier: "zh-Hans")

    private let interfaceGlossary: [String: String] = [
        "apply": "应用",
        "cancel": "取消",
        "continue": "继续",
        "copy": "复制",
        "done": "完成",
        "edit": "编辑",
        "full access": "完全访问",
        "open in new window": "在新窗口中打开",
        "preferences": "偏好设置",
        "preferences...": "偏好设置",
        "preferences…": "偏好设置",
        "preferences settings": "偏好设置",
        "preview": "预览",
        "please try again": "请稍后重试",
        "pin chat": "置顶聊天",
        "rename chat": "重命名聊天",
        "archive chat": "归档聊天",
        "mark as unread": "标记为未读",
        "ask for approval": "请求批准",
        "always ask to edit external files and use the internet": "始终在编辑外部文件和使用互联网前询问",
        "approve for me": "自动为我批准",
        "copy working directory": "复制工作目录",
        "copy session id": "复制会话 ID",
        "copy deeplink": "复制深链",
        "reveal in finder": "在 Finder 中显示",
        "something went wrong": "出现错误",
        "sign in to continue": "请登录后继续",
        "settings": "设置",
        "search": "搜索",
        "share": "共享",
        "skip": "跳过",
        "start": "开始",
        "update available": "有可用更新",
        "view all": "查看全部"
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

            let source = Self.normalizedInterfaceKey(paragraph)
            results.append(interfaceGlossary[source] ?? translated)
        }

        return results
    }

    private static func normalizedInterfaceKey(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedBullet = trimmed.replacingOccurrences(
            of: #"^[•·\-\u{2022}\u{2023}\u{25E6}\d]+(?:[.)、:]|\s)?\s*"#,
            with: "",
            options: .regularExpression
        )
        let collapsedWhitespace = strippedBullet.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmedPunctuation = collapsedWhitespace
            .trimmingCharacters(in: CharacterSet(charactersIn: "…"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPunctuation.lowercased()
    }
}
