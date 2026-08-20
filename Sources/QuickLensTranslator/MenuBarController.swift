import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let loginItemService: LoginItemService
    private let onStartCapture: () -> Void
    private let onPauseShortcut: () -> Void
    private let onResumeShortcut: () throws -> Void
    private let onUpdateShortcut: (HotKeyShortcut) throws -> Void
    private let onQuit: () -> Void
    private var shortcut: HotKeyShortcut
    private lazy var shortcutItem = NSMenuItem(
        title: shortcutItemTitle,
        action: #selector(showShortcutSettings),
        keyEquivalent: ""
    )
    private lazy var loginItem = NSMenuItem(
        title: "开机自动启动",
        action: #selector(toggleLoginItem),
        keyEquivalent: ""
    )

    init(
        loginItemService: LoginItemService,
        shortcut: HotKeyShortcut,
        onStartCapture: @escaping () -> Void,
        onPauseShortcut: @escaping () -> Void,
        onResumeShortcut: @escaping () throws -> Void,
        onUpdateShortcut: @escaping (HotKeyShortcut) throws -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.loginItemService = loginItemService
        self.shortcut = shortcut
        self.onStartCapture = onStartCapture
        self.onPauseShortcut = onPauseShortcut
        self.onResumeShortcut = onResumeShortcut
        self.onUpdateShortcut = onUpdateShortcut
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "text.viewfinder",
                accessibilityDescription: "英见"
            )
            button.toolTip = "英见"
        }

        configureMenu()
        statusItem.menu = menu
    }

    private func configureMenu() {
        let startItem = NSMenuItem(
            title: "开始截图翻译",
            action: #selector(startCapture),
            keyEquivalent: ""
        )
        startItem.target = self
        startItem.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)
        menu.addItem(startItem)

        shortcutItem.target = self
        shortcutItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        menu.addItem(shortcutItem)

        menu.addItem(.separator())

        loginItem.target = self
        loginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(loginItem)
        updateLoginItemState()

        let privacyItem = NSMenuItem(
            title: "隐私说明",
            action: #selector(showPrivacy),
            keyEquivalent: ""
        )
        privacyItem.target = self
        privacyItem.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
        menu.addItem(privacyItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出英见",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func startCapture() {
        onStartCapture()
    }

    @objc private func showShortcutSettings() {
        onPauseShortcut()
        let result = ShortcutRecorder.run(currentShortcut: shortcut)
        let newShortcut: HotKeyShortcut

        switch result {
        case let .save(recordedShortcut):
            newShortcut = recordedShortcut
        case .restoreDefault:
            newShortcut = .default
        case .cancel:
            try? onResumeShortcut()
            return
        }

        do {
            try onUpdateShortcut(newShortcut)
            shortcut = newShortcut
            shortcutItem.title = shortcutItemTitle
            ToastPresenter.show(message: "快捷键已设为 \(newShortcut.displayName)")
        } catch {
            AlertPresenter.show(
                title: "无法使用这个快捷键",
                message: "这个组合键可能已被其他应用占用。原来的快捷键仍然有效，请换一个组合后重试。"
            )
        }
    }

    @objc private func showPrivacy() {
        AlertPresenter.show(
            title: "隐私说明",
            message: "截图仅用于本次文字识别和翻译。应用不保存截图、OCR 原文或翻译结果，也不提供历史记录、账号或云同步。"
        )
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemService.setEnabled(!loginItemService.isEnabled)
            updateLoginItemState()
        } catch {
            updateLoginItemState()
            AlertPresenter.show(
                title: "无法更新开机启动",
                message: "请将应用放入“应用程序”文件夹后重试，或在“系统设置 → 通用 → 登录项”中手动设置。"
            )
        }
    }

    @objc private func quit() {
        onQuit()
    }

    private func updateLoginItemState() {
        loginItem.state = loginItemService.isEnabled ? .on : .off
    }

    private var shortcutItemTitle: String {
        "设置快捷键…（当前 \(shortcut.displayName)）"
    }
}
