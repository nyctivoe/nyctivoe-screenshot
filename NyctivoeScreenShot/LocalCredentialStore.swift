//
//  LocalCredentialStore.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/12/26.
//

import Foundation

struct LocalCredentialStore {
    private let fileManager: FileManager
    private let credentialsURL: URL

    init(service: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let fileName = "\(Self.sanitizedFileName(service))-credentials.json"
        credentialsURL = Self.applicationSupportFolderURL(fileManager: fileManager)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func string(for account: String) -> String? {
        credentials()[account]
    }

    func setString(_ value: String, for account: String) throws {
        var credentials = credentials()
        credentials[account] = value
        try write(credentials)
    }

    func removeString(for account: String) {
        var credentials = credentials()
        guard credentials.removeValue(forKey: account) != nil else {
            return
        }

        try? write(credentials)
    }

    private func credentials() -> [String: String] {
        guard fileManager.fileExists(atPath: credentialsURL.path),
              let data = try? Data(contentsOf: credentialsURL),
              let credentials = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return credentials
    }

    private func write(_ credentials: [String: String]) throws {
        let folderURL = credentialsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: credentialsURL.path
        )
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

    private static func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet.alphanumerics.inverted
        let components = value
            .components(separatedBy: invalidCharacters)
            .filter { !$0.isEmpty }
        return components.isEmpty ? "NyctivoeScreenShot" : components.joined(separator: "-")
    }
}
