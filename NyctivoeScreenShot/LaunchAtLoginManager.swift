//
//  LaunchAtLoginManager.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var statusText: String {
        switch status {
        case .enabled:
            "Enabled"
        case .requiresApproval:
            "Needs approval in System Settings"
        case .notRegistered:
            "Disabled"
        case .notFound:
            "Unavailable"
        @unknown default:
            "Unknown"
        }
    }

    init() {
        status = service.status
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ isEnabled: Bool) {
        errorMessage = nil

        do {
            if isEnabled {
                try service.register()
            } else if status != .notRegistered {
                try service.unregister()
            }

            refresh()
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum AppLaunchContext {
    static func shouldSuppressPermissionWindow(
        hasCompletedPermissionOnboarding: Bool,
        launchAtLoginManager: LaunchAtLoginManager
    ) -> Bool {
        hasCompletedPermissionOnboarding || shouldSuppressMainWindow(launchAtLoginManager: launchAtLoginManager)
    }

    static func shouldSuppressMainWindow(launchAtLoginManager: LaunchAtLoginManager) -> Bool {
        launchAtLoginManager.isEnabled && parentProcessName() == "launchd"
    }

    private static func parentProcessName() -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(getppid(), &pathBuffer, UInt32(pathBuffer.count))
        guard result > 0 else {
            return nil
        }

        let path = String(cString: pathBuffer)
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
