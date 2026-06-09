//
//  GlobalShortcutManager.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import Carbon
import Foundation

struct GlobalShortcutRegistrationFailure: Equatable {
    let kind: ScreenshotKind
    let shortcut: ScreenshotKeyboardShortcut
    let status: OSStatus
}

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

    @discardableResult
    func updatePreferences(_ preferences: ScreenshotShortcutPreferences) -> [GlobalShortcutRegistrationFailure] {
        ensureEventHandlerInstalled()
        unregisterHotKeys()

        var failures: [GlobalShortcutRegistrationFailure] = []

        let fullScreenResult = register(
            shortcut: preferences.fullScreenShortcut,
            identifier: HotKeyIdentifier.fullScreen.rawValue
        )
        fullScreenHotKey = fullScreenResult.hotKey
        if let status = fullScreenResult.failureStatus {
            failures.append(
                GlobalShortcutRegistrationFailure(
                    kind: .fullScreen,
                    shortcut: preferences.fullScreenShortcut,
                    status: status
                )
            )
        }

        let partialResult = register(
            shortcut: preferences.partialShortcut,
            identifier: HotKeyIdentifier.partial.rawValue
        )
        partialHotKey = partialResult.hotKey
        if let status = partialResult.failureStatus {
            failures.append(
                GlobalShortcutRegistrationFailure(
                    kind: .partial,
                    shortcut: preferences.partialShortcut,
                    status: status
                )
            )
        }

        return failures
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

    private func register(
        shortcut: ScreenshotKeyboardShortcut,
        identifier: UInt32
    ) -> RegistrationResult {
        guard shortcut.isEnabled else {
            return RegistrationResult(hotKey: nil, failureStatus: nil)
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            return RegistrationResult(hotKey: nil, failureStatus: status)
        }

        return RegistrationResult(hotKey: hotKeyRef, failureStatus: nil)
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

    private struct RegistrationResult {
        let hotKey: EventHotKeyRef?
        let failureStatus: OSStatus?
    }

    private enum HotKeyIdentifier: UInt32 {
        case fullScreen = 1
        case partial = 2
    }
}
