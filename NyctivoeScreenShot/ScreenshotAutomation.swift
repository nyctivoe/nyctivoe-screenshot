//
//  ScreenshotAutomation.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit
import Foundation

struct ScreenshotAutomationPreferences: Equatable {
    static let `default` = ScreenshotAutomationPreferences(
        supabaseProjectURL: "",
        supabaseAnonKey: "",
        supabaseEmail: "",
        supabasePassword: "",
        supabaseDestination: .storage,
        supabaseBucket: "screenshots",
        supabasePathPrefix: "screenshots",
        supabaseTableName: "screenshots",
        supabaseTablePayloadTemplate: ScreenshotSupabaseTablePayloadTemplate.defaultValue,
        copiesSupabasePublicURL: false,
        shareLinkDomain: "",
        automationSteps: ScreenshotAutomationStep.defaultSteps
    )

    var supabaseProjectURL: String
    var supabaseAnonKey: String
    var supabaseEmail: String
    var supabasePassword: String
    var supabaseDestination: ScreenshotSupabaseDestination
    var supabaseBucket: String
    var supabasePathPrefix: String
    var supabaseTableName: String
    var supabaseTablePayloadTemplate: String
    var copiesSupabasePublicURL: Bool
    var shareLinkDomain: String
    var automationSteps: [ScreenshotAutomationStep]

    var isSupabaseConfigured: Bool {
        let hasBaseConfiguration = !normalizedProjectURL.isEmpty
            && !supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !supabaseEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !supabasePassword.isEmpty

        switch supabaseDestination {
        case .storage:
            return hasBaseConfiguration
                && !supabaseBucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .tableBase64:
            return hasBaseConfiguration
                && !supabaseTableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !supabaseTablePayloadTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var normalizedProjectURL: String {
        supabaseProjectURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var legacySupabaseConfiguration: ScreenshotSupabaseConfiguration {
        ScreenshotSupabaseConfiguration(
            projectURL: supabaseProjectURL,
            anonKey: supabaseAnonKey,
            email: supabaseEmail,
            password: supabasePassword,
            destination: supabaseDestination,
            bucket: supabaseBucket,
            pathPrefix: supabasePathPrefix,
            tableName: supabaseTableName,
            tablePayloadTemplate: supabaseTablePayloadTemplate,
            copiesPublicURL: copiesSupabasePublicURL
        )
    }
}

struct ScreenshotSupabaseConfiguration: Codable, Equatable {
    static let `default` = ScreenshotSupabaseConfiguration(
        projectURL: "",
        anonKey: "",
        email: "",
        password: "",
        destination: .storage,
        bucket: "screenshots",
        pathPrefix: "screenshots",
        tableName: "screenshots",
        tablePayloadTemplate: ScreenshotSupabaseTablePayloadTemplate.defaultValue,
        copiesPublicURL: false
    )

    var projectURL: String
    var anonKey: String
    var email: String
    var password: String
    var destination: ScreenshotSupabaseDestination
    var bucket: String
    var pathPrefix: String
    var tableName: String
    var tablePayloadTemplate: String
    var copiesPublicURL: Bool

    var isConfigured: Bool {
        let hasBaseConfiguration = !normalizedProjectURL.isEmpty
            && !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty

        switch destination {
        case .storage:
            return hasBaseConfiguration && !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .tableBase64:
            return hasBaseConfiguration
                && !tableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !tablePayloadTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var normalizedProjectURL: String {
        projectURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var isEmpty: Bool {
        self == .default
    }
}

struct ScreenshotShareLinkConfiguration: Codable, Equatable {
    static let `default` = ScreenshotShareLinkConfiguration(customDomain: "", urlTemplate: "")

    var customDomain: String
    var urlTemplate: String

    enum CodingKeys: String, CodingKey {
        case customDomain
        case urlTemplate
    }

    init(customDomain: String, urlTemplate: String = "") {
        self.customDomain = customDomain
        self.urlTemplate = urlTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customDomain = try container.decodeIfPresent(String.self, forKey: .customDomain) ?? ""
        urlTemplate = try container.decodeIfPresent(String.self, forKey: .urlTemplate) ?? ""
    }
}

struct ScreenshotAutomationStep: Codable, Equatable, Identifiable {
    static let defaultSteps = ScreenshotAutomationEventKind.defaultSequence.map { eventKind in
        ScreenshotAutomationStep(
            name: eventKind.label,
            details: eventKind.defaultDetails,
            events: [ScreenshotAutomationEvent(kind: eventKind)],
            runsAfterCapture: false,
            showsInPreviewMenu: eventKind.defaultShowsInPreviewMenu,
            isEnabled: true
        )
    }

    let id: UUID
    var name: String
    var details: String
    var events: [ScreenshotAutomationEvent]
    var runsAfterCapture: Bool
    var showsInPreviewMenu: Bool
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        details: String,
        events: [ScreenshotAutomationEvent],
        runsAfterCapture: Bool,
        showsInPreviewMenu: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.events = events
        self.runsAfterCapture = runsAfterCapture
        self.showsInPreviewMenu = showsInPreviewMenu
        self.isEnabled = isEnabled
    }

    var title: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? primaryEventKind.label : trimmedName
    }

    var resolvedDetails: String {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDetails.isEmpty ? events.map(\.kind.defaultDetails).joined(separator: " ") : trimmedDetails
    }

    var primaryEventKind: ScreenshotAutomationEventKind {
        events.first?.kind ?? .copyFile
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case details
        case function
        case events
        case runsAfterCapture
        case showsInPreviewMenu
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyFunction = try container.decodeIfPresent(ScreenshotAutomationEventKind.self, forKey: .function)
        let decodedEvents = try container.decodeIfPresent([ScreenshotAutomationEvent].self, forKey: .events)
        let events = decodedEvents ?? legacyFunction.map { [ScreenshotAutomationEvent(kind: $0)] } ?? [ScreenshotAutomationEvent(kind: .copyFile)]
        let primaryEventKind = events.first?.kind ?? .copyFile

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? primaryEventKind.label
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? primaryEventKind.defaultDetails
        self.events = events
        runsAfterCapture = try container.decode(Bool.self, forKey: .runsAfterCapture)
        showsInPreviewMenu = try container.decode(Bool.self, forKey: .showsInPreviewMenu)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(details, forKey: .details)
        try container.encode(events, forKey: .events)
        try container.encode(runsAfterCapture, forKey: .runsAfterCapture)
        try container.encode(showsInPreviewMenu, forKey: .showsInPreviewMenu)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

struct ScreenshotAutomationEvent: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: ScreenshotAutomationEventKind
    var supabaseConfiguration: ScreenshotSupabaseConfiguration
    var shareLinkConfiguration: ScreenshotShareLinkConfiguration

    init(
        id: UUID = UUID(),
        kind: ScreenshotAutomationEventKind,
        supabaseConfiguration: ScreenshotSupabaseConfiguration = .default,
        shareLinkConfiguration: ScreenshotShareLinkConfiguration = .default
    ) {
        self.id = id
        self.kind = kind
        self.supabaseConfiguration = supabaseConfiguration
        self.shareLinkConfiguration = shareLinkConfiguration
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case supabaseConfiguration
        case shareLinkConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(ScreenshotAutomationEventKind.self, forKey: .kind)
        supabaseConfiguration = try container.decodeIfPresent(
            ScreenshotSupabaseConfiguration.self,
            forKey: .supabaseConfiguration
        ) ?? .default
        shareLinkConfiguration = try container.decodeIfPresent(
            ScreenshotShareLinkConfiguration.self,
            forKey: .shareLinkConfiguration
        ) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(supabaseConfiguration, forKey: .supabaseConfiguration)
        try container.encode(shareLinkConfiguration, forKey: .shareLinkConfiguration)
    }
}

enum ScreenshotAutomationEventKind: String, CaseIterable, Codable, Identifiable {
    case copyFile
    case copyFilePath
    case openInPreview
    case supabaseUpload
    case copyShareLink

    var id: String {
        rawValue
    }

    static let defaultSequence: [ScreenshotAutomationEventKind] = [
        .copyFile,
        .copyFilePath,
        .openInPreview,
        .supabaseUpload
    ]

    var label: String {
        switch self {
        case .copyFile:
            "Copy File"
        case .copyFilePath:
            "Copy File Path"
        case .openInPreview:
            "Open in Preview"
        case .supabaseUpload:
            "Supabase Upload"
        case .copyShareLink:
            "Copy Share Link"
        }
    }

    var systemImage: String {
        switch self {
        case .copyFile:
            "doc.on.doc"
        case .copyFilePath:
            "text.insert"
        case .openInPreview:
            "eye"
        case .supabaseUpload:
            "icloud.and.arrow.up"
        case .copyShareLink:
            "link"
        }
    }

    var defaultShowsInPreviewMenu: Bool {
        switch self {
        case .copyFile, .copyFilePath, .openInPreview:
            true
        case .supabaseUpload, .copyShareLink:
            false
        }
    }

    var defaultDetails: String {
        switch self {
        case .copyFile:
            "Copies the screenshot file to the clipboard."
        case .copyFilePath:
            "Copies the saved screenshot path as text."
        case .openInPreview:
            "Opens the screenshot in Preview."
        case .supabaseUpload:
            "Uploads the screenshot using the Supabase settings."
        case .copyShareLink:
            "Builds a custom share URL from the latest Supabase ID or public URL and copies it."
        }
    }
}

enum ScreenshotSupabaseTablePayloadTemplate {
    static let defaultValue = """
    {
      "image": "data:image/png;base64,{base64Image}"
    }
    """

    static let placeholderNames = [
        "base64Image",
        "fileName",
        "captureKind",
        "dimensions",
        "createdAt",
        "width",
        "height",
        "filePath"
    ]

    static func renderedPayload(template: String, record: ScreenshotRecord, base64: String) throws -> [String: Any] {
        let renderedTemplate = render(template: normalized(template), record: record, base64: base64)
        guard let data = renderedTemplate.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ScreenshotAutomationError.invalidTablePayloadTemplate
        }

        return payload
    }

    static func normalized(_ template: String) -> String {
        template
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private static func render(template: String, record: ScreenshotRecord, base64: String) -> String {
        let values = [
            "base64Image": base64,
            "fileName": record.fileName,
            "captureKind": record.kind.rawValue,
            "dimensions": record.dimensionsText,
            "createdAt": ISO8601DateFormatter().string(from: record.createdAt),
            "width": "\(Int(record.pixelSize.width))",
            "height": "\(Int(record.pixelSize.height))",
            "filePath": record.url.path
        ]

        var renderedTemplate = template
        for name in placeholderNames {
            renderedTemplate = renderedTemplate.replacingOccurrences(
                of: "{\(name)}",
                with: jsonEscapedStringFragment(values[name] ?? "")
            )
        }

        return renderedTemplate
    }

    private static func jsonEscapedStringFragment(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encodedString = String(data: data, encoding: .utf8),
              encodedString.count >= 2
        else {
            return value
        }

        return String(encodedString.dropFirst().dropLast())
    }
}

enum ScreenshotSupabaseDestination: String, CaseIterable, Codable, Identifiable {
    case storage
    case tableBase64

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .storage:
            "Storage Bucket"
        case .tableBase64:
            "Table Base64"
        }
    }
}

final class ScreenshotAutomationContext {
    let record: ScreenshotRecord
    var values: [String: String]

    init(record: ScreenshotRecord, values: [String: String]? = nil) {
        self.record = record
        self.values = values ?? Self.defaultValues(for: record)
    }

    private static func defaultValues(for record: ScreenshotRecord) -> [String: String] {
        [
            "fileName": record.fileName,
            "filePath": record.url.path,
            "captureKind": record.kind.rawValue,
            "dimensions": record.dimensionsText,
            "createdAt": ISO8601DateFormatter().string(from: record.createdAt),
            "width": "\(Int(record.pixelSize.width))",
            "height": "\(Int(record.pixelSize.height))"
        ]
    }
}

enum ScreenshotAutomationTemplateRenderer {
    static func render(_ template: String, values: [String: String]) -> String {
        var renderedTemplate = template
        for (key, value) in values {
            renderedTemplate = renderedTemplate.replacingOccurrences(of: "{\(key)}", with: value)
        }

        return renderedTemplate
    }

    static func unresolvedPlaceholderNames(in value: String) -> [String] {
        var names: [String] = []
        var remainder = value[...]

        while let start = remainder.firstIndex(of: "{"),
              let end = remainder[start...].firstIndex(of: "}") {
            let nameStart = remainder.index(after: start)
            let name = String(remainder[nameStart..<end])
            if !name.isEmpty {
                names.append(name)
            }

            remainder = remainder[remainder.index(after: end)...]
        }

        return names
    }
}

struct ScreenshotAutomationResult {
    let message: String
    let publicURL: URL?
    let values: [String: String]

    init(message: String, publicURL: URL? = nil, values: [String: String] = [:]) {
        self.message = message
        self.publicURL = publicURL
        self.values = values
    }
}

protocol ScreenshotAutomationAction {
    var title: String { get }
    func run(context: ScreenshotAutomationContext) async throws -> ScreenshotAutomationResult?
}

final class ScreenshotAutomationRunner {
    var preferences: ScreenshotAutomationPreferences

    init(preferences: ScreenshotAutomationPreferences = .default) {
        self.preferences = preferences
    }

    func run(record: ScreenshotRecord) async -> ScreenshotAutomationSummary {
        await run(record: record, steps: preferences.automationSteps.filter { $0.isEnabled && $0.runsAfterCapture })
    }

    func run(record: ScreenshotRecord, step: ScreenshotAutomationStep) async -> ScreenshotAutomationSummary {
        await run(record: record, steps: [step])
    }

    private func run(record: ScreenshotRecord, steps: [ScreenshotAutomationStep]) async -> ScreenshotAutomationSummary {
        var messages: [String] = []
        var publicURL: URL?
        var values: [String: String]?

        for step in steps {
            let context = ScreenshotAutomationContext(record: record, values: values)
            for action in actions(for: step) {
                do {
                    if let result = try await action.run(context: context) {
                        messages.append(result.message)
                        publicURL = result.publicURL ?? publicURL
                        context.values.merge(result.values) { _, newValue in newValue }
                        values = context.values
                    }
                } catch {
                    messages.append("\(action.title) failed: \(error.localizedDescription)")
                }
            }
        }

        return ScreenshotAutomationSummary(messages: messages, publicURL: publicURL, values: values ?? [:])
    }

    private func actions(for step: ScreenshotAutomationStep) -> [ScreenshotAutomationAction] {
        step.events.map { event in
            switch event.kind {
            case .copyFile:
                return CopyFileAction(title: step.title)
            case .copyFilePath:
                return CopyFilePathAction(title: step.title)
            case .openInPreview:
                return OpenInPreviewAction(title: step.title)
            case .supabaseUpload:
                return SupabaseScreenshotAction(title: step.title, configuration: event.supabaseConfiguration)
            case .copyShareLink:
                return CopyShareLinkAction(title: step.title, configuration: event.shareLinkConfiguration)
            }
        }
    }
}

struct ScreenshotAutomationSummary {
    let messages: [String]
    let publicURL: URL?
    let values: [String: String]

    var statusMessage: String? {
        messages.last
    }
}

private struct SupabaseScreenshotAction: ScreenshotAutomationAction {
    let title: String
    let configuration: ScreenshotSupabaseConfiguration

    func run(context: ScreenshotAutomationContext) async throws -> ScreenshotAutomationResult? {
        guard configuration.isConfigured else {
            throw ScreenshotAutomationError.supabaseNotConfigured
        }

        let accessToken = try await SupabasePasswordAuthenticator(configuration: configuration).accessToken()

        switch configuration.destination {
        case .storage:
            return try await uploadToStorage(context: context, accessToken: accessToken)
        case .tableBase64:
            return try await insertBase64Record(context: context, accessToken: accessToken)
        }
    }

    private func uploadToStorage(
        context: ScreenshotAutomationContext,
        accessToken: String
    ) async throws -> ScreenshotAutomationResult {
        let objectPath = Self.objectPath(
            fileName: context.record.fileName,
            prefix: configuration.pathPrefix
        )
        let uploadURL = try Self.storageObjectURL(
            projectURL: configuration.normalizedProjectURL,
            bucket: configuration.bucket,
            objectPath: objectPath
        )
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")

        let data = try Data(contentsOf: context.record.url)
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenshotAutomationError.invalidServerResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ScreenshotAutomationError.uploadRejected(
                statusCode: httpResponse.statusCode,
                responseBody: Self.responseBody(from: responseData)
            )
        }

        let publicURL = Self.publicObjectURL(
            projectURL: configuration.normalizedProjectURL,
            bucket: configuration.bucket,
            objectPath: objectPath
        )

        if configuration.copiesPublicURL, let publicURL {
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(publicURL.absoluteString, forType: .string)
            }
        }

        return ScreenshotAutomationResult(
            message: configuration.copiesPublicURL ? "Uploaded and copied Supabase URL" : "Uploaded to Supabase",
            publicURL: publicURL,
            values: [
                "objectPath": objectPath,
                "publicURL": publicURL?.absoluteString ?? "",
                "supabase.objectPath": objectPath,
                "supabase.publicURL": publicURL?.absoluteString ?? ""
            ].filter { !$0.value.isEmpty }
        )
    }

    private func insertBase64Record(
        context: ScreenshotAutomationContext,
        accessToken: String
    ) async throws -> ScreenshotAutomationResult {
        let data = try Data(contentsOf: context.record.url)
        let payload = try tablePayload(record: context.record, base64: data.base64EncodedString())
        guard !payload.isEmpty else {
            throw ScreenshotAutomationError.tableColumnsUnavailable
        }

        let insertURL = try Self.tableInsertURL(
            projectURL: configuration.normalizedProjectURL,
            tableName: configuration.tableName
        )
        var request = URLRequest(url: insertURL)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenshotAutomationError.invalidServerResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ScreenshotAutomationError.uploadRejected(
            statusCode: httpResponse.statusCode,
                responseBody: Self.responseBody(from: responseData)
            )
        }

        let returnedValues = Self.returnedValues(from: responseData)
        return ScreenshotAutomationResult(
            message: "Inserted base64 screenshot in Supabase",
            values: returnedValues
        )
    }

    private func tablePayload(record: ScreenshotRecord, base64: String) throws -> [String: Any] {
        try ScreenshotSupabaseTablePayloadTemplate.renderedPayload(
            template: configuration.tablePayloadTemplate,
            record: record,
            base64: base64
        )
    }

    private static func objectPath(fileName: String, prefix: String) -> String {
        let cleanedPrefix = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleanedPrefix.isEmpty ? fileName : "\(cleanedPrefix)/\(fileName)"
    }

    private static func storageObjectURL(
        projectURL: String,
        bucket: String,
        objectPath: String
    ) throws -> URL {
        guard var components = URLComponents(string: projectURL) else {
            throw ScreenshotAutomationError.invalidSupabaseURL
        }

        components.path = "/storage/v1/object/\(bucket)/\(objectPath)"
        guard let url = components.url else {
            throw ScreenshotAutomationError.invalidSupabaseURL
        }

        return url
    }

    private static func publicObjectURL(
        projectURL: String,
        bucket: String,
        objectPath: String
    ) -> URL? {
        guard var components = URLComponents(string: projectURL) else {
            return nil
        }

        components.path = "/storage/v1/object/public/\(bucket)/\(objectPath)"
        return components.url
    }

    private static func tableInsertURL(
        projectURL: String,
        tableName: String
    ) throws -> URL {
        guard var components = URLComponents(string: projectURL) else {
            throw ScreenshotAutomationError.invalidSupabaseURL
        }

        components.path = "/rest/v1/\(tableName.trimmingCharacters(in: .whitespacesAndNewlines))"
        guard let url = components.url else {
            throw ScreenshotAutomationError.invalidSupabaseURL
        }

        return url
    }

    fileprivate static func responseBody(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func returnedValues(from data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }

        let row: [String: Any]?
        if let rows = object as? [[String: Any]] {
            row = rows.first
        } else {
            row = object as? [String: Any]
        }

        guard let row else {
            return [:]
        }

        var values: [String: String] = [:]
        if let id = stringValue(from: row["id"] ?? row["uuid"]) {
            values["supabaseRecordID"] = id
            values["id"] = values["id"] ?? id
            values["uuid"] = values["uuid"] ?? id
            values["supabase.id"] = values["supabase.id"] ?? id
            values["supabase.uuid"] = values["supabase.uuid"] ?? id
        }

        for (key, value) in row {
            if let stringValue = stringValue(from: value) {
                values[key] = stringValue
                values["supabase.\(key)"] = stringValue
            }
        }

        return values
    }

    private static func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let uuid as UUID:
            return uuid.uuidString
        default:
            return nil
        }
    }
}

private struct CopyFileAction: ScreenshotAutomationAction {
    let title: String

    func run(context: ScreenshotAutomationContext) async throws -> ScreenshotAutomationResult? {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([context.record.url as NSURL])
        }

        return ScreenshotAutomationResult(
            message: "Copied file",
            values: [
                "copiedFile": context.record.url.path,
                "copiedFilePath": context.record.url.path
            ]
        )
    }
}

private struct CopyFilePathAction: ScreenshotAutomationAction {
    let title: String

    func run(context: ScreenshotAutomationContext) async throws -> ScreenshotAutomationResult? {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(context.record.url.path, forType: .string)
        }

        return ScreenshotAutomationResult(
            message: "Copied file path",
            values: ["copiedFilePath": context.record.url.path]
        )
    }
}

private struct OpenInPreviewAction: ScreenshotAutomationAction {
    let title: String

    func run(context: ScreenshotAutomationContext) async throws -> ScreenshotAutomationResult? {
        await MainActor.run {
            guard let previewURL = previewApplicationURL else {
                NSWorkspace.shared.open(context.record.url)
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([context.record.url], withApplicationAt: previewURL, configuration: configuration) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(context.record.url)
                }
            }
        }

        return ScreenshotAutomationResult(
            message: "Opened in Preview",
            values: ["openedFilePath": context.record.url.path]
        )
    }

    private var previewApplicationURL: URL? {
        let candidates = [
            URL(fileURLWithPath: "/System/Applications/Preview.app"),
            URL(fileURLWithPath: "/Applications/Preview.app")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private struct CopyShareLinkAction: ScreenshotAutomationAction {
    let title: String
    let configuration: ScreenshotShareLinkConfiguration

    func run(context: ScreenshotAutomationContext) async throws -> ScreenshotAutomationResult? {
        let link = try shareLink(from: context.values)

        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.absoluteString, forType: .string)
        }

        return ScreenshotAutomationResult(
            message: "Copied share link",
            publicURL: link,
            values: ["shareURL": link.absoluteString]
        )
    }

    private func shareLink(from values: [String: String]) throws -> URL {
        let trimmedDomain = configuration.customDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let trimmedTemplate = configuration.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTemplate.isEmpty {
            let renderedTemplate = ScreenshotAutomationTemplateRenderer.render(trimmedTemplate, values: values)
            let unresolvedNames = ScreenshotAutomationTemplateRenderer.unresolvedPlaceholderNames(in: renderedTemplate)
            guard unresolvedNames.isEmpty else {
                throw ScreenshotAutomationError.unresolvedPlaceholders(unresolvedNames)
            }

            guard let url = URL(string: renderedTemplate) else {
                throw ScreenshotAutomationError.invalidShareLink
            }

            return url
        }

        if !trimmedDomain.isEmpty, let id = values["uuid"] ?? values["id"] ?? values["supabaseRecordID"] {
            let domain = trimmedDomain.contains("://") ? trimmedDomain : "https://\(trimmedDomain)"
            guard let url = URL(string: "\(domain)/\(id)") else {
                throw ScreenshotAutomationError.invalidShareLink
            }

            return url
        }

        if let publicURL = values["publicURL"] ?? values["supabase.publicURL"],
           let url = URL(string: publicURL) {
            return url
        }

        throw ScreenshotAutomationError.shareLinkUnavailable
    }
}

private struct SupabasePasswordAuthenticator {
    let configuration: ScreenshotSupabaseConfiguration

    func accessToken() async throws -> String {
        let authURL = try tokenURL(projectURL: configuration.normalizedProjectURL)
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SupabasePasswordRequest(
                email: configuration.email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: configuration.password
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScreenshotAutomationError.invalidServerResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ScreenshotAutomationError.authenticationRejected(
                statusCode: httpResponse.statusCode,
                responseBody: SupabaseScreenshotAction.responseBody(from: data)
            )
        }

        let session = try JSONDecoder().decode(SupabasePasswordSession.self, from: data)
        return session.accessToken
    }

    private func tokenURL(projectURL: String) throws -> URL {
        guard var components = URLComponents(string: projectURL) else {
            throw ScreenshotAutomationError.invalidSupabaseURL
        }

        components.path = "/auth/v1/token"
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let url = components.url else {
            throw ScreenshotAutomationError.invalidSupabaseURL
        }

        return url
    }
}

private struct SupabasePasswordRequest: Encodable {
    let email: String
    let password: String
}

private struct SupabasePasswordSession: Decodable {
    let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

enum ScreenshotAutomationError: LocalizedError {
    case supabaseNotConfigured
    case invalidSupabaseURL
    case invalidServerResponse
    case tableColumnsUnavailable
    case invalidTablePayloadTemplate
    case invalidShareLink
    case shareLinkUnavailable
    case unresolvedPlaceholders([String])
    case authenticationRejected(statusCode: Int, responseBody: String?)
    case uploadRejected(statusCode: Int, responseBody: String?)

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured:
            "Supabase upload is enabled but not configured."
        case .invalidSupabaseURL:
            "The Supabase project URL is invalid."
        case .invalidServerResponse:
            "Supabase returned an invalid response."
        case .tableColumnsUnavailable:
            "Write a JSON table payload template before uploading."
        case .invalidTablePayloadTemplate:
            "The Supabase table payload must be valid JSON after placeholders are filled."
        case .invalidShareLink:
            "The rendered share link is not a valid URL."
        case .shareLinkUnavailable:
            "No Supabase ID or public URL is available for the share link."
        case .unresolvedPlaceholders(let names):
            "The share link has unresolved placeholders: \(names.map { "{\($0)}" }.joined(separator: ", "))."
        case .authenticationRejected(let statusCode, let responseBody):
            Self.message("Supabase authentication failed", statusCode: statusCode, responseBody: responseBody)
        case .uploadRejected(let statusCode, let responseBody):
            Self.message("Supabase rejected the upload", statusCode: statusCode, responseBody: responseBody)
        }
    }

    private static func message(_ prefix: String, statusCode: Int, responseBody: String?) -> String {
        let trimmedResponseBody = responseBody?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedResponseBody, !trimmedResponseBody.isEmpty else {
            return "\(prefix) with status \(statusCode)."
        }

        return "\(prefix) with status \(statusCode): \(trimmedResponseBody)"
    }
}
