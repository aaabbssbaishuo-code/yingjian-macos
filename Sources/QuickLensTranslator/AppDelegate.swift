import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let hotKeyManager = HotKeyManager()
    private let captureCoordinator = CaptureCoordinator()
    private let loginItemService = LoginItemService()
    private let launchGuideService = LaunchGuideService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItemService.enableByDefaultIfNeeded()

        menuBarController = MenuBarController(
            loginItemService: loginItemService,
            shortcut: hotKeyManager.shortcut,
            onStartCapture: { [weak self] in
                self?.startCapture()
            },
            onPauseShortcut: { [weak self] in
                self?.hotKeyManager.unregister()
            },
            onResumeShortcut: { [weak self] in
                guard let self else { return }
                try self.hotKeyManager.registerCurrentHotKey()
            },
            onUpdateShortcut: { [weak self] shortcut in
                guard let self else { return }
                try self.hotKeyManager.updateShortcut(shortcut)
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        hotKeyManager.onHotKey = { [weak self] in
            self?.startCapture()
        }

        do {
            try hotKeyManager.registerCurrentHotKey()
        } catch {
            AlertPresenter.show(
                title: "快捷键注册失败",
                message: "无法注册 \(hotKeyManager.shortcut.displayName)。请从菜单栏为英见设置另一个快捷键。"
            )
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            await launchGuideService.runIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    private func startCapture() {
        guard !captureCoordinator.isCapturing else { return }
        captureCoordinator.start()
    }
}
