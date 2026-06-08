//
//  ScreenshotController.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit
import Carbon
import Combine
import Foundation

@MainActor
final class ScreenshotController: ObservableObject {
    @Published private(set) var hasScreenRecordingPermission: Bool
    @Published private(set) var isCapturing = false
    @Published private(set) var recentCaptures: [ScreenshotRecord] = []
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var recordingShortcutKind: ScreenshotKind?
    @Published var namingPreferences: ScreenshotNamingPreferences {
        didSet {
            guard oldValue != namingPreferences else {
                return
            }

            storage.namingPreferences = namingPreferences
            Self.saveNamingPreferences(namingPreferences)
        }
    }
    @Published var shortcutPreferences: ScreenshotShortcutPreferences {
        didSet {
            guard oldValue != shortcutPreferences else {
                return
            }

            Self.saveShortcutPreferences(shortcutPreferences)
            shortcutManager.updatePreferences(shortcutPreferences)
        }
    }
    @Published var feedbackPreferences: ScreenshotFeedbackPreferences {
        didSet {
            guard oldValue != feedbackPreferences else {
                return
            }

            Self.saveFeedbackPreferences(feedbackPreferences)
        }
    }

    private let captureService = ScreenshotCaptureService()
    private let storage: ScreenshotStorage
    private let partialOverlay = PartialScreenshotOverlayController()
    private let shortcutManager = GlobalShortcutManager()
    private let feedbackPerformer = ScreenshotFeedbackPerformer()
    private let previewPanelController = ScreenshotPreviewPanelController()
    private var shortcutEventMonitor: Any?
    private var recentCapturesSyncTask: Task<Void, Never>?

    var screenshotsFolderURL: URL {
        storage.folderURL
    }

    var namingPreviewFileName: String {
        storage.previewFileName(for: .fullScreen)
    }

    init() {
        let savedNamingPreferences = Self.loadNamingPreferences()
        let savedShortcutPreferences = Self.loadShortcutPreferences()
        let savedFeedbackPreferences = Self.loadFeedbackPreferences()
        storage = ScreenshotStorage(namingPreferences: savedNamingPreferences)
        namingPreferences = savedNamingPreferences
        shortcutPreferences = savedShortcutPreferences
        feedbackPreferences = savedFeedbackPreferences
        hasScreenRecordingPermission = captureService.hasScreenRecordingPermission

        shortcutManager.onFullScreenShortcut = { [weak self] in
            self?.captureFullScreen()
        }
        shortcutManager.onPartialShortcut = { [weak self] in
            self?.capturePartialScreen()
        }
        shortcutManager.updatePreferences(savedShortcutPreferences)

        do {
            try storage.ensureFolderExists()
            recentCaptures = storage.loadRecentCaptures()
            startRecentCapturesSync()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    deinit {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
        }

        recentCapturesSyncTask?.cancel()
    }

    func refreshPermissionStatus() {
        hasScreenRecordingPermission = captureService.hasScreenRecordingPermission
    }

    func requestScreenRecordingPermission() {
        let granted = captureService.requestScreenRecordingPermission()
        hasScreenRecordingPermission = granted || captureService.hasScreenRecordingPermission
        statusMessage = hasScreenRecordingPermission
            ? "Screen Recording permission granted."
            : "Enable Screen Recording permission in System Settings."
    }

    func captureFullScreen() {
        guard beginCapture() else {
            return
        }

        let focusRestorer = ActiveApplicationRestorer()

        Task {
            defer {
                finishCapture()
                focusRestorer.restore()
            }

            do {
                let image = try await captureService.captureMainDisplay()
                let record = try storage.save(image, kind: .fullScreen)
                remember(record)
                feedbackPerformer.perform(feedbackPreferences)
                statusMessage = "Saved \(record.fileName)"
            } catch {
                handle(error)
            }
        }
    }

    func capturePartialScreen() {
        guard !isCapturing else {
            return
        }

        refreshPermissionStatus()
        guard hasScreenRecordingPermission else {
            statusMessage = "Screen Recording permission is required."
            requestScreenRecordingPermission()
            return
        }

        let focusRestorer = ActiveApplicationRestorer()
        statusMessage = "Select an area."
        partialOverlay.begin { [weak self] selection in
            guard let self else {
                focusRestorer.restore()
                return
            }

            guard let selection else {
                statusMessage = "Partial screenshot cancelled."
                focusRestorer.restore()
                return
            }

            feedbackPerformer.perform(feedbackPreferences)
            capturePartial(rect: selection.captureRect, focusRestorer: focusRestorer)
        }
    }

    func openScreenshotsFolder() {
        do {
            try storage.ensureFolderExists()
            NSWorkspace.shared.open(storage.folderURL)
        } catch {
            handle(error)
        }
    }

    func reveal(_ record: ScreenshotRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.url])
    }

    func open(_ record: ScreenshotRecord) {
        NSWorkspace.shared.open(record.url)
    }

    func resetNamingPreferences() {
        namingPreferences = .default
    }

    func resetShortcutPreferences() {
        shortcutPreferences = .default
    }

    func startRecordingShortcut(for kind: ScreenshotKind) {
        stopRecordingShortcut()
        recordingShortcutKind = kind
        statusMessage = "Press the new \(kind.rawValue.lowercased()) shortcut."

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.completeShortcutRecording(with: event)
            }

            return nil
        }
    }

    private func capturePartial(rect: CGRect, focusRestorer: ActiveApplicationRestorer) {
        guard beginCapture() else {
            focusRestorer.restore()
            return
        }

        Task {
            defer {
                finishCapture()
                focusRestorer.restore()
            }

            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                let image = try await captureService.capture(rect: rect)
                let record = try storage.save(image, kind: .partial)
                remember(record)
                statusMessage = "Saved \(record.fileName)"
            } catch {
                handle(error)
            }
        }
    }

    private func beginCapture() -> Bool {
        guard !isCapturing else {
            return false
        }

        refreshPermissionStatus()
        guard hasScreenRecordingPermission else {
            statusMessage = "Screen Recording permission is required."
            requestScreenRecordingPermission()
            return false
        }

        isCapturing = true
        statusMessage = "Capturing..."
        return true
    }

    private func finishCapture() {
        isCapturing = false
        refreshPermissionStatus()
    }

    private func remember(_ record: ScreenshotRecord) {
        recentCaptures.insert(record, at: 0)
        if recentCaptures.count > 8 {
            recentCaptures.removeLast(recentCaptures.count - 8)
        }

        storage.saveRecentCaptures(recentCaptures)
        previewPanelController.show(record: record)
    }

    private func startRecentCapturesSync() {
        recentCapturesSyncTask?.cancel()
        recentCapturesSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }

                self?.syncRecentCapturesFromDisk()
            }
        }
    }

    private func syncRecentCapturesFromDisk() {
        let syncedCaptures = storage.reconciledRecentCaptures()
        guard syncedCaptures != recentCaptures else {
            return
        }

        recentCaptures = syncedCaptures
    }

    private func handle(_ error: Error) {
        statusMessage = error.localizedDescription
    }

    private func completeShortcutRecording(with event: NSEvent) {
        guard let recordingShortcutKind else {
            stopRecordingShortcut()
            return
        }

        if event.keyCode == 53 {
            stopRecordingShortcut()
            statusMessage = "Shortcut recording cancelled."
            return
        }

        guard let shortcut = ScreenshotKeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: Self.carbonModifiers(from: event.modifierFlags)
        ) else {
            statusMessage = "Use at least one modifier key."
            return
        }

        switch recordingShortcutKind {
        case .fullScreen:
            shortcutPreferences.fullScreenShortcut = shortcut
        case .partial:
            shortcutPreferences.partialShortcut = shortcut
        }

        stopRecordingShortcut()
        statusMessage = "Shortcut updated to \(shortcut.displayText)."
    }

    private func stopRecordingShortcut() {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
            self.shortcutEventMonitor = nil
        }

        recordingShortcutKind = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }

        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }

        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }

        return modifiers
    }

    private static func loadNamingPreferences() -> ScreenshotNamingPreferences {
        let defaults = UserDefaults.standard
        let defaultPreferences = ScreenshotNamingPreferences.default
        let prefix = defaults.string(forKey: UserDefaultsKey.namePrefix) ?? defaultPreferences.prefix
        let timestampStyle = defaults
            .string(forKey: UserDefaultsKey.timestampStyle)
            .flatMap(ScreenshotTimestampStyle.init(rawValue:))
        ?? defaultPreferences.timestampStyle

        return ScreenshotNamingPreferences(
            prefix: prefix,
            timestampStyle: timestampStyle,
            includesCaptureKind: defaults.object(forKey: UserDefaultsKey.includesCaptureKind) as? Bool
            ?? defaultPreferences.includesCaptureKind
        )
    }

    private static func saveNamingPreferences(_ preferences: ScreenshotNamingPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.prefix, forKey: UserDefaultsKey.namePrefix)
        defaults.set(preferences.timestampStyle.rawValue, forKey: UserDefaultsKey.timestampStyle)
        defaults.set(preferences.includesCaptureKind, forKey: UserDefaultsKey.includesCaptureKind)
    }

    private static func loadShortcutPreferences() -> ScreenshotShortcutPreferences {
        let defaults = UserDefaults.standard
        let defaultPreferences = ScreenshotShortcutPreferences.default

        return ScreenshotShortcutPreferences(
            fullScreenShortcut: loadShortcut(
                keyCodeKey: UserDefaultsKey.fullScreenShortcutKeyCode,
                modifiersKey: UserDefaultsKey.fullScreenShortcutModifiers,
                defaultValue: defaultPreferences.fullScreenShortcut,
                defaults: defaults
            ),
            partialShortcut: loadShortcut(
                keyCodeKey: UserDefaultsKey.partialShortcutKeyCode,
                modifiersKey: UserDefaultsKey.partialShortcutModifiers,
                defaultValue: defaultPreferences.partialShortcut,
                defaults: defaults
            )
        )
    }

    private static func loadShortcut(
        keyCodeKey: String,
        modifiersKey: String,
        defaultValue: ScreenshotKeyboardShortcut,
        defaults: UserDefaults
    ) -> ScreenshotKeyboardShortcut {
        let keyCode = UInt32(defaults.integer(forKey: keyCodeKey))
        let modifierRawValue = UInt32(defaults.integer(forKey: modifiersKey))
        let modifiers = ScreenshotShortcutModifiers(rawValue: modifierRawValue)
        let shortcut = ScreenshotKeyboardShortcut(keyCode: keyCode, modifiers: modifiers)

        return shortcut.isEnabled ? shortcut : defaultValue
    }

    private static func saveShortcutPreferences(_ preferences: ScreenshotShortcutPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(Int(preferences.fullScreenShortcut.keyCode), forKey: UserDefaultsKey.fullScreenShortcutKeyCode)
        defaults.set(Int(preferences.fullScreenShortcut.modifiers.rawValue), forKey: UserDefaultsKey.fullScreenShortcutModifiers)
        defaults.set(Int(preferences.partialShortcut.keyCode), forKey: UserDefaultsKey.partialShortcutKeyCode)
        defaults.set(Int(preferences.partialShortcut.modifiers.rawValue), forKey: UserDefaultsKey.partialShortcutModifiers)
    }

    private static func loadFeedbackPreferences() -> ScreenshotFeedbackPreferences {
        let defaults = UserDefaults.standard
        let defaultPreferences = ScreenshotFeedbackPreferences.default
        let sound = defaults
            .string(forKey: UserDefaultsKey.feedbackSound)
            .flatMap(ScreenshotFeedbackSound.init(rawValue:))
        ?? defaultPreferences.sound
        let flashIntensity = defaults
            .string(forKey: UserDefaultsKey.feedbackFlashIntensity)
            .flatMap(ScreenshotFeedbackFlashIntensity.init(rawValue:))
        ?? defaultPreferences.flashIntensity
        let flashDuration = defaults
            .string(forKey: UserDefaultsKey.feedbackFlashDuration)
            .flatMap(ScreenshotFeedbackFlashDuration.init(rawValue:))
        ?? defaultPreferences.flashDuration

        return ScreenshotFeedbackPreferences(
            playsSound: defaults.object(forKey: UserDefaultsKey.feedbackPlaysSound) as? Bool
            ?? defaultPreferences.playsSound,
            flashesScreen: defaults.object(forKey: UserDefaultsKey.feedbackFlashesScreen) as? Bool
            ?? defaultPreferences.flashesScreen,
            sound: sound,
            flashIntensity: flashIntensity,
            flashDuration: flashDuration
        )
    }

    private static func saveFeedbackPreferences(_ preferences: ScreenshotFeedbackPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.playsSound, forKey: UserDefaultsKey.feedbackPlaysSound)
        defaults.set(preferences.flashesScreen, forKey: UserDefaultsKey.feedbackFlashesScreen)
        defaults.set(preferences.sound.rawValue, forKey: UserDefaultsKey.feedbackSound)
        defaults.set(preferences.flashIntensity.rawValue, forKey: UserDefaultsKey.feedbackFlashIntensity)
        defaults.set(preferences.flashDuration.rawValue, forKey: UserDefaultsKey.feedbackFlashDuration)
    }

    private enum UserDefaultsKey {
        static let namePrefix = "screenshotNamePrefix"
        static let timestampStyle = "screenshotTimestampStyle"
        static let includesCaptureKind = "screenshotIncludesCaptureKind"
        static let fullScreenShortcutKeyCode = "fullScreenShortcutKeyCode"
        static let fullScreenShortcutModifiers = "fullScreenShortcutModifiers"
        static let partialShortcutKeyCode = "partialShortcutKeyCode"
        static let partialShortcutModifiers = "partialShortcutModifiers"
        static let feedbackPlaysSound = "screenshotFeedbackPlaysSound"
        static let feedbackFlashesScreen = "screenshotFeedbackFlashesScreen"
        static let feedbackSound = "screenshotFeedbackSound"
        static let feedbackFlashIntensity = "screenshotFeedbackFlashIntensity"
        static let feedbackFlashDuration = "screenshotFeedbackFlashDuration"
    }
}

private struct ActiveApplicationRestorer {
    private let application: NSRunningApplication?

    init() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        application = frontmostApplication?.processIdentifier == currentProcessIdentifier
            ? nil
            : frontmostApplication
    }

    func restore() {
        application?.activate(options: [])
    }
}
