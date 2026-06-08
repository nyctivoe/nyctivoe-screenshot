//
//  ContentView.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/7/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ScreenshotController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            captureActions
            statusBar
            namingOptions
            shortcutAndFeedbackOptions

            Divider()

            recentCaptures

            Spacer(minLength: 0)

            footerActions
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 580)
        .onAppear {
            controller.refreshPermissionStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("NyctivoeScreenShot")
                    .font(.title2.weight(.semibold))
                Text(controller.screenshotsFolderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            permissionBadge
        }
    }

    private var permissionBadge: some View {
        Label(
            controller.hasScreenRecordingPermission ? "Ready" : "Permission Needed",
            systemImage: controller.hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(controller.hasScreenRecordingPermission ? .green : .orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private var captureActions: some View {
        HStack(spacing: 12) {
            Button {
                controller.captureFullScreen()
            } label: {
                Label("Full Screen", systemImage: "display")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                controller.capturePartialScreen()
            } label: {
                Label("Partial", systemImage: "crop")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .disabled(controller.isCapturing)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if controller.isCapturing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }

            Text(controller.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var namingOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Saved Name", systemImage: "tag")
                    .font(.headline)

                Spacer()

                Button {
                    controller.resetNamingPreferences()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Reset naming")
            }

            HStack(spacing: 12) {
                TextField("Prefix", text: namePrefixBinding)
                    .textFieldStyle(.roundedBorder)

                Picker("Timestamp", selection: timestampStyleBinding) {
                    ForEach(ScreenshotTimestampStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            HStack(spacing: 12) {
                Toggle("Capture Type", isOn: includesCaptureKindBinding)

                Spacer()

                Text(controller.namingPreviewFileName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var shortcutAndFeedbackOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Shortcuts & Feedback", systemImage: "keyboard")
                    .font(.headline)

                Spacer()

                Button {
                    controller.resetShortcutPreferences()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Reset shortcuts")
            }

            HStack(spacing: 12) {
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
            }

            HStack(spacing: 12) {
                Toggle("Sound", isOn: playsSoundBinding)

                Picker("Sound", selection: feedbackSoundBinding) {
                    ForEach(ScreenshotFeedbackSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
                .disabled(!controller.feedbackPreferences.playsSound)

                Toggle("Blink", isOn: flashesScreenBinding)

                Spacer()
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
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
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .disabled(controller.isCapturing)
    }

    private var recentCaptures: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Captures")
                .font(.headline)

            if controller.recentCaptures.isEmpty {
                ContentUnavailableView {
                    Label("No Captures Yet", systemImage: "photo.on.rectangle")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(controller.recentCaptures) { record in
                            CaptureRow(record: record, controller: controller)
                        }
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Button {
                controller.openScreenshotsFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }

            Spacer()

            if !controller.hasScreenRecordingPermission {
                Button {
                    controller.requestScreenRecordingPermission()
                } label: {
                    Label("Request Permission", systemImage: "lock.open")
                }
            }
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
}

private struct CaptureRow: View {
    let record: ScreenshotRecord
    @ObservedObject var controller: ScreenshotController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind == .fullScreen ? "display" : "crop")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(record.kind.rawValue) · \(record.dimensionsText) · \(record.createdAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                controller.open(record)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
                    .labelStyle(.iconOnly)
            }
            .help("Open")

            Button {
                controller.reveal(record)
            } label: {
                Label("Reveal", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .help("Reveal")
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView(controller: ScreenshotController())
}
