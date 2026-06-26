import AppKit
import SwiftUI
import Translation

@MainActor
final class FloatingTranslationPanel: NSPanel {
    private let speechService = SpeechService()
    private var dismissTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var cardModel: TranslationCardModel?
    private var hostingView: NSHostingView<AnyView>?
    private var currentSelection: CGRect?
    private var currentScreen: NSScreen?
    private let entryOffset: CGFloat = 10
    private let transitionDuration: TimeInterval = 0.18
    private let panelWidth: CGFloat = 440

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
        installOutsideClickMonitor()
        let model = TranslationCardModel(paragraphs: paragraphs)
        cardModel = model
        speechService.onStateChanged = { [weak model] state in
            model?.setSpeechState(state)
        }
        speechService.onActiveParagraphChanged = { [weak model] index in
            model?.setActiveSpeechParagraphIndex(index)
        }
        speechService.onActiveWordRangeChanged = { [weak model] paragraphIndex, range in
            model?.setActiveSpeechWord(paragraphIndex: paragraphIndex, range: range)
        }

        currentSelection = selection
        currentScreen = screen

        let rootView = AnyView(TranslationCardView(
            model: model,
            panelWidth: panelWidth,
            onSpeak: { [weak self] in
                self?.toggleSpeech(model.paragraphs)
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
                guard let self else { return }
                self.relayoutPanel(animated: true)
                self.scheduleDismiss()
            }
        ))

        let panelSize = TranslationCardView.preferredSize(
            model: model,
            panelWidth: panelWidth,
            visibleFrame: screen.visibleFrame
        )
        applyPanelSize(panelSize, selection: selection, screen: screen, animated: false)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: panelSize)
        contentView = hostingView
        self.hostingView = hostingView

        alphaValue = 0
        let finalFrame = frame
        setFrame(
            finalFrame.offsetBy(dx: 0, dy: -entryOffset),
            display: false
        )
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(finalFrame, display: true)
        }

    }

    func dismiss() {
        dismissTask?.cancel()
        removeOutsideClickMonitor()
        speechService.stop()
        speechService.onStateChanged = nil
        speechService.onActiveParagraphChanged = nil
        speechService.onActiveWordRangeChanged = nil
        cardModel = nil
        hostingView = nil
        currentSelection = nil
        currentScreen = nil
        guard isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(frame.offsetBy(dx: 0, dy: -entryOffset), display: true)
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    private func toggleSpeech(_ paragraphs: [String]) {
        if !speechService.toggle(paragraphs: paragraphs) {
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

    private func relayoutPanel(animated: Bool) {
        guard let model = cardModel,
              let selection = currentSelection,
              let screen = currentScreen else {
            return
        }

        let size = TranslationCardView.preferredSize(
            model: model,
            panelWidth: panelWidth,
            visibleFrame: screen.visibleFrame
        )
        applyPanelSize(size, selection: selection, screen: screen, animated: animated)
    }

    private func applyPanelSize(
        _ size: CGSize,
        selection: CGRect,
        screen: NSScreen,
        animated: Bool
    ) {
        let origin = PanelPlacement.origin(
            panelSize: size,
            selection: selection,
            visibleFrame: screen.visibleFrame
        )

        if animated, isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(CGRect(origin: origin, size: size), display: true)
            }
        } else {
            setFrame(CGRect(origin: origin, size: size), display: true)
        }

        setContentSize(size)
        hostingView?.frame = CGRect(origin: .zero, size: size)
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            let mouseLocation = NSEvent.mouseLocation
            guard !self.frame.contains(mouseLocation) else { return }
            Task { @MainActor in
                self.dismiss()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
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
    @Published private(set) var speechState = SpeechService.State.idle
    @Published private(set) var activeSpeechParagraphIndex: Int?
    @Published private(set) var activeSpeechWordRange: NSRange?

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

    var isSpeaking: Bool {
        speechState == .speaking
    }

    var isPaused: Bool {
        speechState == .paused
    }

    func setSpeechState(_ speechState: SpeechService.State) {
        self.speechState = speechState
        if speechState == .idle {
            activeSpeechParagraphIndex = nil
            activeSpeechWordRange = nil
        }
    }

    func setActiveSpeechParagraphIndex(_ index: Int?) {
        activeSpeechParagraphIndex = index
        if index == nil {
            activeSpeechWordRange = nil
        }
    }

    func setActiveSpeechWord(paragraphIndex: Int?, range: NSRange?) {
        activeSpeechParagraphIndex = paragraphIndex
        activeSpeechWordRange = range
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
    let panelWidth: CGFloat
    let onSpeak: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void
    let onTranslationFinished: () -> Void

    private let translationService = TranslationService()

    static func preferredSize(
        model: TranslationCardModel,
        panelWidth: CGFloat,
        visibleFrame: CGRect
    ) -> CGSize {
        let width = panelWidth
        let contentWidth = width - 32
        let maxHeight = max(220, visibleFrame.height - 80)

        let topArea: CGFloat = 30
        let dividerArea: CGFloat = 1
        let bottomArea: CGFloat = 28
        let verticalPadding: CGFloat = 32
        let spacing: CGFloat = 10

        let contentHeight: CGFloat
        switch model.state {
        case .translating:
            contentHeight = 28
        case .translated, .failed:
            let itemCount = displayItemCount(for: model)
            contentHeight = (0..<itemCount).reduce(into: CGFloat(0)) { total, index in
                let chineseFont = NSFont.systemFont(
                    ofSize: itemCount == 1 ? 17 : 15,
                    weight: .semibold
                )
                total += measuredTextHeight(
                    translationText(for: model, at: index),
                    font: chineseFont,
                    width: contentWidth
                )

                if let english = englishText(for: model, at: index),
                   !english.isEmpty {
                    total += 8
                    total += measuredTextHeight(
                        english,
                        font: .systemFont(ofSize: 13),
                        width: contentWidth
                    )
                }

                if itemCount > 1 {
                    total += 14
                }
                if index < itemCount - 1 {
                    total += 1 + 14
                }
            }
        }

        let totalHeight = verticalPadding
            + topArea
            + contentHeight
            + spacing
            + dividerArea
            + spacing
            + bottomArea

        let height = min(max(totalHeight, 176), maxHeight)
        return CGSize(width: width, height: height)
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

            Divider()

            HStack(spacing: 8) {
                Button {
                    onSpeak()
                } label: {
                    Image(systemName: model.isPaused ? "play.fill" : (model.isSpeaking ? "pause.fill" : "speaker.wave.2"))
                }
                .buttonStyle(PanelIconButtonStyle(isActive: model.isSpeaking || model.isPaused))
                .help(model.isPaused ? "继续朗读" : (model.isSpeaking ? "暂停朗读" : "朗读英文"))

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
        .frame(width: panelWidth)
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
                try await session.prepareTranslation()
                let translations = try await translationService.translateParagraphs(
                    model.paragraphs,
                    using: session
                )
                await MainActor.run {
                    model.complete(with: translations)
                    onTranslationFinished()
                }
            } catch TranslationError.unsupportedSourceLanguage,
                    TranslationError.unsupportedTargetLanguage,
                    TranslationError.unsupportedLanguagePairing {
                await MainActor.run {
                    model.fail()
                    ToastPresenter.show(message: "当前系统不支持这组翻译语言。")
                    onTranslationFinished()
                }
            } catch {
                if isTranslationLanguagePackNotInstalled(error) {
                    await MainActor.run {
                        model.fail()
                        ToastPresenter.show(message: "翻译语言包未就绪，请保持联网后重试。")
                        onTranslationFinished()
                    }
                    return
                }

                await MainActor.run {
                    model.fail()
                    ToastPresenter.show(message: "翻译失败，请检查网络或语言包。")
                    onTranslationFinished()
                }
            }
        }
    }

    private func isTranslationLanguagePackNotInstalled(_ error: Error) -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        return TranslationError.notInstalled ~= error
    }

    @ViewBuilder
    private var translationContent: some View {
        switch model.state {
        case .translating:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在翻译 \(model.paragraphs.count) 段英文…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        case .translated, .failed:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let itemCount = displayItemCount(for: model)
                    ForEach(0..<itemCount, id: \.self) { index in
                        TranslationParagraphRow(
                            chinese: translationText(for: model, at: index),
                            english: englishText(for: model, at: index),
                            isSingle: itemCount == 1,
                            activeWordRange: model.activeSpeechParagraphIndex == index
                                ? model.activeSpeechWordRange
                                : nil
                        )

                        if index < itemCount - 1 {
                            Divider()
                                .padding(.vertical, 7)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

private struct TranslationParagraphRow: View {
    let chinese: String
    let english: String?
    let isSingle: Bool
    let activeWordRange: NSRange?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chinese)
                .font(.system(size: isSingle ? 17 : 15, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let english, !english.isEmpty {
                highlightedEnglishText(english, activeWordRange: activeWordRange)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.08), value: activeWordRange?.location)
            }
        }
        .padding(.vertical, isSingle ? 0 : 7)
    }

    private func highlightedEnglishText(_ english: String, activeWordRange: NSRange?) -> Text {
        guard let activeWordRange,
              let range = Range(activeWordRange, in: english),
              !range.isEmpty else {
            return Text(english).foregroundColor(.secondary)
        }

        let prefix = String(english[..<range.lowerBound])
        let word = String(english[range])
        let suffix = String(english[range.upperBound...])

        return Text(prefix).foregroundColor(.secondary)
            + Text(word).foregroundColor(.accentColor).bold().underline()
            + Text(suffix).foregroundColor(.secondary)
    }
}

@MainActor
private func displayItemCount(for model: TranslationCardModel) -> Int {
    if model.state == .failed {
        return 1
    }
    return max(model.paragraphs.count, model.translations.count, 1)
}

@MainActor
private func translationText(for model: TranslationCardModel, at index: Int) -> String {
    if model.translations.indices.contains(index) {
        return model.translations[index]
    }
    return model.translations.first ?? ""
}

@MainActor
private func englishText(for model: TranslationCardModel, at index: Int) -> String? {
    if model.state == .failed {
        return model.fullEnglishText
    }
    guard model.paragraphs.indices.contains(index) else { return nil }
    return model.paragraphs[index]
}

private func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return font.pointSize + 4 }

    let rect = (text as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font]
    )
    return ceil(rect.height)
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
