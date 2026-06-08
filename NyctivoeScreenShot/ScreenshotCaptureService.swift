//
//  ScreenshotCaptureService.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenshotCaptureService {
    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureMainDisplay() async throws -> CGImage {
        guard hasScreenRecordingPermission else {
            throw ScreenshotAppError.screenRecordingPermissionMissing
        }

        let content = try await SCShareableContent.current
        let filter = try mainDisplayFilter(from: content)
        return try await capture(filter: filter, sourceRect: filter.contentRect)
    }

    func capture(rect: CGRect) async throws -> CGImage {
        guard hasScreenRecordingPermission else {
            throw ScreenshotAppError.screenRecordingPermissionMissing
        }

        let content = try await SCShareableContent.current
        let filter = try mainDisplayFilter(from: content)
        let sourceRect = rect.intersection(filter.contentRect)

        guard !sourceRect.isNull, !sourceRect.isEmpty else {
            throw ScreenshotAppError.captureRegionUnavailable
        }

        return try await capture(filter: filter, sourceRect: sourceRect)
    }

    private func mainDisplayFilter(from content: SCShareableContent) throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw ScreenshotAppError.mainDisplayUnavailable
        }

        let currentApp = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }

        return SCContentFilter(
            display: display,
            excludingApplications: currentApp,
            exceptingWindows: []
        )
    }

    private func capture(filter: SCContentFilter, sourceRect: CGRect) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Self.pixelDimension(
            points: sourceRect.width,
            scale: CGFloat(filter.pointPixelScale)
        )
        configuration.height = Self.pixelDimension(
            points: sourceRect.height,
            scale: CGFloat(filter.pointPixelScale)
        )
        configuration.scalesToFit = false
        configuration.showsCursor = true

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func pixelDimension(points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((points * scale).rounded(.toNearestOrAwayFromZero)))
    }
}
