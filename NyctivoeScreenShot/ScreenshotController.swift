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
    private static let supabaseCredentialStore = LocalCredentialStore(
        service: "\(Bundle.main.bundleIdentifier ?? "NyctivoeScreenShot").supabase"
    )

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
    @Published var storagePreferences: ScreenshotStoragePreferences {
        didSet {
            guard oldValue != storagePreferences else {
                return
            }

            storage.storagePreferences = storagePreferences
            Self.saveStoragePreferences(storagePreferences)
            recentCaptures = storage.loadRecentCaptures()
        }
    }
    @Published var shortcutPreferences: ScreenshotShortcutPreferences {
        didSet {
            guard oldValue != shortcutPreferences else {
                return
            }

            Self.saveShortcutPreferences(shortcutPreferences)
            shortcutRegistrationFailures = applyShortcutPreferences(shortcutPreferences)
        }
    }
    @Published var feedbackPreferences: ScreenshotFeedbackPreferences {
        didSet {
            guard oldValue != feedbackPreferences else {
                return
            }

            Self.saveFeedbackPreferences(feedbackPreferences)
            feedbackPerformer.prepare(feedbackPreferences)
        }
    }
    @Published var previewPreferences: ScreenshotPreviewPreferences {
        didSet {
            guard oldValue != previewPreferences else {
                return
            }

            Self.savePreviewPreferences(previewPreferences)
        }
    }
    @Published var automationPreferences: ScreenshotAutomationPreferences {
        didSet {
            guard oldValue != automationPreferences else {
                return
            }

            Self.saveAutomationPreferences(automationPreferences)
        }
    }

    private let captureService = ScreenshotCaptureService()
    private let storage: ScreenshotStorage
    private let partialOverlay = PartialScreenshotOverlayController()
    private let shortcutManager = GlobalShortcutManager()
    private let feedbackPerformer = ScreenshotFeedbackPerformer()
    private let previewPanelController = ScreenshotPreviewPanelController()
    private var shortcutEventMonitor: Any?
    private var shortcutRegistrationFailures: [GlobalShortcutRegistrationFailure] = []
    private var recentCapturesSyncTask: Task<Void, Never>?
    private var captureWarmUpTask: Task<Void, Never>?
    private var didWarmCapturePipeline = false

    var screenshotsFolderURL: URL {
        storage.folderURL
    }

    var namingPreviewFileName: String {
        storage.previewFileName(for: .fullScreen)
    }

    private var automationHandlers: ScreenshotAutomationHandlers {
        ScreenshotAutomationHandlers(
            deleteCurrentScreenshot: { [weak self] record in
                guard let self else {
                    return
                }

                try self.deleteCurrentScreenshot(record)
            },
            closePreviewPanel: { [weak self] in
                self?.previewPanelController.close()
            }
        )
    }

    init() {
        let savedNamingPreferences = Self.loadNamingPreferences()
        let savedStoragePreferences = Self.loadStoragePreferences()
        let savedShortcutPreferences = Self.loadShortcutPreferences()
        let savedFeedbackPreferences = Self.loadFeedbackPreferences()
        let savedPreviewPreferences = Self.loadPreviewPreferences()
        let savedAutomationPreferences = Self.loadAutomationPreferences()
        storage = ScreenshotStorage(
            namingPreferences: savedNamingPreferences,
            storagePreferences: savedStoragePreferences
        )
        namingPreferences = savedNamingPreferences
        storagePreferences = savedStoragePreferences
        shortcutPreferences = savedShortcutPreferences
        feedbackPreferences = savedFeedbackPreferences
        previewPreferences = savedPreviewPreferences
        automationPreferences = savedAutomationPreferences
        hasScreenRecordingPermission = captureService.hasScreenRecordingPermission

        shortcutManager.onFullScreenShortcut = { [weak self] in
            self?.captureFullScreen()
        }
        shortcutManager.onPartialShortcut = { [weak self] in
            self?.capturePartialScreen()
        }
        shortcutRegistrationFailures = applyShortcutPreferences(savedShortcutPreferences)

        do {
            try storage.ensureFolderExists()
            recentCaptures = storage.loadRecentCaptures()
            startRecentCapturesSync()
        } catch {
            statusMessage = error.localizedDescription
        }

        feedbackPerformer.prepare(feedbackPreferences)
        warmUpCapturePipeline()
    }

    deinit {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
        }

        recentCapturesSyncTask?.cancel()
        captureWarmUpTask?.cancel()
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
        warmUpCapturePipeline()
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
                runAutomations(for: record)
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

        feedbackPerformer.prepare(feedbackPreferences)
        warmUpCapturePipeline()

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

    func chooseScreenshotsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = storage.folderURL
        panel.prompt = "Choose"
        panel.message = "Choose where NyctivoeScreenShot saves screenshots."

        panel.begin { [weak self] response in
            guard response == .OK,
                  let url = panel.url
            else {
                return
            }

            Task { @MainActor in
                self?.storagePreferences.customFolderURL = url
            }
        }
    }

    func resetScreenshotsFolder() {
        storagePreferences.customFolderURL = nil
    }

    func resetStoragePreferences() {
        storagePreferences = .default
    }

    func reveal(_ record: ScreenshotRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.url])
    }

    func open(_ record: ScreenshotRecord) {
        NSWorkspace.shared.open(record.url)
    }

    private func deleteCurrentScreenshot(_ record: ScreenshotRecord) throws {
        if FileManager.default.fileExists(atPath: record.url.path) {
            try FileManager.default.removeItem(at: record.url)
        }

        recentCaptures.removeAll { $0.url == record.url }
        storage.saveRecentCaptures(recentCaptures)
        statusMessage = "Deleted \(record.fileName)"
    }

    func runAutomationStep(_ step: ScreenshotAutomationStep, for record: ScreenshotRecord) {
        guard step.isEnabled else {
            return
        }

        statusMessage = "Running \(step.title)..."
        Task { [weak self, preferences = automationPreferences, step, record] in
            guard let self else {
                return
            }

            let runner = ScreenshotAutomationRunner(preferences: preferences, handlers: automationHandlers)
            let summary = await runner.run(record: record, step: step)

            guard let statusMessage = summary.statusMessage else {
                return
            }

            self.statusMessage = statusMessage
        }
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

        focusRestorer.restore()

        Task {
            defer {
                finishCapture()
            }

            do {
                let image = try await captureService.capture(rect: rect)
                let record = try storage.save(image, kind: .partial)
                remember(record)
                statusMessage = "Saved \(record.fileName)"
                runAutomations(for: record)
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

    private func warmUpCapturePipeline() {
        guard hasScreenRecordingPermission,
              !didWarmCapturePipeline,
              captureWarmUpTask == nil
        else {
            return
        }

        captureWarmUpTask = Task(priority: .utility) { [weak self, captureService] in
            let didWarm = await captureService.warmUp()
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }

                self.didWarmCapturePipeline = didWarm
                self.captureWarmUpTask = nil
            }
        }
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
        previewPanelController.show(
            record: record,
            automationSteps: automationPreferences.automationSteps.filter { $0.isEnabled && $0.showsInPreviewMenu },
            previewPreferences: previewPreferences,
            onRunAutomationStep: { [weak self] step, record in
                self?.runAutomationStep(step, for: record)
            }
        )
    }

    private func runAutomations(for record: ScreenshotRecord) {
        let preferences = automationPreferences
        guard preferences.automationSteps.contains(where: { $0.isEnabled && $0.runsAfterCapture }) else {
            return
        }

        statusMessage = "Saved \(record.fileName). Running automations..."
        Task { [weak self, preferences, record] in
            guard let self else {
                return
            }

            let runner = ScreenshotAutomationRunner(preferences: preferences, handlers: automationHandlers)
            let summary = await runner.run(record: record)

            guard let statusMessage = summary.statusMessage else {
                return
            }

            self.statusMessage = statusMessage
        }
    }

    private func applyShortcutPreferences(
        _ preferences: ScreenshotShortcutPreferences
    ) -> [GlobalShortcutRegistrationFailure] {
        let failures = shortcutManager.updatePreferences(preferences)
        if !failures.isEmpty {
            statusMessage = Self.shortcutRegistrationFailureMessage(for: failures)
        }

        return failures
    }

    private static func shortcutRegistrationFailureMessage(
        for failures: [GlobalShortcutRegistrationFailure]
    ) -> String {
        guard failures.count > 1 else {
            guard let failure = failures.first else {
                return "Shortcuts updated."
            }

            return "Could not register \(failure.kind.rawValue.lowercased()) shortcut \(failure.shortcut.displayText) (status \(failure.status))."
        }

        let names = failures.map { $0.kind.rawValue.lowercased() }.joined(separator: ", ")
        return "Could not register shortcuts: \(names)."
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
        if shortcutRegistrationFailures.isEmpty {
            statusMessage = "Shortcut updated to \(shortcut.displayText)."
        }
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
        let dateFormatStyle = defaults
            .string(forKey: UserDefaultsKey.dateFormatStyle)
            .flatMap(ScreenshotDateFormatStyle.init(rawValue:))
        ?? migratedDateFormatStyle(defaults: defaults)
        let timeFormatStyle = defaults
            .string(forKey: UserDefaultsKey.timeFormatStyle)
            .flatMap(ScreenshotTimeFormatStyle.init(rawValue:))
        ?? migratedTimeFormatStyle(defaults: defaults)

        return ScreenshotNamingPreferences(
            prefix: prefix,
            dateFormatStyle: dateFormatStyle,
            timeFormatStyle: timeFormatStyle,
            includesCaptureKind: defaults.object(forKey: UserDefaultsKey.includesCaptureKind) as? Bool
            ?? defaultPreferences.includesCaptureKind
        )
    }

    private static func saveNamingPreferences(_ preferences: ScreenshotNamingPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.prefix, forKey: UserDefaultsKey.namePrefix)
        defaults.set(preferences.dateFormatStyle.rawValue, forKey: UserDefaultsKey.dateFormatStyle)
        defaults.set(preferences.timeFormatStyle.rawValue, forKey: UserDefaultsKey.timeFormatStyle)
        defaults.set(preferences.includesCaptureKind, forKey: UserDefaultsKey.includesCaptureKind)
    }

    private static func migratedDateFormatStyle(defaults: UserDefaults) -> ScreenshotDateFormatStyle {
        switch defaults.string(forKey: UserDefaultsKey.timestampStyle) {
        case "dateAndTime", "dateOnly":
            .yearMonthDayDashes
        case "none":
            .none
        default:
            ScreenshotNamingPreferences.default.dateFormatStyle
        }
    }

    private static func migratedTimeFormatStyle(defaults: UserDefaults) -> ScreenshotTimeFormatStyle {
        switch defaults.string(forKey: UserDefaultsKey.timestampStyle) {
        case "dateAndTime":
            .hourMinuteSecondDashes
        case "dateOnly", "none":
            .none
        default:
            ScreenshotNamingPreferences.default.timeFormatStyle
        }
    }

    private static func loadStoragePreferences() -> ScreenshotStoragePreferences {
        let defaults = UserDefaults.standard
        let defaultPreferences = ScreenshotStoragePreferences.default
        let customFolderURL = defaults.string(forKey: UserDefaultsKey.customFolderPath).map(URL.init(fileURLWithPath:))
        let folderOrganization = defaults
            .string(forKey: UserDefaultsKey.folderOrganization)
            .flatMap(ScreenshotFolderOrganization.init(rawValue:))
        ?? defaultPreferences.folderOrganization

        return ScreenshotStoragePreferences(
            customFolderURL: customFolderURL,
            folderOrganization: folderOrganization
        )
    }

    private static func saveStoragePreferences(_ preferences: ScreenshotStoragePreferences) {
        let defaults = UserDefaults.standard
        if let customFolderURL = preferences.customFolderURL {
            defaults.set(customFolderURL.path, forKey: UserDefaultsKey.customFolderPath)
        } else {
            defaults.removeObject(forKey: UserDefaultsKey.customFolderPath)
        }
        defaults.set(preferences.folderOrganization.rawValue, forKey: UserDefaultsKey.folderOrganization)
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
        guard defaults.object(forKey: keyCodeKey) != nil,
              defaults.object(forKey: modifiersKey) != nil
        else {
            return defaultValue
        }

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
        let flashDuration: TimeInterval
        if let storedDuration = defaults.object(forKey: UserDefaultsKey.feedbackFlashDuration) as? TimeInterval {
            flashDuration = storedDuration
        } else {
            flashDuration = defaults
                .string(forKey: UserDefaultsKey.feedbackFlashDuration)
                .flatMap(ScreenshotFeedbackFlashDuration.init(rawValue:))?
                .fadeOutDuration
            ?? defaultPreferences.flashDuration
        }

        return ScreenshotFeedbackPreferences(
            playsSound: defaults.object(forKey: UserDefaultsKey.feedbackPlaysSound) as? Bool
            ?? defaultPreferences.playsSound,
            flashesScreen: defaults.object(forKey: UserDefaultsKey.feedbackFlashesScreen) as? Bool
            ?? defaultPreferences.flashesScreen,
            sound: sound,
            soundVolume: defaults.object(forKey: UserDefaultsKey.feedbackSoundVolume) as? Double
            ?? defaultPreferences.soundVolume,
            flashIntensity: flashIntensity,
            flashDuration: flashDuration
        )
    }

    private static func saveFeedbackPreferences(_ preferences: ScreenshotFeedbackPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.playsSound, forKey: UserDefaultsKey.feedbackPlaysSound)
        defaults.set(preferences.flashesScreen, forKey: UserDefaultsKey.feedbackFlashesScreen)
        defaults.set(preferences.sound.rawValue, forKey: UserDefaultsKey.feedbackSound)
        defaults.set(preferences.soundVolume, forKey: UserDefaultsKey.feedbackSoundVolume)
        defaults.set(preferences.flashIntensity.rawValue, forKey: UserDefaultsKey.feedbackFlashIntensity)
        defaults.set(preferences.flashDuration, forKey: UserDefaultsKey.feedbackFlashDuration)
    }

    private static func loadPreviewPreferences() -> ScreenshotPreviewPreferences {
        let defaults = UserDefaults.standard
        let defaultPreferences = ScreenshotPreviewPreferences.default
        let dismissalDelay = defaults.object(forKey: UserDefaultsKey.previewDismissalDelay) as? TimeInterval
            ?? defaultPreferences.dismissalDelay

        let showsImagePreview = defaults.object(forKey: UserDefaultsKey.previewShowsImagePreview) as? Bool
            ?? defaultPreferences.showsImagePreview

        return ScreenshotPreviewPreferences(
            dismissalDelay: dismissalDelay,
            showsImagePreview: showsImagePreview
        )
    }

    private static func savePreviewPreferences(_ preferences: ScreenshotPreviewPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.dismissalDelay, forKey: UserDefaultsKey.previewDismissalDelay)
        defaults.set(preferences.showsImagePreview, forKey: UserDefaultsKey.previewShowsImagePreview)
    }

    private static func loadAutomationPreferences() -> ScreenshotAutomationPreferences {
        let defaults = UserDefaults.standard
        let defaultPreferences = ScreenshotAutomationPreferences.default

        var preferences = ScreenshotAutomationPreferences(
            supabaseProjectURL: defaults.string(forKey: UserDefaultsKey.supabaseProjectURL)
            ?? defaultPreferences.supabaseProjectURL,
            supabaseAnonKey: loadSupabaseCredential(.anonKey, legacyDefaultsKey: UserDefaultsKey.supabaseAnonKey, defaults: defaults),
            supabaseEmail: loadSupabaseCredential(.email, legacyDefaultsKey: UserDefaultsKey.supabaseEmail, defaults: defaults),
            supabasePassword: loadSupabaseCredential(.password, legacyDefaultsKey: UserDefaultsKey.supabasePassword, defaults: defaults),
            supabaseDestination: defaults
                .string(forKey: UserDefaultsKey.supabaseDestination)
                .flatMap(ScreenshotSupabaseDestination.init(rawValue:))
            ?? defaultPreferences.supabaseDestination,
            supabaseBucket: defaults.string(forKey: UserDefaultsKey.supabaseBucket)
            ?? defaultPreferences.supabaseBucket,
            supabasePathPrefix: defaults.string(forKey: UserDefaultsKey.supabasePathPrefix)
            ?? defaultPreferences.supabasePathPrefix,
            supabaseTableName: defaults.string(forKey: UserDefaultsKey.supabaseTableName)
            ?? defaultPreferences.supabaseTableName,
            supabaseTablePayloadTemplate: loadSupabaseTablePayloadTemplate(defaults: defaults),
            copiesSupabasePublicURL: defaults.object(forKey: UserDefaultsKey.supabaseCopiesPublicURL) as? Bool
            ?? defaultPreferences.copiesSupabasePublicURL,
            shareLinkDomain: defaults.string(forKey: UserDefaultsKey.shareLinkDomain)
            ?? defaultPreferences.shareLinkDomain,
            automationSteps: loadAutomationSteps(defaults: defaults)
        )
        preferences.automationSteps = migratedEventConfigurations(in: preferences.automationSteps, preferences: preferences)
        saveAutomationPreferences(preferences)
        return preferences
    }

    private static func saveAutomationPreferences(_ preferences: ScreenshotAutomationPreferences) {
        let defaults = UserDefaults.standard
        saveSupabaseCredentials(from: preferences.legacySupabaseConfiguration, eventID: nil)
        defaults.set(preferences.supabaseProjectURL, forKey: UserDefaultsKey.supabaseProjectURL)
        defaults.removeObject(forKey: UserDefaultsKey.supabaseAnonKey)
        defaults.removeObject(forKey: UserDefaultsKey.supabaseEmail)
        defaults.removeObject(forKey: UserDefaultsKey.supabasePassword)
        defaults.set(preferences.supabaseDestination.rawValue, forKey: UserDefaultsKey.supabaseDestination)
        defaults.set(preferences.supabaseBucket, forKey: UserDefaultsKey.supabaseBucket)
        defaults.set(preferences.supabasePathPrefix, forKey: UserDefaultsKey.supabasePathPrefix)
        defaults.set(preferences.supabaseTableName, forKey: UserDefaultsKey.supabaseTableName)
        defaults.set(preferences.supabaseTablePayloadTemplate, forKey: UserDefaultsKey.supabaseTablePayloadTemplate)
        defaults.set(preferences.copiesSupabasePublicURL, forKey: UserDefaultsKey.supabaseCopiesPublicURL)
        defaults.set(preferences.shareLinkDomain, forKey: UserDefaultsKey.shareLinkDomain)
        saveAutomationSteps(preferences.automationSteps, defaults: defaults)
    }

    private static func loadSupabaseCredential(
        _ field: SupabaseCredentialField,
        legacyDefaultsKey: String,
        defaults: UserDefaults
    ) -> String {
        if let storedValue = supabaseCredentialStore.string(for: credentialAccount(field, eventID: nil)) {
            defaults.removeObject(forKey: legacyDefaultsKey)
            return storedValue
        }

        defer {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }

        guard let legacyValue = defaults.string(forKey: legacyDefaultsKey), !legacyValue.isEmpty else {
            return ""
        }

        try? supabaseCredentialStore.setString(legacyValue, for: credentialAccount(field, eventID: nil))
        return legacyValue
    }

    private static func hydratedSupabaseConfiguration(
        _ configuration: ScreenshotSupabaseConfiguration,
        eventID: UUID?
    ) -> ScreenshotSupabaseConfiguration {
        var hydratedConfiguration = configuration
        hydratedConfiguration.anonKey = hydratedCredential(configuration.anonKey, field: .anonKey, eventID: eventID)
        hydratedConfiguration.email = hydratedCredential(configuration.email, field: .email, eventID: eventID)
        hydratedConfiguration.password = hydratedCredential(configuration.password, field: .password, eventID: eventID)
        return hydratedConfiguration
    }

    private static func hydratedCredential(
        _ decodedValue: String,
        field: SupabaseCredentialField,
        eventID: UUID?
    ) -> String {
        if !decodedValue.isEmpty {
            try? supabaseCredentialStore.setString(decodedValue, for: credentialAccount(field, eventID: eventID))
            return decodedValue
        }

        return supabaseCredentialStore.string(for: credentialAccount(field, eventID: eventID)) ?? ""
    }

    private static func saveSupabaseCredentials(from configuration: ScreenshotSupabaseConfiguration, eventID: UUID?) {
        saveSupabaseCredential(configuration.anonKey, field: .anonKey, eventID: eventID)
        saveSupabaseCredential(configuration.email, field: .email, eventID: eventID)
        saveSupabaseCredential(configuration.password, field: .password, eventID: eventID)
    }

    private static func saveSupabaseCredential(_ value: String, field: SupabaseCredentialField, eventID: UUID?) {
        let account = credentialAccount(field, eventID: eventID)
        if value.isEmpty {
            supabaseCredentialStore.removeString(for: account)
        } else {
            try? supabaseCredentialStore.setString(value, for: account)
        }
    }

    private static func credentialAccount(_ field: SupabaseCredentialField, eventID: UUID?) -> String {
        if let eventID {
            return "supabase.event.\(eventID.uuidString).\(field.rawValue)"
        }

        return "supabase.global.\(field.rawValue)"
    }

    private static func loadSupabaseTablePayloadTemplate(
        defaults: UserDefaults
    ) -> String {
        defaults.string(forKey: UserDefaultsKey.supabaseTablePayloadTemplate)
            .map(migratedSupabaseTablePayloadTemplate)
        ?? defaults.data(forKey: UserDefaultsKey.supabaseTableColumnMappings)
            .flatMap { data in
                try? JSONDecoder().decode([LegacySupabaseTableColumnMapping].self, from: data)
            }
            .map(Self.supabaseTablePayloadTemplate)
        ?? ScreenshotAutomationPreferences.default.supabaseTablePayloadTemplate
    }

    private static func migratedSupabaseTablePayloadTemplate(_ template: String) -> String {
        let oldDefaultTemplate = """
        {
          "image": "{base64Image}",
          "file_name": "{fileName}",
          "capture_kind": "{captureKind}",
          "dimensions": "{dimensions}",
          "created_at": "{createdAt}"
        }
        """

        guard template.trimmingCharacters(in: .whitespacesAndNewlines)
            == oldDefaultTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return template
        }

        return ScreenshotSupabaseTablePayloadTemplate.defaultValue
    }

    private static func loadAutomationSteps(defaults: UserDefaults) -> [ScreenshotAutomationStep] {
        let defaultSteps = ScreenshotAutomationStep.defaultSteps
        guard let data = defaults.data(forKey: UserDefaultsKey.automationSteps),
              let savedSteps = try? JSONDecoder().decode([ScreenshotAutomationStep].self, from: data)
        else {
            return migratedAutomationSteps(defaults: defaults, defaultSteps: defaultSteps)
        }

        return hydratedSupabaseCredentials(in: savedSteps)
    }

    private static func migratedAutomationSteps(
        defaults: UserDefaults,
        defaultSteps: [ScreenshotAutomationStep]
    ) -> [ScreenshotAutomationStep] {
        let legacySupabaseEnabled = defaults.object(forKey: UserDefaultsKey.supabaseUploadEnabled) as? Bool ?? false
        return defaultSteps.map { step in
            guard step.events.contains(where: { $0.kind == .supabaseUpload }) else {
                return step
            }

            var migratedStep = step
            migratedStep.runsAfterCapture = legacySupabaseEnabled
            migratedStep.isEnabled = true
            return migratedStep
        }
    }

    private static func hydratedSupabaseCredentials(in steps: [ScreenshotAutomationStep]) -> [ScreenshotAutomationStep] {
        steps.map { step in
            var hydratedStep = step
            for eventIndex in hydratedStep.events.indices where hydratedStep.events[eventIndex].kind == .supabaseUpload {
                hydratedStep.events[eventIndex].supabaseConfiguration = hydratedSupabaseConfiguration(
                    hydratedStep.events[eventIndex].supabaseConfiguration,
                    eventID: hydratedStep.events[eventIndex].id
                )
            }

            return hydratedStep
        }
    }

    private static func migratedEventConfigurations(
        in steps: [ScreenshotAutomationStep],
        preferences: ScreenshotAutomationPreferences
    ) -> [ScreenshotAutomationStep] {
        hydratedSupabaseCredentials(in: steps.map { step in
            var migratedStep = step
            for eventIndex in migratedStep.events.indices {
                switch migratedStep.events[eventIndex].kind {
                case .supabaseUpload:
                    if migratedStep.events[eventIndex].supabaseConfiguration.isEmpty {
                        migratedStep.events[eventIndex].supabaseConfiguration = preferences.legacySupabaseConfiguration
                    }
                case .copyShareLink:
                    if migratedStep.events[eventIndex].shareLinkConfiguration == .default {
                        migratedStep.events[eventIndex].shareLinkConfiguration = ScreenshotShareLinkConfiguration(
                            customDomain: preferences.shareLinkDomain,
                            urlTemplate: shareLinkTemplate(from: preferences.shareLinkDomain)
                        )
                    }
                case .copyFile, .copyFilePath, .openInPreview, .deleteCurrentScreenshot, .closePreviewPanel:
                    break
                }
            }

            return migratedStep
        })
    }

    private static func shareLinkTemplate(from legacyDomain: String) -> String {
        let trimmedDomain = legacyDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedDomain.isEmpty else {
            return ""
        }

        let domain = trimmedDomain.contains("://") ? trimmedDomain : "https://\(trimmedDomain)"
        return "\(domain)/{uuid}"
    }

    private static func saveAutomationSteps(
        _ steps: [ScreenshotAutomationStep],
        defaults: UserDefaults
    ) {
        let sanitizedSteps = steps.map { step in
            var sanitizedStep = step
            for eventIndex in sanitizedStep.events.indices where sanitizedStep.events[eventIndex].kind == .supabaseUpload {
                let configuration = sanitizedStep.events[eventIndex].supabaseConfiguration
                saveSupabaseCredentials(from: configuration, eventID: sanitizedStep.events[eventIndex].id)
                sanitizedStep.events[eventIndex].supabaseConfiguration.anonKey = ""
                sanitizedStep.events[eventIndex].supabaseConfiguration.email = ""
                sanitizedStep.events[eventIndex].supabaseConfiguration.password = ""
            }

            return sanitizedStep
        }

        guard let data = try? JSONEncoder().encode(sanitizedSteps) else {
            return
        }

        defaults.set(data, forKey: UserDefaultsKey.automationSteps)
    }

    private static func supabaseTablePayloadTemplate(from mappings: [LegacySupabaseTableColumnMapping]) -> String {
        var payload: [String: String] = [:]
        for mapping in mappings where mapping.isComplete {
            payload[mapping.columnName.trimmingCharacters(in: .whitespacesAndNewlines)] = "{\(mapping.valueSource.rawValue)}"
        }

        guard !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let template = String(data: data, encoding: .utf8)
        else {
            return ScreenshotSupabaseTablePayloadTemplate.defaultValue
        }

        return template
    }

    private enum SupabaseCredentialField: String {
        case anonKey
        case email
        case password
    }

    private enum UserDefaultsKey {
        static let namePrefix = "screenshotNamePrefix"
        static let timestampStyle = "screenshotTimestampStyle"
        static let dateFormatStyle = "screenshotDateFormatStyle"
        static let timeFormatStyle = "screenshotTimeFormatStyle"
        static let includesCaptureKind = "screenshotIncludesCaptureKind"
        static let customFolderPath = "screenshotCustomFolderPath"
        static let folderOrganization = "screenshotFolderOrganization"
        static let fullScreenShortcutKeyCode = "fullScreenShortcutKeyCode"
        static let fullScreenShortcutModifiers = "fullScreenShortcutModifiers"
        static let partialShortcutKeyCode = "partialShortcutKeyCode"
        static let partialShortcutModifiers = "partialShortcutModifiers"
        static let feedbackPlaysSound = "screenshotFeedbackPlaysSound"
        static let feedbackFlashesScreen = "screenshotFeedbackFlashesScreen"
        static let feedbackSound = "screenshotFeedbackSound"
        static let feedbackSoundVolume = "screenshotFeedbackSoundVolume"
        static let feedbackFlashIntensity = "screenshotFeedbackFlashIntensity"
        static let feedbackFlashDuration = "screenshotFeedbackFlashDuration"
        static let previewDismissalDelay = "screenshotPreviewDismissalDelay"
        static let previewShowsImagePreview = "screenshotPreviewShowsImagePreview"
        static let supabaseUploadEnabled = "screenshotSupabaseUploadEnabled"
        static let supabaseProjectURL = "screenshotSupabaseProjectURL"
        static let supabaseAnonKey = "screenshotSupabaseAnonKey"
        static let supabaseEmail = "screenshotSupabaseEmail"
        static let supabasePassword = "screenshotSupabasePassword"
        static let supabaseDestination = "screenshotSupabaseDestination"
        static let supabaseBucket = "screenshotSupabaseBucket"
        static let supabasePathPrefix = "screenshotSupabasePathPrefix"
        static let supabaseTableName = "screenshotSupabaseTableName"
        static let supabaseTableColumnMappings = "screenshotSupabaseTableColumnMappings"
        static let supabaseTablePayloadTemplate = "screenshotSupabaseTablePayloadTemplate"
        static let supabaseCopiesPublicURL = "screenshotSupabaseCopiesPublicURL"
        static let shareLinkDomain = "screenshotShareLinkDomain"
        static let automationSteps = "screenshotAutomationSteps"
    }

    private struct LegacySupabaseTableColumnMapping: Codable {
        var columnName: String
        var valueSource: LegacySupabaseTableValueSource

        var isComplete: Bool {
            !columnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && valueSource != .empty
        }
    }

    private enum LegacySupabaseTableValueSource: String, Codable {
        case empty
        case base64Image
        case fileName
        case captureKind
        case dimensions
        case createdAt
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
