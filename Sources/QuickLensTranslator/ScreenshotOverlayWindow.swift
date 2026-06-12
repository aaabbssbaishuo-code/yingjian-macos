import AppKit

enum ScreenshotSelectionResult {
    case selected(CGRect, NSScreen)
    case tooSmall
    case cancelled
}

@MainActor
final class ScreenshotOverlayController {
    private var windows: [ScreenshotOverlayWindow] = []
    private var completion: ((ScreenshotSelectionResult) -> Void)?

    func beginSelection(completion: @escaping (ScreenshotSelectionResult) -> Void) {
        finishWithoutCallback()
        self.completion = completion

        windows = NSScreen.screens.map { screen in
            let window = ScreenshotOverlayWindow(screen: screen)
            window.onSelection = { [weak self] localRect in
                self?.completeSelection(localRect, from: window)
            }
            window.onCancel = { [weak self] in
                self?.complete(.cancelled)
            }
            return window
        }

        NSCursor.crosshair.push()
        let mouseLocation = NSEvent.mouseLocation
        let targetWindow = windows.first {
            $0.targetScreen.frame.contains(mouseLocation)
        } ?? windows.first

        windows
            .filter { $0 !== targetWindow }
            .forEach { $0.orderFrontRegardless() }
        targetWindow?.makeKeyAndOrderFront(nil)
        targetWindow?.makeFirstResponder(targetWindow?.contentView)
    }

    private func completeSelection(_ localRect: CGRect, from window: ScreenshotOverlayWindow) {
        let rect = localRect.standardized

        guard rect.width >= 8, rect.height >= 8 else {
            complete(.tooSmall)
            return
        }

        let screenRect = CGRect(
            x: window.frame.minX + rect.minX,
            y: window.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        complete(.selected(screenRect, window.targetScreen))
    }

    private func complete(_ result: ScreenshotSelectionResult) {
        let callback = completion
        finishWithoutCallback()
        callback?(result)
    }

    private func finishWithoutCallback() {
        if !windows.isEmpty {
            NSCursor.pop()
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion = nil
    }
}

@MainActor
final class ScreenshotOverlayWindow: NSWindow {
    let targetScreen: NSScreen
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        targetScreen = screen
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = ScreenshotSelectionView()

        if let selectionView = contentView as? ScreenshotSelectionView {
            selectionView.onSelection = { [weak self] rect in
                self?.onSelection?(rect)
            }
            selectionView.onCancel = { [weak self] in
                self?.onCancel?()
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class ScreenshotSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let endPoint = convert(event.locationInWindow, from: nil)
        onSelection?(CGRect(
            x: startPoint.x,
            y: startPoint.y,
            width: endPoint.x - startPoint.x,
            height: endPoint.y - startPoint.y
        ).standardized)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.26).setFill()
        bounds.fill()

        guard let selectionRect else {
            drawHint()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        selectionRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()

        drawSizeLabel(for: selectionRect)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: startPoint.x,
            y: startPoint.y,
            width: currentPoint.x - startPoint.x,
            height: currentPoint.y - startPoint.y
        ).standardized
    }

    private func drawHint() {
        let text = "拖拽选择英文区域  ·  Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.midY - size.height / 2 - 8,
            width: size.width + 28,
            height: size.height + 16
        )

        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(
            at: CGPoint(x: rect.minX + 14, y: rect.minY + 8),
            withAttributes: attributes
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: rect.minX,
            y: max(6, rect.minY - size.height - 12),
            width: size.width + 12,
            height: size.height + 6
        )

        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            at: CGPoint(x: labelRect.minX + 6, y: labelRect.minY + 3),
            withAttributes: attributes
        )
    }
}
