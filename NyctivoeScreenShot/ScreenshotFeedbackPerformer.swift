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
    private var activeSound: NSSound?

    func perform(_ preferences: ScreenshotFeedbackPreferences) {
        if preferences.playsSound, preferences.soundVolume > 0 {
            activeSound = NSSound(named: preferences.sound.soundName)
            activeSound?.volume = Float(preferences.soundVolume)
            activeSound?.play()
        }

        if preferences.flashesScreen, preferences.flashDuration > 0 {
            flashScreens(
                intensity: preferences.flashIntensity,
                duration: preferences.flashDuration
            )
        }
    }

    private func flashScreens(
        intensity: ScreenshotFeedbackFlashIntensity,
        duration: TimeInterval
    ) {
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
            window.backgroundColor = NSColor.white.withAlphaComponent(intensity.alpha)
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
                    context.duration = duration
                    window.animator().alphaValue = 0.0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        window.orderOut(nil)
                        self.flashWindows.removeAll { $0 === window }
                    }
                }
            }
        }
    }
}
