import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let hotKeyManager = HotKeyManager()
    private let loginItemService = LoginItemService()
    private let launchGuideService = LaunchGuideService()
    private let shortcutStore = ShortcutStore()
    private let speechSettingsStore = SpeechSettingsStore.standard
    private let shortcutSettingsController = ShortcutSettingsWindowController()
    private var currentShortcut = KeyboardShortcut.defaultShortcut
    private lazy var captureCoordinator = CaptureCoordinator { [weak self] in
        self?.showShortcutSettings()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItemService.enableByDefaultIfNeeded()

        hotKeyManager.onHotKey = { [weak self] in
            self?.startCapture()
        }

        currentShortcut = shortcutStore.shortcut
        do {
            try hotKeyManager.register(currentShortcut)
        } catch {
            restoreDefaultShortcut(after: error)
        }

        menuBarController = MenuBarController(
            loginItemService: loginItemService,
            shortcut: currentShortcut,
            onStartCapture: { [weak self] in
                self?.startCapture()
            },
            onOpenSettings: { [weak self] in
                self?.showShortcutSettings()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            warmNaturalVoiceIfEnabled()
            await launchGuideService.runIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    private func startCapture() {
        guard !captureCoordinator.isCapturing else { return }
        warmNaturalVoiceIfEnabled()
        captureCoordinator.start()
    }

    private func warmNaturalVoiceIfEnabled() {
        guard speechSettingsStore.settings.engine == .natural,
              let files = NaturalVoicePackManager.standard.modelFiles else { return }
        Task {
            try? await KokoroSpeechSynthesizer.shared.prepare(files: files)
        }
    }

    private func showShortcutSettings() {
        shortcutSettingsController.present(
            shortcut: currentShortcut,
            speechSettings: speechSettingsStore.settings,
            onApply: { [weak self] shortcut, speechSettings in
                self?.applySettings(shortcut: shortcut, speechSettings: speechSettings)
            },
            onRecordingChanged: { [weak self] isRecording in
                self?.hotKeyManager.isSuspended = isRecording
            }
        )
    }

    private func applySettings(
        shortcut: KeyboardShortcut,
        speechSettings: SpeechSettings
    ) -> String? {
        if shortcut != currentShortcut,
           let errorMessage = applyShortcut(shortcut) {
            return errorMessage
        }
        speechSettingsStore.save(speechSettings)
        warmNaturalVoiceIfEnabled()
        return nil
    }

    private func applyShortcut(_ shortcut: KeyboardShortcut) -> String? {
        if let validationMessage = shortcut.validationMessage {
            return validationMessage
        }

        let previousShortcut = currentShortcut
        do {
            try hotKeyManager.register(shortcut)
            currentShortcut = shortcut
            shortcutStore.save(shortcut)
            menuBarController?.updateShortcut(shortcut)
            return nil
        } catch {
            try? hotKeyManager.register(previousShortcut)
            return error.localizedDescription
        }
    }

    private func restoreDefaultShortcut(after registrationError: Error) {
        guard currentShortcut != .defaultShortcut else {
            AlertPresenter.show(
                title: "快捷键注册失败",
                message: registrationError.localizedDescription
            )
            return
        }

        currentShortcut = .defaultShortcut
        shortcutStore.save(currentShortcut)
        do {
            try hotKeyManager.register(currentShortcut)
            AlertPresenter.show(
                title: "快捷键已恢复默认",
                message: "原快捷键无法注册，已恢复为 \(currentShortcut.accessibilityDescription)。"
            )
        } catch {
            AlertPresenter.show(
                title: "快捷键注册失败",
                message: error.localizedDescription
            )
        }
    }
}
