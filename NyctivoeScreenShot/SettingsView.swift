//
//  SettingsView.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: ScreenshotController
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                generalSettings
            }

            Tab("Shortcuts", systemImage: "keyboard") {
                shortcutSettings
            }

            Tab("Feedback", systemImage: "speaker.wave.2") {
                feedbackSettings
            }

            Tab("Automation", systemImage: "wand.and.sparkles") {
                automationSettings
            }
        }
        .scenePadding()
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            launchAtLoginManager.refresh()
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                Toggle("Start on Login", isOn: launchAtLoginBinding)

                HStack {
                    Text("Login Item")
                    Spacer()
                    Text(launchAtLoginManager.statusText)
                        .foregroundStyle(.secondary)
                }

                if launchAtLoginManager.status == .requiresApproval {
                    Button {
                        launchAtLoginManager.openLoginItemsSettings()
                    } label: {
                        Label("Open Login Items", systemImage: "gear")
                    }
                }

                if let errorMessage = launchAtLoginManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Saved Name") {
                TextField("Prefix", text: namePrefixBinding)

                Picker("Timestamp", selection: timestampStyleBinding) {
                    ForEach(ScreenshotTimestampStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }

                Toggle("Include Capture Type", isOn: includesCaptureKindBinding)

                HStack {
                    Text("Preview")
                    Spacer()
                    Text(controller.namingPreviewFileName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button {
                    controller.resetNamingPreferences()
                } label: {
                    Label("Reset Naming", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var automationSettings: some View {
        Form {
            Section("Functions") {
                ForEach(controller.automationPreferences.automationSteps.indices, id: \.self) { index in
                    automationStepRow(index: index)
                }

                Button {
                    addAutomationStep()
                } label: {
                    Label("Add Function", systemImage: "plus")
                }
            }

        }
        .formStyle(.grouped)
    }

    private var shortcutSettings: some View {
        Form {
            Section {
                shortcutButton(
                    title: "Full Screen",
                    kind: .fullScreen,
                    shortcut: controller.shortcutPreferences.fullScreenShortcut,
                    systemImage: "display"
                )

                shortcutButton(
                    title: "Partial",
                    kind: .partial,
                    shortcut: controller.shortcutPreferences.partialShortcut,
                    systemImage: "crop"
                )

                Button {
                    controller.resetShortcutPreferences()
                } label: {
                    Label("Reset Shortcuts", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var feedbackSettings: some View {
        Form {
            Section("Sound") {
                Toggle("Play Sound", isOn: playsSoundBinding)

                Picker("Sound", selection: feedbackSoundBinding) {
                    ForEach(ScreenshotFeedbackSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .disabled(!controller.feedbackPreferences.playsSound)
            }

            Section("Blink") {
                Toggle("Blink Screen", isOn: flashesScreenBinding)

                Picker("Intensity", selection: flashIntensityBinding) {
                    ForEach(ScreenshotFeedbackFlashIntensity.allCases) { intensity in
                        Text(intensity.label).tag(intensity)
                    }
                }
                .disabled(!controller.feedbackPreferences.flashesScreen)

                Picker("Duration", selection: flashDurationBinding) {
                    ForEach(ScreenshotFeedbackFlashDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
                .disabled(!controller.feedbackPreferences.flashesScreen)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutButton(
        title: String,
        kind: ScreenshotKind,
        shortcut: ScreenshotKeyboardShortcut,
        systemImage: String
    ) -> some View {
        Button {
            controller.startRecordingShortcut(for: kind)
        } label: {
            Label(
                controller.recordingShortcutKind == kind ? "Recording..." : "\(title): \(shortcut.displayText)",
                systemImage: systemImage
            )
        }
        .disabled(controller.isCapturing)
    }

    private func automationStepRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Function Name", text: automationStepNameBinding(index: index))
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Button {
                    moveAutomationStep(from: index, by: -1)
                } label: {
                    Label("Move Up", systemImage: "chevron.up")
                        .labelStyle(.iconOnly)
                }
                .disabled(index == 0)
                .help("Move Up")

                Button {
                    moveAutomationStep(from: index, by: 1)
                } label: {
                    Label("Move Down", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                }
                .disabled(index >= controller.automationPreferences.automationSteps.count - 1)
                .help("Move Down")

                Button {
                    deleteAutomationStep(at: index)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Delete")
            }

            TextField("What it does", text: automationStepDetailsBinding(index: index), axis: .vertical)
                .lineLimit(2...4)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(automationEventIndices(for: index), id: \.self) { eventIndex in
                    automationEventRow(stepIndex: index, eventIndex: eventIndex)
                }

                Button {
                    addAutomationEvent(to: index)
                } label: {
                    Label("Add Event", systemImage: "plus")
                }
            }

            HStack {
                Toggle("Enabled", isOn: automationStepEnabledBinding(index: index))
                Toggle("After Capture", isOn: automationStepRunsAfterCaptureBinding(index: index))
                Toggle("Preview Menu", isOn: automationStepShowsInPreviewMenuBinding(index: index))
            }
            .toggleStyle(.checkbox)
        }
    }

    private func automationEventRow(stepIndex: Int, eventIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: automationEventKind(stepIndex: stepIndex, eventIndex: eventIndex).systemImage)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                Picker("Event", selection: automationEventKindBinding(stepIndex: stepIndex, eventIndex: eventIndex)) {
                    ForEach(ScreenshotAutomationEventKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()

                Spacer()

                Button {
                    moveAutomationEvent(stepIndex: stepIndex, eventIndex: eventIndex, by: -1)
                } label: {
                    Label("Move Event Up", systemImage: "chevron.up")
                        .labelStyle(.iconOnly)
                }
                .disabled(eventIndex == 0)
                .help("Move Event Up")

                Button {
                    moveAutomationEvent(stepIndex: stepIndex, eventIndex: eventIndex, by: 1)
                } label: {
                    Label("Move Event Down", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                }
                .disabled(eventIndex >= automationEventIndices(for: stepIndex).count - 1)
                .help("Move Event Down")

                Button {
                    deleteAutomationEvent(stepIndex: stepIndex, eventIndex: eventIndex)
                } label: {
                    Label("Delete Event", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(automationEventIndices(for: stepIndex).count <= 1)
                .help("Delete Event")
            }

            automationEventConfiguration(stepIndex: stepIndex, eventIndex: eventIndex)
        }
    }

    @ViewBuilder
    private func automationEventConfiguration(stepIndex: Int, eventIndex: Int) -> some View {
        switch automationEventKind(stepIndex: stepIndex, eventIndex: eventIndex) {
        case .supabaseUpload:
            supabaseEventConfiguration(stepIndex: stepIndex, eventIndex: eventIndex)
        case .copyShareLink:
            shareLinkEventConfiguration(stepIndex: stepIndex, eventIndex: eventIndex)
        case .copyFile, .copyFilePath, .openInPreview:
            EmptyView()
        }
    }

    private func supabaseEventConfiguration(stepIndex: Int, eventIndex: Int) -> some View {
        DisclosureGroup("Supabase Config") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Supabase URL", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.projectURL))
                    .textFieldStyle(.roundedBorder)

                SecureField("Supabase Publishable Key", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.anonKey))
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.email))
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.password))
                    .textFieldStyle(.roundedBorder)

                Picker("Destination", selection: supabaseDestinationBinding(stepIndex: stepIndex, eventIndex: eventIndex)) {
                    ForEach(ScreenshotSupabaseDestination.allCases) { destination in
                        Text(destination.label).tag(destination)
                    }
                }
                .pickerStyle(.segmented)

                if supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex).destination == .storage {
                    TextField("Bucket", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.bucket))
                        .textFieldStyle(.roundedBorder)

                    TextField("Path Prefix", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.pathPrefix))
                        .textFieldStyle(.roundedBorder)

                    Toggle("Copy Public URL", isOn: supabaseBoolBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.copiesPublicURL))
                }

                if supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex).destination == .tableBase64 {
                    TextField("Table Name", text: supabaseStringBinding(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.tableName))
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: supabaseTablePayloadTemplateBinding(stepIndex: stepIndex, eventIndex: eventIndex))
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .frame(minHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary, lineWidth: 1)
                            )

                        Text(supabaseTablePlaceholderText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            setSupabaseConfigurationValue(
                                stepIndex: stepIndex,
                                eventIndex: eventIndex,
                                keyPath: \.tablePayloadTemplate,
                                value: """
                                {
                                  "name": "{fileName}",
                                  "image": "data:image/png;base64,{base64Image}",
                                  "is_public": true
                                }
                                """
                            )
                        } label: {
                            Label("Use Screenshot Table Template", systemImage: "arrow.counterclockwise")
                        }
                    }
                }

                HStack {
                    Text("Status")
                    Spacer()
                    let isConfigured = supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex).isConfigured
                    Label(
                        isConfigured ? "Configured" : "Not Configured",
                        systemImage: isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isConfigured ? .green : .orange)
                }
            }
            .padding(.top, 8)
        }
    }

    private func shareLinkEventConfiguration(stepIndex: Int, eventIndex: Int) -> some View {
        DisclosureGroup("Share Link Config") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("URL Template", text: shareLinkURLTemplateBinding(stepIndex: stepIndex, eventIndex: eventIndex))
                    .textFieldStyle(.roundedBorder)

                Text(automationPlaceholderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLoginManager.isEnabled
        } set: { value in
            launchAtLoginManager.setEnabled(value)
        }
    }

    private var namePrefixBinding: Binding<String> {
        Binding {
            controller.namingPreferences.prefix
        } set: { value in
            controller.namingPreferences.prefix = value
        }
    }

    private var timestampStyleBinding: Binding<ScreenshotTimestampStyle> {
        Binding {
            controller.namingPreferences.timestampStyle
        } set: { value in
            controller.namingPreferences.timestampStyle = value
        }
    }

    private var includesCaptureKindBinding: Binding<Bool> {
        Binding {
            controller.namingPreferences.includesCaptureKind
        } set: { value in
            controller.namingPreferences.includesCaptureKind = value
        }
    }

    private var playsSoundBinding: Binding<Bool> {
        Binding {
            controller.feedbackPreferences.playsSound
        } set: { value in
            controller.feedbackPreferences.playsSound = value
        }
    }

    private var flashesScreenBinding: Binding<Bool> {
        Binding {
            controller.feedbackPreferences.flashesScreen
        } set: { value in
            controller.feedbackPreferences.flashesScreen = value
        }
    }

    private var feedbackSoundBinding: Binding<ScreenshotFeedbackSound> {
        Binding {
            controller.feedbackPreferences.sound
        } set: { value in
            controller.feedbackPreferences.sound = value
        }
    }

    private var flashIntensityBinding: Binding<ScreenshotFeedbackFlashIntensity> {
        Binding {
            controller.feedbackPreferences.flashIntensity
        } set: { value in
            controller.feedbackPreferences.flashIntensity = value
        }
    }

    private var flashDurationBinding: Binding<ScreenshotFeedbackFlashDuration> {
        Binding {
            controller.feedbackPreferences.flashDuration
        } set: { value in
            controller.feedbackPreferences.flashDuration = value
        }
    }

    private var supabaseProjectURLBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabaseProjectURL
        } set: { value in
            controller.automationPreferences.supabaseProjectURL = value
        }
    }

    private var supabaseAnonKeyBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabaseAnonKey
        } set: { value in
            controller.automationPreferences.supabaseAnonKey = value
        }
    }

    private var supabaseEmailBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabaseEmail
        } set: { value in
            controller.automationPreferences.supabaseEmail = value
        }
    }

    private var supabasePasswordBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabasePassword
        } set: { value in
            controller.automationPreferences.supabasePassword = value
        }
    }

    private var supabaseDestinationBinding: Binding<ScreenshotSupabaseDestination> {
        Binding {
            controller.automationPreferences.supabaseDestination
        } set: { value in
            controller.automationPreferences.supabaseDestination = value
        }
    }

    private var supabaseBucketBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabaseBucket
        } set: { value in
            controller.automationPreferences.supabaseBucket = value
        }
    }

    private var supabasePathPrefixBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabasePathPrefix
        } set: { value in
            controller.automationPreferences.supabasePathPrefix = value
        }
    }

    private var supabaseTableNameBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabaseTableName
        } set: { value in
            controller.automationPreferences.supabaseTableName = value
        }
    }

    private var supabaseTablePayloadTemplateBinding: Binding<String> {
        Binding {
            controller.automationPreferences.supabaseTablePayloadTemplate
        } set: { value in
            controller.automationPreferences.supabaseTablePayloadTemplate = ScreenshotSupabaseTablePayloadTemplate.normalized(value)
        }
    }

    private var shareLinkDomainBinding: Binding<String> {
        Binding {
            controller.automationPreferences.shareLinkDomain
        } set: { value in
            controller.automationPreferences.shareLinkDomain = value
        }
    }

    private var isSupabaseFunctionEnabled: Bool {
        controller.automationPreferences.automationSteps.contains {
            $0.events.contains(where: { $0.kind == .supabaseUpload }) && $0.isEnabled
        }
    }

    private var supabaseTablePlaceholderText: String {
        let placeholders = ScreenshotSupabaseTablePayloadTemplate.placeholderNames
            .map { "{\($0)}" }
            .joined(separator: ", ")
        return "Placeholders: \(placeholders)"
    }

    private var automationPlaceholderText: String {
        "Placeholders include screenshot values like {fileName}, {filePath}, {width}, {height}; Supabase returned columns like {uuid}, {id}, {name}; and namespaced values like {supabase.uuid}."
    }

    private func supabaseConfiguration(stepIndex: Int, eventIndex: Int) -> ScreenshotSupabaseConfiguration {
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
        else {
            return .default
        }

        return controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].supabaseConfiguration
    }

    private func setSupabaseConfigurationValue<Value>(
        stepIndex: Int,
        eventIndex: Int,
        keyPath: WritableKeyPath<ScreenshotSupabaseConfiguration, Value>,
        value: Value
    ) {
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
        else {
            return
        }

        controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].supabaseConfiguration[keyPath: keyPath] = value
    }

    private func supabaseStringBinding(
        stepIndex: Int,
        eventIndex: Int,
        keyPath: WritableKeyPath<ScreenshotSupabaseConfiguration, String>
    ) -> Binding<String> {
        Binding {
            supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex)[keyPath: keyPath]
        } set: { value in
            setSupabaseConfigurationValue(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: keyPath, value: value)
        }
    }

    private func supabaseBoolBinding(
        stepIndex: Int,
        eventIndex: Int,
        keyPath: WritableKeyPath<ScreenshotSupabaseConfiguration, Bool>
    ) -> Binding<Bool> {
        Binding {
            supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex)[keyPath: keyPath]
        } set: { value in
            setSupabaseConfigurationValue(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: keyPath, value: value)
        }
    }

    private func supabaseDestinationBinding(stepIndex: Int, eventIndex: Int) -> Binding<ScreenshotSupabaseDestination> {
        Binding {
            supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex).destination
        } set: { value in
            setSupabaseConfigurationValue(stepIndex: stepIndex, eventIndex: eventIndex, keyPath: \.destination, value: value)
        }
    }

    private func supabaseTablePayloadTemplateBinding(stepIndex: Int, eventIndex: Int) -> Binding<String> {
        Binding {
            supabaseConfiguration(stepIndex: stepIndex, eventIndex: eventIndex).tablePayloadTemplate
        } set: { value in
            setSupabaseConfigurationValue(
                stepIndex: stepIndex,
                eventIndex: eventIndex,
                keyPath: \.tablePayloadTemplate,
                value: ScreenshotSupabaseTablePayloadTemplate.normalized(value)
            )
        }
    }

    private func shareLinkCustomDomainBinding(stepIndex: Int, eventIndex: Int) -> Binding<String> {
        Binding {
            guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
                  controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
            else {
                return ""
            }

            return controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].shareLinkConfiguration.customDomain
        } set: { value in
            guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
                  controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
            else {
                return
            }

            controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].shareLinkConfiguration.customDomain = value
        }
    }

    private func shareLinkURLTemplateBinding(stepIndex: Int, eventIndex: Int) -> Binding<String> {
        Binding {
            guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
                  controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
            else {
                return ""
            }

            return controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].shareLinkConfiguration.urlTemplate
        } set: { value in
            guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
                  controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
            else {
                return
            }

            controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].shareLinkConfiguration.urlTemplate = value
        }
    }

    private func automationStepNameBinding(index: Int) -> Binding<String> {
        Binding {
            guard controller.automationPreferences.automationSteps.indices.contains(index) else {
                return ""
            }

            return controller.automationPreferences.automationSteps[index].name
        } set: { value in
            guard controller.automationPreferences.automationSteps.indices.contains(index) else {
                return
            }

            controller.automationPreferences.automationSteps[index].name = value
        }
    }

    private func automationStepDetailsBinding(index: Int) -> Binding<String> {
        Binding {
            guard controller.automationPreferences.automationSteps.indices.contains(index) else {
                return ""
            }

            return controller.automationPreferences.automationSteps[index].details
        } set: { value in
            guard controller.automationPreferences.automationSteps.indices.contains(index) else {
                return
            }

            controller.automationPreferences.automationSteps[index].details = value
        }
    }

    private func automationStepEnabledBinding(index: Int) -> Binding<Bool> {
        automationStepBoolBinding(index: index, keyPath: \.isEnabled)
    }

    private func automationStepRunsAfterCaptureBinding(index: Int) -> Binding<Bool> {
        automationStepBoolBinding(index: index, keyPath: \.runsAfterCapture)
    }

    private func automationStepShowsInPreviewMenuBinding(index: Int) -> Binding<Bool> {
        automationStepBoolBinding(index: index, keyPath: \.showsInPreviewMenu)
    }

    private func automationStepBoolBinding(
        index: Int,
        keyPath: WritableKeyPath<ScreenshotAutomationStep, Bool>
    ) -> Binding<Bool> {
        Binding {
            guard controller.automationPreferences.automationSteps.indices.contains(index) else {
                return false
            }

            return controller.automationPreferences.automationSteps[index][keyPath: keyPath]
        } set: { value in
            guard controller.automationPreferences.automationSteps.indices.contains(index) else {
                return
            }

            controller.automationPreferences.automationSteps[index][keyPath: keyPath] = value
        }
    }

    private func moveAutomationStep(from index: Int, by offset: Int) {
        let destinationIndex = index + offset
        guard controller.automationPreferences.automationSteps.indices.contains(index),
              controller.automationPreferences.automationSteps.indices.contains(destinationIndex)
        else {
            return
        }

        controller.automationPreferences.automationSteps.swapAt(index, destinationIndex)
    }

    private func automationEventIndices(for stepIndex: Int) -> [Int] {
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex) else {
            return []
        }

        return Array(controller.automationPreferences.automationSteps[stepIndex].events.indices)
    }

    private func automationEventKind(stepIndex: Int, eventIndex: Int) -> ScreenshotAutomationEventKind {
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
        else {
            return .copyFile
        }

        return controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].kind
    }

    private func automationEventKindBinding(stepIndex: Int, eventIndex: Int) -> Binding<ScreenshotAutomationEventKind> {
        Binding {
            automationEventKind(stepIndex: stepIndex, eventIndex: eventIndex)
        } set: { value in
            guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
                  controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex)
            else {
                return
            }

            controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].kind = value
            if value == .supabaseUpload,
               controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].supabaseConfiguration.isEmpty {
                controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].supabaseConfiguration = controller.automationPreferences.legacySupabaseConfiguration
            }

            if value == .copyShareLink,
               controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].shareLinkConfiguration == .default {
                let legacyDomain = controller.automationPreferences.shareLinkDomain
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let urlTemplate = legacyDomain.isEmpty
                    ? "https://ss.nyctivoe.com/{uuid}"
                    : "\(legacyDomain.contains("://") ? legacyDomain : "https://\(legacyDomain)")/{uuid}"
                controller.automationPreferences.automationSteps[stepIndex].events[eventIndex].shareLinkConfiguration = ScreenshotShareLinkConfiguration(
                    customDomain: controller.automationPreferences.shareLinkDomain,
                    urlTemplate: urlTemplate
                )
            }
        }
    }

    private func addAutomationEvent(to stepIndex: Int) {
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex) else {
            return
        }

        controller.automationPreferences.automationSteps[stepIndex].events.append(
            ScreenshotAutomationEvent(kind: .copyFile)
        )
    }

    private func deleteAutomationEvent(stepIndex: Int, eventIndex: Int) {
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.count > 1
        else {
            return
        }

        controller.automationPreferences.automationSteps[stepIndex].events.remove(at: eventIndex)
    }

    private func moveAutomationEvent(stepIndex: Int, eventIndex: Int, by offset: Int) {
        let destinationIndex = eventIndex + offset
        guard controller.automationPreferences.automationSteps.indices.contains(stepIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(eventIndex),
              controller.automationPreferences.automationSteps[stepIndex].events.indices.contains(destinationIndex)
        else {
            return
        }

        controller.automationPreferences.automationSteps[stepIndex].events.swapAt(eventIndex, destinationIndex)
    }

    private func addAutomationStep() {
        controller.automationPreferences.automationSteps.append(
            ScreenshotAutomationStep(
                name: "New Function",
                details: ScreenshotAutomationEventKind.copyFile.defaultDetails,
                events: [ScreenshotAutomationEvent(kind: .copyFile)],
                runsAfterCapture: false,
                showsInPreviewMenu: true,
                isEnabled: true
            )
        )
    }

    private func deleteAutomationStep(at index: Int) {
        guard controller.automationPreferences.automationSteps.indices.contains(index) else {
            return
        }

        controller.automationPreferences.automationSteps.remove(at: index)
    }

    private var supabaseCopiesPublicURLBinding: Binding<Bool> {
        Binding {
            controller.automationPreferences.copiesSupabasePublicURL
        } set: { value in
            controller.automationPreferences.copiesSupabasePublicURL = value
        }
    }
}

#Preview {
    SettingsView(
        controller: ScreenshotController(),
        launchAtLoginManager: LaunchAtLoginManager()
    )
}
