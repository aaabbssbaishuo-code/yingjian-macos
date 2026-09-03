import AppKit
import CoreGraphics

enum ScreenshotSelectionResult {
    case selected(CGRect, NSScreen, CGImage?)
    case tooSmall
    case cancelled
}

@MainActor
final class ScreenshotOverlayController {
    private var windows: [ScreenshotOverlayWindow] = []
    private var completion: ((ScreenshotSelectionResult) -> Void)?
    private var keyboardMonitor: Any?
    private var localKeyboardMonitor: Any?
    private let selectionState = ScreenshotOverlayState()

    func beginSelection(
        snapshots: [CGDirectDisplayID: ScreenSnapshot] = [:],
        completion: @escaping (ScreenshotSelectionResult) -> Void
    ) {
        finishWithoutCallback()
        self.completion = completion

        windows = NSScreen.screens.map { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
            let snapshot = displayID.flatMap { snapshots[$0] }
            let window = ScreenshotOverlayWindow(
                screen: screen,
                selectionState: selectionState,
                snapshot: snapshot
            )
            window.onSelection = { [weak self] localRect in
                self?.completeSelection(localRect, from: window)
            }
            return window
        }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyboardEvent(event)
            }
        }
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == 49 || event.keyCode == 53 else { return event }
            Task { @MainActor in
                self?.handleKeyboardEvent(event)
            }
            return nil
        }

        NSCursor.crosshair.push()
        windows.forEach {
            $0.orderFrontRegardless()
        }
    }

    private func complete(_ result: ScreenshotSelectionResult) {
        let callback = completion
        finishWithoutCallback()
        callback?(result)
    }

    private func handleKeyboardEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            complete(.cancelled)
        } else if event.keyCode == 49, !event.isARepeat {
            windows.forEach { window in
                window.setMovingSelection(event.type == .keyDown)
            }
        }
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
        complete(.selected(
            screenRect,
            window.targetScreen,
            window.snapshot?.cropping(to: screenRect)
        ))
    }

    private func finishWithoutCallback() {
        if !windows.isEmpty {
            NSCursor.pop()
        }
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let localKeyboardMonitor {
            NSEvent.removeMonitor(localKeyboardMonitor)
            self.localKeyboardMonitor = nil
        }
        selectionState.reset()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion = nil
    }
}

@MainActor
final class ScreenshotOverlayWindow: NSPanel {
    let targetScreen: NSScreen
    let snapshot: ScreenSnapshot?
    private let selectionState: ScreenshotOverlayState
    private let selectionView: ScreenshotSelectionView
    var onSelection: ((CGRect) -> Void)?

    init(screen: NSScreen, selectionState: ScreenshotOverlayState, snapshot: ScreenSnapshot?) {
        targetScreen = screen
        self.snapshot = snapshot
        self.selectionState = selectionState
        selectionView = ScreenshotSelectionView(
            selectionState: selectionState,
            screen: screen,
            snapshotImage: snapshot?.image
        )
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false

        selectionView.frame = CGRect(origin: .zero, size: screen.frame.size)
        selectionView.autoresizingMask = [.width, .height]
        selectionView.onSelection = { [weak self] rect in
            self?.onSelection?(rect)
        }
        contentView = selectionView
    }

    func setMovingSelection(_ isMoving: Bool) {
        selectionView.setMovingSelection(isMoving)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenshotSelectionView: NSView {
    private let selectionState: ScreenshotOverlayState
    private let screen: NSScreen
    private let frozenImage: NSImage?
    var onSelection: ((CGRect) -> Void)?

    init(selectionState: ScreenshotOverlayState, screen: NSScreen, snapshotImage: CGImage?) {
        self.selectionState = selectionState
        self.screen = screen
        frozenImage = snapshotImage.map { image in
            NSImage(cgImage: image, size: screen.frame.size)
        }
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
        let point = convert(event.locationInWindow, from: nil)
        selectionState.begin(at: point, on: screen, within: bounds)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionState.update(at: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionState.update(at: point)
        selectionState.setMoving(false)
        NSCursor.crosshair.set()
        needsDisplay = true

        guard let selectionRect = selectionState.selectionRect else { return }
        onSelection?(selectionRect)
    }

    func setMovingSelection(_ isMoving: Bool) {
        guard selectionState.activeScreen === screen,
              selectionState.isSelecting else { return }
        selectionState.setMoving(isMoving)
        (isMoving ? NSCursor.closedHand : NSCursor.crosshair).set()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        frozenImage?.draw(in: bounds)

        NSColor.black.withAlphaComponent(0.26).setFill()
        bounds.fill()

        guard let selectionRect = selectionRect else {
            drawHint()
            return
        }

        if let frozenImage {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selectionRect).addClip()
            frozenImage.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            selectionRect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()

        drawSizeLabel(for: selectionRect)
    }

    private var selectionRect: CGRect? {
        guard selectionState.activeScreen === screen,
              let selectionRect = selectionState.selectionRect else {
            return nil
        }
        return selectionRect.standardized
    }

    private func drawHint() {
        let text = "拖拽选择英文区域  ·  按住空格移动  ·  Esc 取消"
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

struct ScreenSnapshot {
    let screen: NSScreen
    let image: CGImage

    func cropping(to rect: CGRect) -> CGImage? {
        let scale = CGFloat(image.width) / screen.frame.width
        let cropRect = CGRect(
            x: (rect.minX - screen.frame.minX) * scale,
            y: (screen.frame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        return image.cropping(to: cropRect)
    }
}

@MainActor
final class ScreenshotOverlayState {
    private(set) var activeScreen: NSScreen?
    private(set) var startPoint: CGPoint?
    private(set) var currentPoint: CGPoint?
    private(set) var isMoving = false
    private var selectionBounds: CGRect?
    private var moveReferencePoint: CGPoint?
    private var moveStartPoint: CGPoint?
    private var moveCurrentPoint: CGPoint?

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

    func begin(at point: CGPoint, on screen: NSScreen, within bounds: CGRect) {
        activeScreen = screen
        selectionBounds = bounds
        let clampedPoint = clamp(point, to: bounds)
        startPoint = clampedPoint
        currentPoint = clampedPoint
        isMoving = false
    }

    func update(at point: CGPoint) {
        guard let bounds = selectionBounds else {
            currentPoint = point
            return
        }
        let clampedPoint = clamp(point, to: bounds)
        guard isMoving,
              let moveReferencePoint,
              let moveStartPoint,
              let moveCurrentPoint else {
            currentPoint = clampedPoint
            return
        }

        let originalRect = CGRect(
            x: moveStartPoint.x,
            y: moveStartPoint.y,
            width: moveCurrentPoint.x - moveStartPoint.x,
            height: moveCurrentPoint.y - moveStartPoint.y
        ).standardized
        var deltaX = clampedPoint.x - moveReferencePoint.x
        var deltaY = clampedPoint.y - moveReferencePoint.y
        deltaX = min(max(deltaX, bounds.minX - originalRect.minX), bounds.maxX - originalRect.maxX)
        deltaY = min(max(deltaY, bounds.minY - originalRect.minY), bounds.maxY - originalRect.maxY)

        let delta = CGPoint(x: deltaX, y: deltaY)
        startPoint = CGPoint(x: moveStartPoint.x + delta.x, y: moveStartPoint.y + delta.y)
        currentPoint = CGPoint(x: moveCurrentPoint.x + delta.x, y: moveCurrentPoint.y + delta.y)
    }

    func setMoving(_ moving: Bool) {
        guard moving != isMoving else { return }
        guard isSelecting else {
            isMoving = false
            return
        }

        isMoving = moving
        if moving {
            moveReferencePoint = currentPoint
            moveStartPoint = startPoint
            moveCurrentPoint = currentPoint
        } else {
            moveReferencePoint = nil
            moveStartPoint = nil
            moveCurrentPoint = nil
        }
    }

    func reset() {
        activeScreen = nil
        startPoint = nil
        currentPoint = nil
        selectionBounds = nil
        isMoving = false
        moveReferencePoint = nil
        moveStartPoint = nil
        moveCurrentPoint = nil
    }

    private func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
