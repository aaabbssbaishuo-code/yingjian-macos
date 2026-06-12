import Carbon
import Foundation

enum HotKeyError: Error {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
final class HotKeyManager {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(
        signature: OSType(UInt32(ascii: "QLTR")),
        id: 1
    )

    func registerDefaultHotKey() throws {
        unregister()

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

    func unregister() {
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
