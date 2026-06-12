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
    private var soundCache: [ScreenshotFeedbackSound: NSSound] = [:]
    private var activeSound: NSSound?

    init() {
        ScreenshotFeedbackSound.allCases.forEach { sound in
            _ = preparedSound(for: sound)
        }
    }

    func prepare(_ preferences: ScreenshotFeedbackPreferences) {
        guard preferences.playsSound, preferences.soundVolume > 0 else {
            return
        }

        _ = preparedSound(for: preferences.sound)
    }

    func perform(_ preferences: ScreenshotFeedbackPreferences) {
        if preferences.playsSound, preferences.soundVolume > 0 {
            activeSound = preparedSound(for: preferences.sound)
            activeSound?.stop()
            activeSound?.currentTime = 0
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

    private func preparedSound(for sound: ScreenshotFeedbackSound) -> NSSound? {
        if let cachedSound = soundCache[sound] {
            return cachedSound
        }

        let loadedSound = NSSound(named: sound.soundName)
        loadedSound.map(prime)
        soundCache[sound] = loadedSound
        return loadedSound
    }

    private func prime(_ sound: NSSound) {
        let volume = sound.volume
        sound.volume = 0
        if sound.play() {
            sound.stop()
            sound.currentTime = 0
        }
        sound.volume = volume
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
