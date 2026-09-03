import AppKit
import Carbon
import CoreGraphics

struct KeyboardShortcut: Codable, Equatable {
    static let defaultShortcut = KeyboardShortcut(
        keyCode: UInt16(kVK_ANSI_T),
        modifierFlags: [.command, .shift],
        keyLabel: "T"
    )

    let keyCode: UInt16
    private let modifierRawValue: UInt
    let keyLabel: String

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        modifierRawValue = modifierFlags
            .intersection(Self.supportedModifiers)
            .rawValue
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown,
              !Self.modifierKeyCodes.contains(event.keyCode),
              let keyLabel = Self.keyLabel(
                for: event.keyCode,
                fallback: event.charactersIgnoringModifiers
              ) else {
            return nil
        }

        self.init(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            keyLabel: keyLabel
        )
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
            .intersection(Self.supportedModifiers)
    }

    var displayString: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘")
        ]
        return symbols
            .filter { modifierFlags.contains($0.0) }
            .map(\.1)
            .joined() + keyLabel
    }

    var accessibilityDescription: String {
        let names: [(NSEvent.ModifierFlags, String)] = [
            (.control, "Control"),
            (.option, "Option"),
            (.shift, "Shift"),
            (.command, "Command")
        ]
        return (names
            .filter { modifierFlags.contains($0.0) }
            .map(\.1) + [keyLabel])
            .joined(separator: " + ")
    }

    var validationMessage: String? {
        let modifierCount = [
            NSEvent.ModifierFlags.control,
            .option,
            .shift,
            .command
        ].filter { modifierFlags.contains($0) }.count

        guard modifierCount >= 2 else {
            return "请至少组合两个修饰键，避免影响正常键盘输入。"
        }
        guard keyCode != UInt16(kVK_Escape) else {
            return "Esc 用于取消操作，不能设为截图快捷键。"
        }
        return nil
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    func matches(_ event: CGEvent) -> Bool {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == keyCode else { return false }

        let supportedEventFlags = event.flags.intersection([
            .maskCommand,
            .maskShift,
            .maskAlternate,
            .maskControl
        ])
        return supportedEventFlags == cgEventFlags
    }

    private var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if modifierFlags.contains(.command) { result.insert(.maskCommand) }
        if modifierFlags.contains(.shift) { result.insert(.maskShift) }
        if modifierFlags.contains(.option) { result.insert(.maskAlternate) }
        if modifierFlags.contains(.control) { result.insert(.maskControl) }
        return result
    }

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .control,
        .option,
        .shift,
        .command
    ]

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock),
        UInt16(kVK_Function)
    ]

    private static func keyLabel(for keyCode: UInt16, fallback: String?) -> String? {
        if let known = knownKeyLabels[keyCode] {
            return known
        }

        let fallback = fallback?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let fallback, !fallback.isEmpty else { return nil }
        return fallback
    }

    private static let knownKeyLabels: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Equal): "=", UInt16(kVK_ANSI_Minus): "-",
        UInt16(kVK_ANSI_RightBracket): "]", UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Grave): "`",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "Home", UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up", UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]
}

final class ShortcutStore {
    private let defaults: UserDefaults
    private let storageKey = "captureKeyboardShortcut"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcut: KeyboardShortcut {
        guard let data = defaults.data(forKey: storageKey),
              let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
              shortcut.validationMessage == nil else {
            return .defaultShortcut
        }
        return shortcut
    }

    func save(_ shortcut: KeyboardShortcut) {
        guard shortcut.validationMessage == nil,
              let data = try? JSONEncoder().encode(shortcut) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
