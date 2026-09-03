import AppKit
import AVFoundation
import Carbon
import SwiftUI

@MainActor
final class ShortcutSettingsWindowController {
    private var panel: ShortcutSettingsPanel?
    private var model: ShortcutSettingsModel?

    func present(
        shortcut: KeyboardShortcut,
        speechSettings: SpeechSettings,
        onApply: @escaping (KeyboardShortcut, SpeechSettings) -> String?,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let model = ShortcutSettingsModel(
            shortcut: shortcut,
            speechSettings: speechSettings,
            onApply: onApply,
            onRecordingChanged: onRecordingChanged
        )
        let panel = ShortcutSettingsPanel(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 548),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        model.onClose = { [weak self] in
            self?.dismiss()
        }

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShortcutSettingsView(model: model))
        panel.center()

        self.model = model
        self.panel = panel

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        model?.stopRecording()
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
}

private final class ShortcutSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class ShortcutSettingsModel: ObservableObject {
    @Published var draft: KeyboardShortcut
    @Published var speechRate: Double
    @Published var speechEngine: SpeechEngineKind
    @Published var voiceIdentifier: String
    @Published var naturalVoiceIdentifier: String
    @Published var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            onRecordingChanged(isRecording)
        }
    }
    @Published var errorMessage: String?

    var onClose: (() -> Void)?
    let voiceOptions = EnglishVoiceCatalog.availableVoices()
    let voicePackManager = NaturalVoicePackManager.standard
    private let initialShortcut: KeyboardShortcut
    private let initialSpeechSettings: SpeechSettings
    private let onApply: (KeyboardShortcut, SpeechSettings) -> String?
    private let onRecordingChanged: (Bool) -> Void
    private var previewSynthesizer: AVSpeechSynthesizer?
    let naturalPreview = NaturalSpeechPreviewController()
    private let previewText = "Translate what you see, one clear word at a time."

    init(
        shortcut: KeyboardShortcut,
        speechSettings: SpeechSettings,
        onApply: @escaping (KeyboardShortcut, SpeechSettings) -> String?,
        onRecordingChanged: @escaping (Bool) -> Void
    ) {
        initialShortcut = shortcut
        initialSpeechSettings = speechSettings
        draft = shortcut
        speechRate = Double(speechSettings.rate)
        speechEngine = speechSettings.engine
        voiceIdentifier = speechSettings.voiceIdentifier ?? ""
        naturalVoiceIdentifier = speechSettings.naturalVoiceIdentifier
        self.onApply = onApply
        self.onRecordingChanged = onRecordingChanged
    }

    var hasChanges: Bool {
        draft != initialShortcut || draftSpeechSettings != initialSpeechSettings
    }

    var canSave: Bool {
        hasChanges && (speechEngine == .system || voicePackManager.modelFiles != nil)
    }

    var automaticVoiceTitle: String {
        guard let voice = voiceOptions.first else { return "自动选择" }
        return "自动（\(voice.menuTitle)）"
    }

    var hasHighQualityVoice: Bool {
        voiceOptions.contains { $0.quality > .standard }
    }

    private var draftSpeechSettings: SpeechSettings {
        SpeechSettings(
            rate: Float(speechRate),
            engine: speechEngine,
            voiceIdentifier: voiceIdentifier.isEmpty ? nil : voiceIdentifier,
            naturalVoiceIdentifier: NaturalVoiceOption.resolve(naturalVoiceIdentifier).id
        )
    }

    var naturalPreviewRequest: NaturalSpeechRequest? {
        guard speechEngine == .natural, let files = voicePackManager.modelFiles else { return nil }
        return NaturalSpeechRequest(
            text: previewText,
            files: files,
            voice: NaturalVoiceOption.resolve(naturalVoiceIdentifier),
            wordsPerMinute: Float(speechRate)
        )
    }

    func prepareNaturalPreview() async {
        guard let request = naturalPreviewRequest else {
            naturalPreview.clear()
            return
        }
        await naturalPreview.prepare(request)
    }

    func receive(_ shortcut: KeyboardShortcut) {
        if let validationMessage = shortcut.validationMessage {
            NSSound.beep()
            errorMessage = validationMessage
            return
        }
        draft = shortcut
        errorMessage = nil
        isRecording = false
    }

    func reset() {
        draft = .defaultShortcut
        errorMessage = nil
        isRecording = false
    }

    func resetSpeech() {
        speechRate = Double(SpeechSettings.defaultRate)
        speechEngine = .system
        voiceIdentifier = ""
        naturalVoiceIdentifier = NaturalVoiceOption.defaultVoice.id
        stopPreview()
    }

    func previewSpeech() {
        stopPreview()
        errorMessage = nil
        if speechEngine == .natural {
            guard let files = voicePackManager.modelFiles else {
                errorMessage = "请先下载自然语音包。"
                return
            }
            naturalPreview.speak(
                text: previewText,
                files: files,
                voice: NaturalVoiceOption.resolve(naturalVoiceIdentifier),
                wordsPerMinute: Float(speechRate)
            ) { [weak self] message in
                self?.errorMessage = message
            }
            return
        }

        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(
            string: previewText
        )
        if let identifier = EnglishVoiceCatalog.resolvedVoiceIdentifier(
            for: draftSpeechSettings.voiceIdentifier
        ) {
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
        }
        let progress = (draftSpeechSettings.rate - SpeechSettings.minimumRate)
            / (SpeechSettings.maximumRate - SpeechSettings.minimumRate)
        utterance.rate = 0.36 + progress * 0.14
        utterance.volume = 1
        synthesizer.speak(utterance)
        previewSynthesizer = synthesizer
    }

    func installNaturalVoicePack() {
        errorMessage = nil
        stopPreview()
        voicePackManager.install()
    }

    func cancelNaturalVoicePackInstall() {
        voicePackManager.cancelInstall()
    }

    func removeNaturalVoicePack() {
        stopPreview()
        naturalPreview.clear()
        Task { await KokoroSpeechSynthesizer.shared.unload() }
        voicePackManager.removePack()
        speechEngine = .system
    }

    func save() {
        isRecording = false
        guard speechEngine == .system || voicePackManager.modelFiles != nil else {
            errorMessage = "请先下载自然语音包。"
            return
        }
        if let error = onApply(draft, draftSpeechSettings) {
            errorMessage = error
            return
        }
        onClose?()
    }

    func stopRecording() {
        isRecording = false
        stopPreview()
        naturalPreview.clear()
    }

    private func stopPreview() {
        previewSynthesizer?.stopSpeaking(at: .immediate)
        previewSynthesizer = nil
        naturalPreview.stop()
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject private var voicePackManager: NaturalVoicePackManager
    @ObservedObject private var naturalPreview: NaturalSpeechPreviewController

    init(model: ShortcutSettingsModel) {
        self.model = model
        voicePackManager = model.voicePackManager
        naturalPreview = model.naturalPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 20, weight: .semibold))
                    Text("自定义截图快捷键与英文朗读")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.onClose?()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SettingsIconButtonStyle())
                .help("关闭")
            }

            Divider()
                .padding(.top, 16)

            HStack(spacing: 14) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("截图翻译")
                        .font(.system(size: 14, weight: .medium))
                    Text("在任意应用中启动框选翻译")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                ShortcutRecorder(
                    shortcut: model.draft,
                    isRecording: model.isRecording,
                    onBeginRecording: {
                        model.errorMessage = nil
                        model.isRecording = true
                    },
                    onCancelRecording: {
                        model.isRecording = false
                    },
                    onShortcut: model.receive
                )
                .frame(width: 132, height: 34)

                Button(action: model.reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(model.draft == .defaultShortcut ? .tertiary : .secondary)
                .disabled(model.draft == .defaultShortcut)
                .help("恢复默认快捷键 \(KeyboardShortcut.defaultShortcut.displayString)")
            }
            .padding(.vertical, 16)

            Group {
                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                } else {
                    Label("请组合至少两个修饰键，例如 \(KeyboardShortcut.defaultShortcut.displayString)", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            .lineLimit(2)
            .frame(minHeight: 30, alignment: .topLeading)

            Divider()
                .padding(.vertical, 12)

            HStack(spacing: 14) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("英文朗读")
                        .font(.system(size: 14, weight: .medium))
                    Text("系统语音轻量，自然语音更接近真人")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Picker("朗读引擎", selection: $model.speechEngine) {
                    ForEach(SpeechEngineKind.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            speechVoiceConfiguration
                .padding(.leading, 42)
                .padding(.top, 12)

            HStack(spacing: 10) {
                Text("语速")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 42, alignment: .leading)

                Slider(
                    value: $model.speechRate,
                    in: Double(SpeechSettings.minimumRate)...Double(SpeechSettings.maximumRate),
                    step: 5
                )

                Text("\(Int(model.speechRate)) 词/分钟")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .trailing)

                Button(action: model.resetSpeech) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("恢复推荐声音与语速")
            }
            .padding(.leading, 42)
            .padding(.top, 12)

            if model.speechEngine == .system, !model.hasHighQualityVoice {
                Label("当前仅检测到普通系统语音；可在系统设置的“辅助功能 > 朗读内容”中下载增强声音。", systemImage: "waveform.badge.exclamationmark")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
                    .padding(.top, 9)
            } else if model.speechEngine == .natural,
                      voicePackManager.status == .installed {
                Label("Kokoro 在本机离线生成，英文文本不会上传。", systemImage: "lock.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
                    .padding(.top, 9)
            }

            Spacer(minLength: 10)

            HStack {
                Spacer()
                Button("取消") {
                    model.onClose?()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    model.save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
            }
        }
        .padding(22)
        .frame(width: 520, height: 548)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .task(id: model.naturalPreviewRequest) {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            await model.prepareNaturalPreview()
        }
    }

    @ViewBuilder
    private var speechVoiceConfiguration: some View {
        if model.speechEngine == .system {
            HStack(spacing: 10) {
                Text("声音")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 42, alignment: .leading)

                Picker("", selection: $model.voiceIdentifier) {
                    Text(model.automaticVoiceTitle).tag("")
                    ForEach(model.voiceOptions) { voice in
                        Text(voice.menuTitle).tag(voice.id)
                    }
                }
                .labelsHidden()

                Button(action: model.previewSpeech) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(SettingsIconButtonStyle())
                .help("试听当前声音")
            }
        } else {
            naturalVoiceConfiguration
        }
    }

    @ViewBuilder
    private var naturalVoiceConfiguration: some View {
        switch voicePackManager.status {
        case .notInstalled:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自然语音包尚未安装")
                        .font(.system(size: 12, weight: .medium))
                    Text("Kokoro 82M · \(NaturalVoicePackManager.archiveSizeText) · 仅首次下载")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("下载") {
                    model.installNaturalVoicePack()
                }
            }

        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                Button("取消") {
                    model.cancelNaturalVoicePackInstall()
                }
            }

        case .verifying:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在校验自然语音包…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .installing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在安装自然语音包…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .installed:
            HStack(spacing: 10) {
                Text("声音")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 42, alignment: .leading)

                Picker("", selection: $model.naturalVoiceIdentifier) {
                    ForEach(NaturalVoiceOption.available) { voice in
                        Text(voice.menuTitle).tag(voice.id)
                    }
                }
                .labelsHidden()

                Button(action: model.previewSpeech) {
                    if naturalPreview.state == .preparing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(SettingsIconButtonStyle())
                .help(naturalPreview.state == .preparing ? "正在准备自然声音" : "试听自然声音")

                Button(action: model.removeNaturalVoicePack) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("删除自然语音包")
            }

        case .failed(let message):
            HStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("重试") {
                    model.installNaturalVoicePack()
                }
            }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onCancelRecording: () -> Void
    let onShortcut: (KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        configure(view)
        if isRecording, view.window?.firstResponder !== view {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    private func configure(_ view: ShortcutRecorderView) {
        view.shortcut = shortcut
        view.isRecording = isRecording
        view.onBeginRecording = onBeginRecording
        view.onCancelRecording = onCancelRecording
        view.onShortcut = onShortcut
        view.needsDisplay = true
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("录制截图翻译快捷键")
        view.setAccessibilityValue(
            isRecording ? "等待输入" : shortcut.accessibilityDescription
        )
    }
}

private final class ShortcutRecorderView: NSView {
    var shortcut = KeyboardShortcut.defaultShortcut
    var isRecording = false
    var onBeginRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onShortcut: ((KeyboardShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        onBeginRecording?()
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onBeginRecording?()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            onCancelRecording?()
            return
        }

        guard let shortcut = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }
        onShortcut?(shortcut)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let shape = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 9,
            yRadius: 9
        )
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor)
            .setFill()
        shape.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor)
            .setStroke()
        shape.lineWidth = isRecording ? 1.5 : 1
        shape.stroke()

        let text = isRecording ? "按下快捷键…" : shortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            ),
            withAttributes: attributes
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private struct SettingsIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }
}
