import Carbon
import Foundation
import ApplicationServices

enum HotKeyError: Error {
    case eventTapInstallationFailed
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
final class HotKeyManager {
    var onHotKey: (() -> Void)?

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(
        signature: OSType(UInt32(ascii: "QLTR")),
        id: 1
    )

    func registerDefaultHotKey() throws {
        unregister()

        if installEventTap() {
            return
        }

        try registerCarbonHotKey()
    }

    private func installEventTap() -> Bool {
        let eventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = manager.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown,
                      manager.isDefaultShortcut(event) else {
                    return Unmanaged.passUnretained(event)
                }

                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat {
                    Task { @MainActor in
                        manager.onHotKey?()
                    }
                }

                return nil
            },
            userInfo: pointer
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func registerCarbonHotKey() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )

                guard status == noErr else { return status }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                guard pressedID.signature == manager.hotKeyID.signature,
                      pressedID.id == manager.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                Task { @MainActor in
                    manager.onHotKey?()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.eventHandlerInstallationFailed(handlerStatus)
        }

        let modifiers = UInt32(cmdKey | shiftKey)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            unregister()
            throw HotKeyError.registrationFailed(registrationStatus)
        }
    }

    private func isDefaultShortcut(_ event: CGEvent) -> Bool {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == UInt32(kVK_ANSI_T) else { return false }

        let flags = event.flags
        return flags.contains(.maskCommand)
            && flags.contains(.maskShift)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
    }

    func unregister() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

private extension UInt32 {
    init(ascii text: String) {
        self = text.utf8.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}
