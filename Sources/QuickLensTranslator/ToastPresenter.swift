import AppKit
import SwiftUI

@MainActor
enum ToastPresenter {
    private static var panel: NSPanel?

    static func show(message: String) {
        panel?.orderOut(nil)

        let size = CGSize(width: 280, height: 52)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - 64
        )

        let toast = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toast.level = .statusBar
        toast.backgroundColor = .clear
        toast.isOpaque = false
        toast.hasShadow = true
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.contentView = NSHostingView(rootView: ToastView(message: message))
        toast.orderFrontRegardless()
        panel = toast

        Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard panel === toast else { return }
            toast.orderOut(nil)
            panel = nil
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(width: 280, height: 52)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
