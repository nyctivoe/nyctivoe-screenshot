//
//  LocalCredentialStore.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/12/26.
//

import Foundation
import LocalAuthentication
import Security

struct LocalCredentialStore {
    private let fileManager: FileManager
    private let service: String
    private let legacyCredentialsURL: URL

    init(service: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.service = service
        let fileName = "\(Self.sanitizedFileName(service))-credentials.json"
        legacyCredentialsURL = Self.applicationSupportFolderURL(fileManager: fileManager)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func string(for account: String) -> String? {
        if let keychainValue = try? keychainString(for: account) {
            return keychainValue
        }

        guard let legacyValue = legacyCredentials()[account] else {
            return nil
        }

        do {
            try setKeychainString(legacyValue, for: account)
            removeLegacyString(for: account)
        } catch {
            // Keep the legacy value readable if migration cannot complete.
        }

        return legacyValue
    }

    func setString(_ value: String, for account: String) throws {
        try setKeychainString(value, for: account)
        removeLegacyString(for: account)
    }

    func removeString(for account: String) {
        let query = baseQuery(for: account)
        SecItemDelete(query as CFDictionary)
        SecItemDelete(legacyKeychainQuery(for: account) as CFDictionary)
        removeLegacyString(for: account)
    }

    private func keychainString(for account: String) throws -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query = baseQuery(for: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecUseAuthenticationContext as String] = context

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data else {
            throw KeychainError(status: errSecDecode)
        }

        return String(data: data, encoding: .utf8)
    }

    private func setKeychainString(_ value: String, for account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError(status: errSecParam)
        }

        var addQuery = baseQuery(for: account)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw KeychainError(status: addStatus)
        }

        let updateStatus = SecItemUpdate(
            baseQuery(for: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw KeychainError(status: updateStatus)
        }
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any
        ]
    }

    private func legacyKeychainQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private func legacyCredentials() -> [String: String] {
        guard fileManager.fileExists(atPath: legacyCredentialsURL.path),
              let data = try? Data(contentsOf: legacyCredentialsURL),
              let credentials = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return credentials
    }

    private func removeLegacyString(for account: String) {
        var credentials = legacyCredentials()
        guard credentials.removeValue(forKey: account) != nil else {
            return
        }

        if credentials.isEmpty {
            try? fileManager.removeItem(at: legacyCredentialsURL)
        } else {
            try? writeLegacyCredentials(credentials)
        }
    }

    private func writeLegacyCredentials(_ credentials: [String: String]) throws {
        let folderURL = legacyCredentialsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(credentials)
        try data.write(to: legacyCredentialsURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: legacyCredentialsURL.path
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

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }

        return "Keychain error \(status)."
    }
}
