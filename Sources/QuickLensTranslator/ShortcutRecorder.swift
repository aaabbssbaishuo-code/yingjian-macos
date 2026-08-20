import AppKit

enum ShortcutRecorderResult {
    case save(HotKeyShortcut)
    case restoreDefault
    case cancel
}

@MainActor
enum ShortcutRecorder {
    static func run(currentShortcut: HotKeyShortcut) -> ShortcutRecorderResult {
        NSApp.activate(ignoringOtherApps: true)

        let recorderView = ShortcutRecorderView(shortcut: currentShortcut)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "设置截图翻译快捷键"
        alert.informativeText = "按下你习惯的组合键。为避免误触，请至少包含 Command、Option 或 Control。"
        alert.accessoryView = recorderView
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "恢复默认")
        alert.window.initialFirstResponder = recorderView

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save(recorderView.shortcut)
        case .alertThirdButtonReturn:
            return .restoreDefault
        default:
            return .cancel
        }
    }
}

@MainActor
private final class ShortcutRecorderView: NSView {
    private(set) var shortcut: HotKeyShortcut
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "等待按键…")

    init(shortcut: HotKeyShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 92))

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        shortcutLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        shortcutLabel.alignment = .center
        shortcutLabel.stringValue = shortcut.displayName

        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center

        let stack = NSStackView(views: [shortcutLabel, hintLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            super.keyDown(with: event)
            return
        }

        guard let newShortcut = HotKeyShortcut(event: event) else {
            hintLabel.stringValue = "请搭配 Command、Option 或 Control"
            NSSound.beep()
            return
        }

        shortcut = newShortcut
        shortcutLabel.stringValue = newShortcut.displayName
        hintLabel.stringValue = "已记录，保存后即可使用"
    }
}
