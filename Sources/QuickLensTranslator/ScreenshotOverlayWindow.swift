import AppKit
import CoreGraphics

enum ScreenshotSelectionResult {
    case selected(CGRect, NSScreen)
    case tooSmall
    case cancelled
}

@MainActor
final class ScreenshotOverlayController {
    private var windows: [ScreenshotOverlayWindow] = []
    private var completion: ((ScreenshotSelectionResult) -> Void)?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private let selectionState = ScreenshotOverlayState()

    func beginSelection(completion: @escaping (ScreenshotSelectionResult) -> Void) {
        finishWithoutCallback()
        self.completion = completion

        windows = NSScreen.screens.map { screen in
            let window = ScreenshotOverlayWindow(screen: screen, selectionState: selectionState)
            return window
        }

        installEventTap()
        NSCursor.crosshair.push()
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func installEventTap() {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<ScreenshotOverlayController>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = controller.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                Task { @MainActor in
                    controller.handleCapturedEvent(type: type, event: event)
                }
                return nil
            },
            userInfo: pointer
        ) else {
            ToastPresenter.show(message: "需要开启辅助功能或输入监控权限。")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleCapturedEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                complete(.cancelled)
            }
        case .leftMouseDown:
            startSelection(at: event.location)
        case .leftMouseDragged:
            updateSelection(at: event.location)
        case .leftMouseUp:
            finishSelection(at: event.location)
        default:
            break
        }
    }

    private func startSelection(at point: CGPoint) {
        guard let screen = screen(containing: point) else { return }
        selectionState.begin(at: point, on: screen)
        refreshWindows()
    }

    private func updateSelection(at point: CGPoint) {
        guard selectionState.isSelecting else { return }
        selectionState.update(at: point)
        refreshWindows()
    }

    private func finishSelection(at point: CGPoint) {
        guard selectionState.isSelecting else { return }
        selectionState.update(at: point)

        guard let screen = selectionState.activeScreen,
              let rect = selectionState.selectionRect else {
            complete(.cancelled)
            return
        }

        guard rect.width >= 8, rect.height >= 8 else {
            complete(.tooSmall)
            return
        }

        complete(.selected(rect, screen))
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func refreshWindows() {
        windows.forEach { $0.contentView?.needsDisplay = true }
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
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
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
    private let selectionState: ScreenshotOverlayState

    init(screen: NSScreen, selectionState: ScreenshotOverlayState) {
        targetScreen = screen
        self.selectionState = selectionState
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = ScreenshotSelectionView(selectionState: selectionState, screen: screen)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ScreenshotSelectionView: NSView {
    private let selectionState: ScreenshotOverlayState
    private let screen: NSScreen

    init(selectionState: ScreenshotOverlayState, screen: NSScreen) {
        self.selectionState = selectionState
        self.screen = screen
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        guard selectionState.activeScreen === screen,
              let selectionRect = selectionState.selectionRect else {
            return nil
        }
        return CGRect(
            x: selectionRect.minX - screen.frame.minX,
            y: selectionRect.minY - screen.frame.minY,
            width: selectionRect.width,
            height: selectionRect.height
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
