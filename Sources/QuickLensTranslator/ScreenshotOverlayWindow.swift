import AppKit
import CoreGraphics

enum ScreenshotSelectionResult {
    case selected(CGRect, NSScreen)
    case tooSmall
    case cancelled
}

@MainActor
final class ScreenshotOverlayController {
    private var window: ScreenshotOverlayWindow?
    private var completion: ((ScreenshotSelectionResult) -> Void)?
    private var escapeMonitor: Any?
    private let selectionState = ScreenshotOverlayState()

    func beginSelection(completion: @escaping (ScreenshotSelectionResult) -> Void) {
        finishWithoutCallback()
        self.completion = completion

        let desktopFrame = Self.virtualDesktopFrame()
        let overlayWindow = ScreenshotOverlayWindow(
            desktopFrame: desktopFrame,
            selectionState: selectionState
        )
        overlayWindow.onSelection = { [weak self] globalRect in
            self?.completeSelection(globalRect)
        }
        window = overlayWindow

        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.complete(.cancelled)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        overlayWindow.orderFrontRegardless()
        overlayWindow.makeKeyAndOrderFront(nil)
    }

    private func complete(_ result: ScreenshotSelectionResult) {
        let callback = completion
        finishWithoutCallback()
        callback?(result)
    }

    private func completeSelection(_ globalRect: CGRect) {
        let rect = globalRect.standardized

        guard rect.width >= 8, rect.height >= 8 else {
            complete(.tooSmall)
            return
        }

        let screen = selectionState.activeScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            complete(.cancelled)
            return
        }

        let screenRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
        complete(.selected(screenRect, screen))
    }

    private func finishWithoutCallback() {
        if window != nil {
            NSCursor.pop()
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        selectionState.reset()
        window?.orderOut(nil)
        window = nil
        completion = nil
    }

    private static func virtualDesktopFrame() -> CGRect {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return .zero
        }

        return screens.dropFirst().reduce(first.frame) { partial, screen in
            partial.union(screen.frame)
        }
    }
}

@MainActor
final class ScreenshotOverlayWindow: NSPanel {
    private let selectionState: ScreenshotOverlayState
    private let desktopFrame: CGRect
    var onSelection: ((CGRect) -> Void)?

    init(desktopFrame: CGRect, selectionState: ScreenshotOverlayState) {
        self.selectionState = selectionState
        self.desktopFrame = desktopFrame
        super.init(
            contentRect: desktopFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false

        let selectionView = ScreenshotSelectionView(
            selectionState: selectionState,
            desktopFrame: desktopFrame
        )
        selectionView.frame = CGRect(origin: .zero, size: desktopFrame.size)
        selectionView.autoresizingMask = [.width, .height]
        selectionView.onSelection = { [weak self] rect in
            self?.onSelection?(rect)
        }
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenshotSelectionView: NSView {
    private let selectionState: ScreenshotOverlayState
    private let desktopFrame: CGRect
    var onSelection: ((CGRect) -> Void)?

    init(selectionState: ScreenshotOverlayState, desktopFrame: CGRect) {
        self.selectionState = selectionState
        self.desktopFrame = desktopFrame
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = toGlobalPoint(localPoint)
        selectionState.begin(at: globalPoint, on: screenContaining(globalPoint))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        selectionState.update(at: toGlobalPoint(localPoint))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        selectionState.update(at: toGlobalPoint(localPoint))
        needsDisplay = true

        guard let selectionRect = selectionState.selectionRect else { return }
        onSelection?(selectionRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.26).setFill()
        bounds.fill()

        guard let selectionRect = selectionRect else {
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
        guard let selectionRect = selectionState.selectionRect else {
            return nil
        }
        return CGRect(
            x: selectionRect.minX - desktopFrame.minX,
            y: selectionRect.minY - desktopFrame.minY,
            width: selectionRect.width,
            height: selectionRect.height
        ).standardized
    }

    private func toGlobalPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + desktopFrame.minX, y: point.y + desktopFrame.minY)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
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

@MainActor
final class ScreenshotOverlayState {
    private(set) var activeScreen: NSScreen?
    private(set) var startPoint: CGPoint?
    private(set) var currentPoint: CGPoint?

    var isSelecting: Bool {
        startPoint != nil && currentPoint != nil
    }

    var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: startPoint.x,
            y: startPoint.y,
            width: currentPoint.x - startPoint.x,
            height: currentPoint.y - startPoint.y
        ).standardized
    }

    func begin(at point: CGPoint, on screen: NSScreen) {
        activeScreen = screen
        startPoint = point
        currentPoint = point
    }

    func update(at point: CGPoint) {
        currentPoint = point
    }

    func reset() {
        activeScreen = nil
        startPoint = nil
        currentPoint = nil
    }
}
