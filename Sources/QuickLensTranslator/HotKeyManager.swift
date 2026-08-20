import AppKit
import ApplicationServices
import Carbon
import Foundation

struct HotKeyShortcut: Equatable {
    static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: [.command, .shift]
    )

    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags

    var displayName: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    var isValid: Bool {
        let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        return !modifiers.intersection(requiredModifiers).isEmpty
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.supportedModifiers)
    }

    init?(event: NSEvent) {
        let shortcut = HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: event.modifierFlags
        )
        guard shortcut.isValid else { return nil }
        self = shortcut
    }

    func matches(_ event: CGEvent) -> Bool {
        let eventKeyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == keyCode else { return false }
        return event.flags.intersection(Self.supportedCGModifiers) == cgModifiers
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: StorageKey.keyCode)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: StorageKey.modifiers)
    }

    static func load() -> HotKeyShortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: StorageKey.keyCode) != nil,
              defaults.object(forKey: StorageKey.modifiers) != nil else {
            return .default
        }

        let shortcut = HotKeyShortcut(
            keyCode: UInt32(defaults.integer(forKey: StorageKey.keyCode)),
            modifiers: NSEvent.ModifierFlags(
                rawValue: UInt(defaults.integer(forKey: StorageKey.modifiers))
            )
        )
        return shortcut.isValid ? shortcut : .default
    }

    var carbonModifiers: UInt32 {
        var value = 0
        if modifiers.contains(.command) { value |= cmdKey }
        if modifiers.contains(.shift) { value |= shiftKey }
        if modifiers.contains(.option) { value |= optionKey }
        if modifiers.contains(.control) { value |= controlKey }
        return UInt32(value)
    }

    private var cgModifiers: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .command, .shift, .option, .control
    ]

    private static let supportedCGModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl
    ]

    private enum StorageKey {
        static let keyCode = "hotKey.keyCode"
        static let modifiers = "hotKey.modifiers"
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C",
            kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I",
            kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U",
            kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2",
            kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
            kVK_ANSI_9: "9",
            kVK_Space: "空格", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
            kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
            kVK_ANSI_Grave: "`",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        return names[Int(keyCode)] ?? "键码 \(keyCode)"
    }
}

enum HotKeyError: Error {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
final class HotKeyManager {
    var onHotKey: (() -> Void)?
    private(set) var shortcut = HotKeyShortcut.load()

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(
        signature: OSType(UInt32(ascii: "QLTR")),
        id: 1
    )

    func registerCurrentHotKey() throws {
        unregister()
        if installEventTap() { return }
        try registerCarbonHotKey()
    }

    func updateShortcut(_ newShortcut: HotKeyShortcut) throws {
        guard newShortcut.isValid else { return }
        let previousShortcut = shortcut

        unregister()
        shortcut = newShortcut

        do {
            try registerCurrentHotKey()
            newShortcut.save()
        } catch {
            unregister()
            shortcut = previousShortcut
            try? registerCurrentHotKey()
            throw error
        }
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
                      manager.shortcut.matches(event) else {
                    return Unmanaged.passUnretained(event)
                }

                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if !isRepeat {
                    Task { @MainActor in manager.onHotKey?() }
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

                Task { @MainActor in manager.onHotKey?() }
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

        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
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
