import AppKit
import Carbon
import Foundation
import Testing
@testable import QuickLensTranslator

@Suite("Keyboard shortcut")
struct KeyboardShortcutTests {
    @Test("Default shortcut uses Command Shift T")
    func defaultShortcutUsesCommandShiftT() {
        let shortcut = KeyboardShortcut.defaultShortcut

        #expect(shortcut.keyCode == UInt16(kVK_ANSI_T))
        #expect(shortcut.modifierFlags == [.command, .shift])
        #expect(shortcut.displayString == "⇧⌘T")
        #expect(shortcut.validationMessage == nil)
    }

    @Test("Shortcut requires at least two modifiers")
    func shortcutRequiresAtLeastTwoModifiers() {
        let shortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_Y),
            modifierFlags: [.command],
            keyLabel: "Y"
        )

        #expect(shortcut.validationMessage != nil)
    }

    @Test("Shortcut survives Codable round trip")
    func shortcutCodableRoundTrip() throws {
        let shortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_Y),
            modifierFlags: [.control, .option],
            keyLabel: "Y"
        )

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)

        #expect(decoded == shortcut)
        #expect(decoded.displayString == "⌃⌥Y")
    }

    @Test("Store persists a valid shortcut")
    func storePersistsValidShortcut() {
        let suiteName = "KeyboardShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShortcutStore(defaults: defaults)
        let shortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.command, .option],
            keyLabel: "R"
        )

        store.save(shortcut)

        #expect(store.shortcut == shortcut)
    }

    @Test("Store falls back to default for invalid shortcut")
    func storeFallsBackToDefaultForInvalidShortcut() throws {
        let suiteName = "KeyboardShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ShortcutStore(defaults: defaults)
        let invalidShortcut = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_T),
            modifierFlags: [.command],
            keyLabel: "T"
        )
        let data = try JSONEncoder().encode(invalidShortcut)
        defaults.set(data, forKey: "captureKeyboardShortcut")

        #expect(store.shortcut == .defaultShortcut)
    }
}
