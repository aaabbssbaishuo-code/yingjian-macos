import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let loginItemService: LoginItemService
    private let onStartCapture: () -> Void
    private let onQuit: () -> Void
    private lazy var loginItem = NSMenuItem(
        title: "开机自动启动",
        action: #selector(toggleLoginItem),
        keyEquivalent: ""
    )

    init(
        loginItemService: LoginItemService,
        onStartCapture: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.loginItemService = loginItemService
        self.onStartCapture = onStartCapture
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

        let shortcutItem = NSMenuItem(
            title: "快捷键：Command + Shift + T",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
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
}
