import AppKit
import CoreGraphics
import QuartzCore

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
        overlayWindow.onSelection = { [weak self] localRect in
            self?.completeSelection(localRect)
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

    private func completeSelection(_ localRect: CGRect) {
        guard let window else {
            complete(.cancelled)
            return
        }

        let rect = localRect.standardized

        guard rect.width >= 8, rect.height >= 8 else {
            complete(.tooSmall)
            return
        }

        let screenRect = rect.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: screenRect.midX, y: screenRect.midY)) })
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            complete(.cancelled)
            return
        }

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
    private let selectionLayer = CAShapeLayer()
    var onSelection: ((CGRect) -> Void)?

    init(selectionState: ScreenshotOverlayState, desktopFrame: CGRect) {
        self.selectionState = selectionState
        self.desktopFrame = desktopFrame
        super.init(frame: .zero)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.26).cgColor

        if selectionLayer.superlayer == nil {
            selectionLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
            selectionLayer.strokeColor = NSColor.white.cgColor
            selectionLayer.lineWidth = 2.5
            selectionLayer.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
            selectionLayer.shadowOpacity = 1
            selectionLayer.shadowRadius = 8
            selectionLayer.shadowOffset = CGSize(width: 0, height: 2)
            layer?.addSublayer(selectionLayer)
        }

        refreshSelectionLayer()
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
        selectionState.begin(at: localPoint)
        refreshSelectionLayer()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        selectionState.update(at: localPoint)
        refreshSelectionLayer()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        selectionState.update(at: localPoint)
        refreshSelectionLayer()
        needsDisplay = true

        guard let selectionRect = selectionState.selectionRect else { return }
        onSelection?(selectionRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if selectionRect == nil {
            NSColor.black.withAlphaComponent(0.26).setFill()
            bounds.fill()
            drawHint()
        }
    }

    private var selectionRect: CGRect? {
        selectionState.selectionRect?.standardized
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

    private func refreshSelectionLayer() {
        guard let selectionRect else {
            selectionLayer.isHidden = true
            return
        }

        selectionLayer.isHidden = false
        selectionLayer.frame = bounds
        selectionLayer.path = CGPath(
            roundedRect: selectionRect.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: 6,
            cornerHeight: 6,
            transform: nil
        )
    }
}

@MainActor
final class ScreenshotOverlayState {
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

    func begin(at point: CGPoint) {
        startPoint = point
        currentPoint = point
    }

    func update(at point: CGPoint) {
        currentPoint = point
    }

    func reset() {
        startPoint = nil
        currentPoint = nil
    }
}
