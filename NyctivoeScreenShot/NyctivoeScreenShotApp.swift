//
//  NyctivoeScreenShotApp.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/7/26.
//

import AppKit
import SwiftUI

@main
struct NyctivoeScreenShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedPermissionOnboarding") private var hasCompletedPermissionOnboarding = false
    @StateObject private var controller = ScreenshotController()
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager()
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        WindowGroup("Screen Recording Permission", id: "permission") {
            PermissionOnboardingView(
                controller: controller,
                hasCompletedOnboarding: $hasCompletedPermissionOnboarding
            )
        }
        .defaultLaunchBehavior(
            AppLaunchContext.shouldSuppressPermissionWindow(
                hasCompletedPermissionOnboarding: hasCompletedPermissionOnboarding,
                launchAtLoginManager: launchAtLoginManager
            )
            ? .suppressed
            : .automatic
        )
        .restorationBehavior(.disabled)

        MenuBarExtra("NyctivoeScreenShot", systemImage: "camera.viewfinder") {
            Button {
                controller.captureFullScreen()
            } label: {
                Label("Full Screen Screenshot", systemImage: "display")
            }
            .disabled(controller.isCapturing)

            Button {
                controller.capturePartialScreen()
            } label: {
                Label("Partial Screenshot", systemImage: "crop")
            }
            .disabled(controller.isCapturing)

            Divider()

            Button {
                controller.openScreenshotsFolder()
            } label: {
                Label("Open Screenshots Folder", systemImage: "folder")
            }

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gear")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                controller: controller,
                launchAtLoginManager: launchAtLoginManager
            )
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isAnotherInstanceRunning else {
            NSApp.terminate(nil)
            return
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private static var isAnotherInstanceRunning: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentProcessIdentifier }
    }
}

private struct PermissionOnboardingView: View {
    @ObservedObject var controller: ScreenshotController
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("NyctivoeScreenShot")
                        .font(.title2.weight(.semibold))
                    Text("Screen Recording permission is required for screenshots.")
                        .foregroundStyle(.secondary)
                }
            }

            permissionStatus

            HStack {
                Button {
                    hasCompletedOnboarding = true
                    dismiss()
                } label: {
                    Text(controller.hasScreenRecordingPermission ? "Done" : "Later")
                }

                Spacer()

                Button {
                    controller.requestScreenRecordingPermission()
                    if controller.hasScreenRecordingPermission {
                        hasCompletedOnboarding = true
                        dismiss()
                    }
                } label: {
                    Label("Request Permission", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            controller.refreshPermissionStatus()
        }
    }

    private var permissionStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(controller.hasScreenRecordingPermission ? .green : .orange)

            Text(controller.hasScreenRecordingPermission ? "Permission is enabled." : "Click Request Permission, then enable Screen Recording in System Settings if prompted.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
