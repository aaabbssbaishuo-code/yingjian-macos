import AppKit
import SwiftUI
import Translation

@MainActor
final class FloatingTranslationPanel: NSPanel {
    private let speechService = SpeechService()
    private var dismissTask: Task<Void, Never>?
    private var cardModel: TranslationCardModel?

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 176),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    func present(paragraphs: [String], near selection: CGRect, on screen: NSScreen) {
        dismissTask?.cancel()
        let model = TranslationCardModel(paragraphs: paragraphs)
        cardModel = model
        speechService.onSpeakingChanged = { [weak model] isSpeaking in
            model?.setSpeaking(isSpeaking)
        }

        let panelSize = TranslationCardView.preferredSize(
            paragraphCount: paragraphs.count
        )
        let rootView = TranslationCardView(
            model: model,
            panelSize: panelSize,
            onSpeak: { [weak self] in
                self?.toggleSpeech(model.fullEnglishText)
            },
            onCopy: {
                guard let chinese = model.translatedText else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(chinese, forType: .string)
                ToastPresenter.show(message: "已复制中文译文")
            },
            onClose: { [weak self] in
                self?.dismiss()
            },
            onHover: { [weak self] hovering in
                self?.handleHover(hovering)
            },
            onTranslationFinished: { [weak self] in
                self?.scheduleDismiss()
            }
        )

        setContentSize(panelSize)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: panelSize)
        contentView = hostingView

        setFrameOrigin(
            PanelPlacement.origin(
                panelSize: panelSize,
                selection: selection,
                visibleFrame: screen.visibleFrame
            )
        )

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }

    }

    func dismiss() {
        dismissTask?.cancel()
        speechService.stop()
        speechService.onSpeakingChanged = nil
        cardModel = nil
        guard isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    private func toggleSpeech(_ text: String) {
        if speechService.isSpeaking {
            speechService.stop()
        } else if !speechService.speak(text) {
            ToastPresenter.show(message: "朗读失败，请稍后重试。")
        }
    }

    private func handleHover(_ hovering: Bool) {
        if hovering {
            dismissTask?.cancel()
        } else {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss()
            }
        }
    }
}

@MainActor
private final class TranslationCardModel: ObservableObject {
    enum State {
        case translating
        case translated
        case failed
    }

    let paragraphs: [String]
    @Published private(set) var translations: [String] = []
    @Published private(set) var state = State.translating
    @Published private(set) var isSpeaking = false

    init(paragraphs: [String]) {
        self.paragraphs = paragraphs
    }

    var translatedText: String? {
        state == .translated
            ? translations.joined(separator: "\n\n")
            : nil
    }

    var fullEnglishText: String {
        paragraphs.joined(separator: "\n\n")
    }

    func complete(with translations: [String]) {
        self.translations = translations
        state = .translated
    }

    func fail() {
        translations = ["翻译失败，请检查网络或语言包后重试。"]
        state = .failed
    }

    func setSpeaking(_ isSpeaking: Bool) {
        self.isSpeaking = isSpeaking
    }
}

private enum PanelPlacement {
    static func origin(
        panelSize: CGSize,
        selection: CGRect,
        visibleFrame: CGRect
    ) -> CGPoint {
        let gap: CGFloat = 10
        let margin: CGFloat = 12

        let candidates = [
            CGPoint(x: selection.midX - panelSize.width / 2, y: selection.minY - panelSize.height - gap),
            CGPoint(x: selection.midX - panelSize.width / 2, y: selection.maxY + gap),
            CGPoint(x: selection.maxX + gap, y: selection.midY - panelSize.height / 2),
            CGPoint(x: selection.minX - panelSize.width - gap, y: selection.midY - panelSize.height / 2)
        ]

        for candidate in candidates {
            let frame = CGRect(origin: candidate, size: panelSize)
            if visibleFrame.insetBy(dx: margin, dy: margin).contains(frame) {
                return candidate
            }
        }

        return CGPoint(
            x: min(
                max(selection.midX - panelSize.width / 2, visibleFrame.minX + margin),
                visibleFrame.maxX - panelSize.width - margin
            ),
            y: min(
                max(selection.minY - panelSize.height - gap, visibleFrame.minY + margin),
                visibleFrame.maxY - panelSize.height - margin
            )
        )
    }
}

private struct TranslationCardView: View {
    @ObservedObject var model: TranslationCardModel
    let panelSize: CGSize
    let onSpeak: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void
    let onTranslationFinished: () -> Void

    private let translationService = TranslationService()

    static func preferredSize(paragraphCount: Int) -> CGSize {
        let height: CGFloat
        if paragraphCount <= 1 {
            height = 176
        } else {
            height = min(460, 116 + CGFloat(paragraphCount) * 66)
        }
        return CGSize(width: 440, height: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                translationContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PanelIconButtonStyle())
                .help("关闭")
            }

            if model.paragraphs.count == 1,
               let english = model.paragraphs.first {
                Text(english)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    onSpeak()
                } label: {
                    Image(systemName: model.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                }
                .buttonStyle(PanelIconButtonStyle(isActive: model.isSpeaking))
                .help("朗读英文")

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(PanelIconButtonStyle())
                .help("复制中文")
                .disabled(model.translatedText == nil)

                Spacer()

                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: panelSize.width, height: panelSize.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .onHover(perform: onHover)
        .translationTask(
            source: TranslationService.sourceLanguage,
            target: TranslationService.targetLanguage
        ) { session in
            do {
                let translations = try await translationService.translateParagraphs(
                    model.paragraphs,
                    using: session
                )
                await MainActor.run {
                    model.complete(with: translations)
                    onTranslationFinished()
                }
            } catch {
                await MainActor.run {
                    model.fail()
                    ToastPresenter.show(message: "翻译失败，请检查网络或语言包。")
                    onTranslationFinished()
                }
            }
        }
    }

    @ViewBuilder
    private var translationContent: some View {
        switch model.state {
        case .translating:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在翻译 \(model.paragraphs.count) 段英文…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        case .translated, .failed:
            if model.translations.count <= 1 {
                Text(model.translations.first ?? "")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.translations.enumerated()), id: \.offset) { index, text in
                            Text(text)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)

                            if index < model.translations.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch model.state {
        case .translating:
            return "Apple Translation"
        case .translated:
            return model.paragraphs.count == 1
                ? "已在设备上翻译"
                : "已翻译 \(model.paragraphs.count) 段英文"
        case .failed:
            return "Translation unavailable"
        }
    }
}

private struct PanelIconButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.78))
            .frame(width: 30, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isActive
                            ? Color.accentColor.opacity(0.14)
                            : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06)
                    )
            )
    }
}
