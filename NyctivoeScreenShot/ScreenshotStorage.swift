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

    var namingPreferences: ScreenshotNamingPreferences
    var storagePreferences: ScreenshotStoragePreferences

    var folderURL: URL {
        storagePreferences.customFolderURL ?? Self.defaultFolderURL(fileManager: fileManager)
    }

    init(
        fileManager: FileManager = .default,
        namingPreferences: ScreenshotNamingPreferences = .default,
        storagePreferences: ScreenshotStoragePreferences = .default
    ) {
        self.fileManager = fileManager
        self.namingPreferences = namingPreferences
        self.storagePreferences = storagePreferences

        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    }

    func ensureFolderExists() throws {
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw ScreenshotAppError.folderUnavailable
        }
    }

    func save(_ image: CGImage, kind: ScreenshotKind) throws -> ScreenshotRecord {
        let createdAt = Date()
        let destinationFolderURL = try destinationFolderURL(for: createdAt)
        let url = try availableURL(for: createdAt, kind: kind, in: destinationFolderURL)
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
        let date = Date()
        let fileName = "\(baseName(for: date, kind: kind)).png"
        let relativeFolderPath = relativeFolderPath(for: date)
        guard !relativeFolderPath.isEmpty else {
            return fileName
        }

        return "\(relativeFolderPath)/\(fileName)"
    }

    func loadRecentCaptures() -> [ScreenshotRecord] {
        reconciledRecentCaptures(from: readPersistedRecentCaptures())
    }

    func saveRecentCaptures(_ records: [ScreenshotRecord]) {
        do {
            try ensureRecentCapturesIndexFolderExists()
            let recentRecords = Array(records.prefix(recentCapturesLimit))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(recentRecords)
            try data.write(to: recentCapturesIndexURL, options: .atomic)
            removeLegacyRecentCapturesIndexIfNeeded()
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

    private func availableURL(for date: Date, kind: ScreenshotKind, in folderURL: URL) throws -> URL {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

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

        if let dateFormat = namingPreferences.dateFormatStyle.dateFormat {
            dateFormatter.dateFormat = dateFormat
            components.append(sanitizedNameComponent(dateFormatter.string(from: date)))
        }

        if let timeFormat = namingPreferences.timeFormatStyle.dateFormat {
            dateFormatter.dateFormat = timeFormat
            components.append(sanitizedNameComponent(dateFormatter.string(from: date)))
        }

        return components.joined(separator: "-")
    }

    private func destinationFolderURL(for date: Date) throws -> URL {
        let destinationURL = relativeFolderPathComponents(for: date).reduce(folderURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }

        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            return destinationURL
        } catch {
            throw ScreenshotAppError.folderUnavailable
        }
    }

    private func relativeFolderPath(for date: Date) -> String {
        relativeFolderPathComponents(for: date).joined(separator: "/")
    }

    private func relativeFolderPathComponents(for date: Date) -> [String] {
        switch storagePreferences.folderOrganization {
        case .singleFolder:
            []
        case .year:
            [formattedDate(date, format: "yyyy")]
        case .yearAndMonth:
            [formattedDate(date, format: "yyyy"), formattedDate(date, format: "MM-MMMM")]
        }
    }

    private func formattedDate(_ date: Date, format: String) -> String {
        dateFormatter.dateFormat = format
        return sanitizedNameComponent(dateFormatter.string(from: date))
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
        Self.applicationSupportFolderURL(fileManager: fileManager)
            .appendingPathComponent("recent-captures.json", isDirectory: false)
    }

    private var legacyRecentCapturesIndexURL: URL {
        folderURL.appendingPathComponent(".recent-captures.json", isDirectory: false)
    }

    private func ensureRecentCapturesIndexFolderExists() throws {
        try fileManager.createDirectory(
            at: recentCapturesIndexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func readPersistedRecentCaptures() -> [ScreenshotRecord] {
        if fileManager.fileExists(atPath: recentCapturesIndexURL.path) {
            return readRecentCapturesIndex(at: recentCapturesIndexURL)
        }

        let legacyRecords = readRecentCapturesIndex(at: legacyRecentCapturesIndexURL)
        if !legacyRecords.isEmpty {
            saveRecentCaptures(legacyRecords)
        }

        return legacyRecords
    }

    private func readRecentCapturesIndex(at url: URL) -> [ScreenshotRecord] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ScreenshotRecord].self, from: data)
        } catch {
            return []
        }
    }

    private func removeLegacyRecentCapturesIndexIfNeeded() {
        guard fileManager.fileExists(atPath: legacyRecentCapturesIndexURL.path) else {
            return
        }

        try? fileManager.removeItem(at: legacyRecentCapturesIndexURL)
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

    private static func defaultFolderURL(fileManager: FileManager) -> URL {
        fileManager
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("NyctivoeScreenShot", isDirectory: true)
        ?? fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("NyctivoeScreenShot", isDirectory: true)
    }

    private static func applicationSupportFolderURL(fileManager: FileManager) -> URL {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("NyctivoeScreenShot", isDirectory: true)
        ?? fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NyctivoeScreenShot", isDirectory: true)
    }
}
