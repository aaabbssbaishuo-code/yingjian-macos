import AppKit
import Translation

@MainActor
final class LaunchGuideService {
    private let didShowInstallGuideKey = "didShowInstallGuide"
    private let didShowPermissionGuideKey = "didShowPermissionGuide"
    private let didShowLanguageGuideKey = "didShowLanguageGuide"
    private let languageAvailability = LanguageAvailability()

    func runIfNeeded() async {
        let showedBlockingGuide =
            showInstallGuideIfNeeded() ||
            showPermissionGuideIfNeeded()
        await showLanguageGuideIfNeeded(showToast: !showedBlockingGuide)
    }

    private func showInstallGuideIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: didShowInstallGuideKey) else { return false }
        guard !Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return false }

        UserDefaults.standard.set(true, forKey: didShowInstallGuideKey)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "建议安装到应用程序"
        alert.informativeText = "为了让更新、启动项和权限管理更稳定，建议把“英见”拖到“应用程序”文件夹后再运行。"
        alert.addButton(withTitle: "打开应用程序文件夹")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        return true
    }

    private func showPermissionGuideIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: didShowPermissionGuideKey) else { return false }

        let needsScreenCapture = !PermissionManager.hasScreenCapturePermission()
        let needsAccessibility = !PermissionManager.hasAccessibilityPermission()
        guard needsScreenCapture || needsAccessibility else { return false }

        UserDefaults.standard.set(true, forKey: didShowPermissionGuideKey)
        NSApp.activate(ignoringOtherApps: true)

        var lines: [String] = []
        if needsScreenCapture {
            lines.append("屏幕录制 / 系统音频录制")
        }
        if needsAccessibility {
            lines.append("辅助功能")
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要系统权限"
        alert.informativeText = "英见需要以下权限才能完成截图翻译：\n• " + lines.joined(separator: "\n• ")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            if needsScreenCapture {
                PermissionManager.requestScreenCapturePermission()
                PermissionManager.openScreenCaptureSettings()
            }
            if needsAccessibility {
                PermissionManager.requestAccessibilityPermission()
                PermissionManager.openAccessibilitySettings()
            }
        }
        return true
    }

    private func showLanguageGuideIfNeeded(showToast: Bool) async {
        guard !UserDefaults.standard.bool(forKey: didShowLanguageGuideKey) else { return }

        let status = await languageAvailability.status(
            from: TranslationService.sourceLanguage,
            to: TranslationService.targetLanguage
        )

        switch status {
        case .installed:
            return
        case .supported:
            UserDefaults.standard.set(true, forKey: didShowLanguageGuideKey)
            if showToast {
                ToastPresenter.show(message: "翻译语言包可用，首次翻译时会自动下载。")
            }
        case .unsupported:
            UserDefaults.standard.set(true, forKey: didShowLanguageGuideKey)
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "翻译语言包暂不可用"
            alert.informativeText = "当前系统尚未提供英文 → 简体中文的翻译语言包。你可以先保持联网，或在系统语言设置中检查翻译语言包状态。"
            alert.addButton(withTitle: "打开语言设置")
            alert.addButton(withTitle: "稍后")

            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.openLocalizationSettings()
            }
        @unknown default:
            return
        }
    }
}
