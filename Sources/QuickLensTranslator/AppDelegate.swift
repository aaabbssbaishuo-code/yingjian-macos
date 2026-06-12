import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let hotKeyManager = HotKeyManager()
    private let captureCoordinator = CaptureCoordinator()
    private let loginItemService = LoginItemService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItemService.enableByDefaultIfNeeded()

        menuBarController = MenuBarController(
            loginItemService: loginItemService,
            onStartCapture: { [weak self] in
                self?.startCapture()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        hotKeyManager.onHotKey = { [weak self] in
            self?.startCapture()
        }

        do {
            try hotKeyManager.registerDefaultHotKey()
        } catch {
            AlertPresenter.show(
                title: "快捷键注册失败",
                message: "Command + Shift + T 已被其他应用占用，请退出冲突应用后重试。"
            )
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
