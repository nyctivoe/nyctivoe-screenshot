//
//  ScreenshotStorage.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ScreenshotStorage {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter
    private let recentCapturesLimit = 8

    let folderURL: URL
    var namingPreferences: ScreenshotNamingPreferences

    init(
        fileManager: FileManager = .default,
        namingPreferences: ScreenshotNamingPreferences = .default
    ) {
        self.fileManager = fileManager
        self.namingPreferences = namingPreferences
        folderURL = fileManager
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("NyctivoeScreenShot", isDirectory: true)
        ?? fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("NyctivoeScreenShot", isDirectory: true)

        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    }

    func ensureFolderExists() throws {
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw ScreenshotAppError.folderUnavailable
        }
    }

    func save(_ image: CGImage, kind: ScreenshotKind) throws -> ScreenshotRecord {
        try ensureFolderExists()

        let createdAt = Date()
        let url = try availableURL(for: createdAt, kind: kind)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotAppError.imageDestinationUnavailable
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotAppError.imageWriteFailed
        }

        return ScreenshotRecord(
            url: url,
            createdAt: createdAt,
            kind: kind,
            pixelSize: CGSize(width: image.width, height: image.height)
        )
    }

    func previewFileName(for kind: ScreenshotKind) -> String {
        "\(baseName(for: Date(), kind: kind)).png"
    }

    func loadRecentCaptures() -> [ScreenshotRecord] {
        reconciledRecentCaptures(from: readPersistedRecentCaptures())
    }

    func saveRecentCaptures(_ records: [ScreenshotRecord]) {
        do {
            try ensureFolderExists()
            let recentRecords = Array(records.prefix(recentCapturesLimit))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recentRecords)
            try data.write(to: recentCapturesIndexURL, options: .atomic)
        } catch {
            // Recent capture history is best-effort and should not block screenshots.
        }
    }

    func reconciledRecentCaptures() -> [ScreenshotRecord] {
        let records = readPersistedRecentCaptures()
        let reconciledRecords = reconciledRecentCaptures(from: records)

        if reconciledRecords != records {
            saveRecentCaptures(reconciledRecords)
        }

        return reconciledRecords
    }

    private func availableURL(for date: Date, kind: ScreenshotKind) throws -> URL {
        let baseName = baseName(for: date, kind: kind)
        var candidate = folderURL.appendingPathComponent("\(baseName).png", isDirectory: false)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(baseName)-\(suffix).png", isDirectory: false)
            suffix += 1
        }

        return candidate
    }

    private func baseName(for date: Date, kind: ScreenshotKind) -> String {
        var components = [sanitizedNameComponent(namingPreferences.prefix)]

        if namingPreferences.includesCaptureKind {
            components.append(kind.fileNameComponent)
        }

        if let dateFormat = namingPreferences.timestampStyle.dateFormat {
            dateFormatter.dateFormat = dateFormat
            components.append(dateFormatter.string(from: date))
        }

        return components.joined(separator: "-")
    }

    private func sanitizedNameComponent(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let sanitizedScalars = trimmedValue.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "-" : String(scalar)
        }
        let sanitized = sanitizedScalars
            .joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-"))

        return sanitized.isEmpty ? ScreenshotNamingPreferences.defaultPrefix : sanitized
    }

    private var recentCapturesIndexURL: URL {
        folderURL.appendingPathComponent(".recent-captures.json", isDirectory: false)
    }

    private func readPersistedRecentCaptures() -> [ScreenshotRecord] {
        guard fileManager.fileExists(atPath: recentCapturesIndexURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: recentCapturesIndexURL)
            return try JSONDecoder().decode([ScreenshotRecord].self, from: data)
        } catch {
            return []
        }
    }

    private func reconciledRecentCaptures(from records: [ScreenshotRecord]) -> [ScreenshotRecord] {
        let existingRecords = records.filter { record in
            fileManager.fileExists(atPath: record.url.path)
        }
        .sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }

        return Array(existingRecords.prefix(recentCapturesLimit))
    }
}
