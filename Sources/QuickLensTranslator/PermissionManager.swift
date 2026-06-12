import AppKit
import CoreGraphics

enum PermissionManager {
    @MainActor
    static func requestScreenCapturePermission() {
        _ = CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许英见。如果开关已经开启，请先关闭再重新开启，然后退出并重新打开英见。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
