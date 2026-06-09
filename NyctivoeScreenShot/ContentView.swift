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

            Divider()

            recentCaptures

            Spacer(minLength: 0)

            footerActions
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 440)
        .nyctivoeWindowBackground()
        .onAppear {
            controller.refreshPermissionStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)

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
        .nyctivoeGlassEffect(in: Capsule())
    }

    private var captureActions: some View {
        HStack(spacing: 12) {
            Button {
                controller.captureFullScreen()
            } label: {
                Label("Full Screen", systemImage: "display")
                    .frame(maxWidth: .infinity)
            }
            .nyctivoeGlassButtonStyle(prominent: true)

            Button {
                controller.capturePartialScreen()
            } label: {
                Label("Partial", systemImage: "crop")
                    .frame(maxWidth: .infinity)
            }
            .nyctivoeGlassButtonStyle()
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
        .nyctivoeGlassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .nyctivoeGlassButtonStyle()

            Spacer()

            if !controller.hasScreenRecordingPermission {
                Button {
                    controller.requestScreenRecordingPermission()
                } label: {
                    Label("Request Permission", systemImage: "lock.open")
                }
                .nyctivoeGlassButtonStyle(prominent: true)
            }
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
                .foregroundStyle(.tint)
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
            .nyctivoeGlassButtonStyle()
            .help("Open")

            Button {
                controller.reveal(record)
            } label: {
                Label("Reveal", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .nyctivoeGlassButtonStyle()
            .help("Reveal")
        }
        .padding(10)
        .nyctivoeGlassEffect(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    ContentView(controller: ScreenshotController())
}
