//
//  GlobalShortcutManager.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import Carbon
import Foundation

@MainActor
final class GlobalShortcutManager {
    var onFullScreenShortcut: (() -> Void)?
    var onPartialShortcut: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var fullScreenHotKey: EventHotKeyRef?
    private var partialHotKey: EventHotKeyRef?

    deinit {
        unregisterHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func updatePreferences(_ preferences: ScreenshotShortcutPreferences) {
        ensureEventHandlerInstalled()
        unregisterHotKeys()

        fullScreenHotKey = register(
            shortcut: preferences.fullScreenShortcut,
            identifier: HotKeyIdentifier.fullScreen.rawValue
        )
        partialHotKey = register(
            shortcut: preferences.partialShortcut,
            identifier: HotKeyIdentifier.partial.rawValue
        )
    }

    private func ensureEventHandlerInstalled() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else {
                    return status
                }

                let manager = Unmanaged<GlobalShortcutManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    manager.handleHotKey(identifier: hotKeyID.id)
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func register(shortcut: ScreenshotKeyboardShortcut, identifier: UInt32) -> EventHotKeyRef? {
        guard shortcut.isEnabled else {
            return nil
        }

        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        return status == noErr ? hotKeyRef : nil
    }

    private func unregisterHotKeys() {
        if let fullScreenHotKey {
            UnregisterEventHotKey(fullScreenHotKey)
            self.fullScreenHotKey = nil
        }

        if let partialHotKey {
            UnregisterEventHotKey(partialHotKey)
            self.partialHotKey = nil
        }
    }

    private func handleHotKey(identifier: UInt32) {
        switch HotKeyIdentifier(rawValue: identifier) {
        case .fullScreen:
            onFullScreenShortcut?()
        case .partial:
            onPartialShortcut?()
        case nil:
            break
        }
    }

    private static let signature: OSType = 0x4E535348

    private enum HotKeyIdentifier: UInt32 {
        case fullScreen = 1
        case partial = 2
    }
}
