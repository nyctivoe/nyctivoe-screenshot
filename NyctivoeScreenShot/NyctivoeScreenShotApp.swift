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
    @StateObject private var controller = ScreenshotController()
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        WindowGroup("NyctivoeScreenShot", id: "main") {
            ContentView(controller: controller)
        }
        .defaultLaunchBehavior(
            AppLaunchContext.shouldSuppressMainWindow(launchAtLoginManager: launchAtLoginManager)
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
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Show Window", systemImage: "macwindow")
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
