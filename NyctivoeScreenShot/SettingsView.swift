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
        }
        .scenePadding()
        .frame(minWidth: 460, minHeight: 300)
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
}

#Preview {
    SettingsView(
        controller: ScreenshotController(),
        launchAtLoginManager: LaunchAtLoginManager()
    )
}
