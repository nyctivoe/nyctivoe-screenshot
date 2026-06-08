//
//  ScreenshotFeedbackPerformer.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit

@MainActor
final class ScreenshotFeedbackPerformer {
    private var flashWindows: [NSWindow] = []

    func perform(_ preferences: ScreenshotFeedbackPreferences) {
        if preferences.playsSound {
            NSSound(named: preferences.sound.soundName)?.play()
        }

        if preferences.flashesScreen {
            flashScreens()
        }
    }

    private func flashScreens() {
        flashWindows.forEach { $0.orderOut(nil) }
        flashWindows.removeAll()

        let screens = NSScreen.screens.isEmpty ? NSScreen.main.map { [$0] } ?? [] : NSScreen.screens

        for screen in screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = NSColor.white.withAlphaComponent(0.32)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.level = .screenSaver
            window.alphaValue = 0.0
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()

            flashWindows.append(window)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.06
                window.animator().alphaValue = 1.0
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    window.animator().alphaValue = 0.0
                } completionHandler: { [weak self, weak window] in
                    guard let window else {
                        return
                    }

                    window.orderOut(nil)
                    self?.flashWindows.removeAll { $0 === window }
                }
            }
        }
    }
}
