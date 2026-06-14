//
//  ScreenshotCaptureService.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

struct ScreenshotCaptureService {
    nonisolated var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    nonisolated func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    nonisolated func warmUp() async -> Bool {
        guard hasScreenRecordingPermission else {
            return false
        }

        do {
            let content = try await SCShareableContent.current
            let filter = try mainDisplayFilter(from: content)
            let sourceRect = Self.warmUpRect(in: filter.contentRect)
            _ = try await capture(filter: filter, sourceRect: sourceRect, includesCursor: false)
            return true
        } catch {
            return false
        }
    }

    nonisolated func captureMainDisplay() async throws -> CGImage {
        guard hasScreenRecordingPermission else {
            throw ScreenshotAppError.screenRecordingPermissionMissing
        }

        let content = try await SCShareableContent.current
        let filter = try mainDisplayFilter(from: content)
        return try await capture(filter: filter, sourceRect: filter.contentRect)
    }

    nonisolated func capture(rect: CGRect) async throws -> CGImage {
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

    private nonisolated func mainDisplayFilter(from content: SCShareableContent) throws -> SCContentFilter {
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

    private nonisolated func capture(
        filter: SCContentFilter,
        sourceRect: CGRect,
        includesCursor: Bool = true
    ) async throws -> CGImage {
        let pointPixelScale = CGFloat(filter.pointPixelScale)
        let cursorSnapshot = includesCursor
            ? await MainActor.run { Self.currentCursorSnapshot() }
            : nil
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Self.pixelDimension(
            points: sourceRect.width,
            scale: pointPixelScale
        )
        configuration.height = Self.pixelDimension(
            points: sourceRect.height,
            scale: pointPixelScale
        )
        configuration.scalesToFit = false
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return Self.image(
            image,
            drawing: cursorSnapshot,
            in: sourceRect,
            scale: pointPixelScale
        )
    }

    @MainActor
    private static func currentCursorSnapshot() -> CursorSnapshot? {
        let cursor = NSCursor.currentSystem ?? NSCursor.current
        let cursorImage = cursor.image
        var proposedRect = CGRect(origin: .zero, size: cursorImage.size)

        guard let image = cursorImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        return CursorSnapshot(
            image: image,
            size: cursorImage.size,
            hotSpot: cursor.hotSpot,
            screenLocation: NSEvent.mouseLocation
        )
    }

    private nonisolated static func image(
        _ image: CGImage,
        drawing cursor: CursorSnapshot?,
        in sourceRect: CGRect,
        scale: CGFloat
    ) -> CGImage {
        guard let cursor else {
            return image
        }

        let cursorFrame = cursor.frame(in: sourceRect, scale: scale)
        guard cursorFrame.intersects(CGRect(x: 0, y: 0, width: image.width, height: image.height)) else {
            return image
        }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(cursor.image, in: cursorFrame)
        return context.makeImage() ?? image
    }

    private nonisolated static func warmUpRect(in contentRect: CGRect) -> CGRect {
        CGRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: min(1, contentRect.width),
            height: min(1, contentRect.height)
        )
    }

    private nonisolated static func pixelDimension(points: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((points * scale).rounded(.toNearestOrAwayFromZero)))
    }
}

private struct CursorSnapshot: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
    let hotSpot: CGPoint
    let screenLocation: CGPoint

    nonisolated func frame(in sourceRect: CGRect, scale: CGFloat) -> CGRect {
        let width = size.width * scale
        let height = size.height * scale
        let x = (screenLocation.x - sourceRect.minX - hotSpot.x) * scale
        let y = (screenLocation.y - sourceRect.minY - (size.height - hotSpot.y)) * scale

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
