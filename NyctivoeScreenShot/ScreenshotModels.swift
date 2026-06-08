//
//  ScreenshotModels.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import Carbon
import CoreGraphics
import Foundation

// Keyboard key codes used by macOS hardware events.
private enum KeyboardKeyCode {
    static let one: UInt32 = 18
    static let two: UInt32 = 19
}

enum ScreenshotKind: String {
    case fullScreen = "Full Screen"
    case partial = "Partial"

    var fileNameComponent: String {
        switch self {
        case .fullScreen:
            "Full-Screen"
        case .partial:
            "Partial"
        }
    }
}

enum ScreenshotTimestampStyle: String, CaseIterable, Identifiable {
    case dateAndTime
    case dateOnly
    case none

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .dateAndTime:
            "Date & Time"
        case .dateOnly:
            "Date Only"
        case .none:
            "None"
        }
    }

    var dateFormat: String? {
        switch self {
        case .dateAndTime:
            "yyyy-MM-dd-HH-mm-ss"
        case .dateOnly:
            "yyyy-MM-dd"
        case .none:
            nil
        }
    }
}

struct ScreenshotNamingPreferences: Equatable {
    static let defaultPrefix = "NyctivoeScreenShot"
    static let `default` = ScreenshotNamingPreferences(
        prefix: defaultPrefix,
        timestampStyle: .dateAndTime,
        includesCaptureKind: false
    )

    var prefix: String
    var timestampStyle: ScreenshotTimestampStyle
    var includesCaptureKind: Bool
}

struct ScreenshotKeyboardShortcut: Equatable {
    static let defaultFullScreen = ScreenshotKeyboardShortcut(
        keyCode: KeyboardKeyCode.one,
        modifiers: [.command, .option]
    )
    static let defaultPartial = ScreenshotKeyboardShortcut(
        keyCode: KeyboardKeyCode.two,
        modifiers: [.command, .option]
    )

    var keyCode: UInt32
    var modifiers: ScreenshotShortcutModifiers

    var isEnabled: Bool {
        keyCode > 0 && modifiers.rawValue > 0
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0

        if modifiers.contains(.command) {
            value |= UInt32(cmdKey)
        }

        if modifiers.contains(.option) {
            value |= UInt32(optionKey)
        }

        if modifiers.contains(.control) {
            value |= UInt32(controlKey)
        }

        if modifiers.contains(.shift) {
            value |= UInt32(shiftKey)
        }

        return value
    }

    var displayText: String {
        "\(modifiers.displayText)\(Self.keyDisplayText(for: keyCode))"
    }

    init(keyCode: UInt32, modifiers: ScreenshotShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(keyCode: UInt32, carbonModifiers: UInt32) {
        let modifiers = ScreenshotShortcutModifiers(carbonModifiers: carbonModifiers)
        guard keyCode > 0, modifiers.rawValue > 0 else {
            return nil
        }

        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static func keyDisplayText(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "O"
        case 32: "U"
        case 33: "["
        case 34: "I"
        case 35: "P"
        case 37: "L"
        case 38: "J"
        case 39: "'"
        case 40: "K"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "N"
        case 46: "M"
        case 47: "."
        case 49: "Space"
        case 50: "`"
        case 53: "Esc"
        case 123: "Left"
        case 124: "Right"
        case 125: "Down"
        case 126: "Up"
        default: "Key \(keyCode)"
        }
    }
}

struct ScreenshotShortcutModifiers: OptionSet, Equatable {
    let rawValue: UInt32

    static let command = ScreenshotShortcutModifiers(rawValue: 1 << 0)
    static let option = ScreenshotShortcutModifiers(rawValue: 1 << 1)
    static let control = ScreenshotShortcutModifiers(rawValue: 1 << 2)
    static let shift = ScreenshotShortcutModifiers(rawValue: 1 << 3)

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(carbonModifiers: UInt32) {
        var value: ScreenshotShortcutModifiers = []

        if carbonModifiers & UInt32(cmdKey) != 0 {
            value.insert(.command)
        }

        if carbonModifiers & UInt32(optionKey) != 0 {
            value.insert(.option)
        }

        if carbonModifiers & UInt32(controlKey) != 0 {
            value.insert(.control)
        }

        if carbonModifiers & UInt32(shiftKey) != 0 {
            value.insert(.shift)
        }

        self = value
    }

    var displayText: String {
        var components: [String] = []

        if contains(.control) {
            components.append("Control")
        }

        if contains(.option) {
            components.append("Option")
        }

        if contains(.shift) {
            components.append("Shift")
        }

        if contains(.command) {
            components.append("Command")
        }

        return components.isEmpty ? "" : "\(components.joined(separator: "-"))-"
    }
}

struct ScreenshotShortcutPreferences: Equatable {
    static let `default` = ScreenshotShortcutPreferences(
        fullScreenShortcut: .defaultFullScreen,
        partialShortcut: .defaultPartial
    )

    var fullScreenShortcut: ScreenshotKeyboardShortcut
    var partialShortcut: ScreenshotKeyboardShortcut
}

enum ScreenshotFeedbackSound: String, CaseIterable, Identifiable {
    case bottle
    case funk
    case glass
    case pop
    case submarine

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .bottle:
            "Bottle"
        case .funk:
            "Funk"
        case .glass:
            "Glass"
        case .pop:
            "Pop"
        case .submarine:
            "Submarine"
        }
    }

    var soundName: String {
        switch self {
        case .bottle:
            "Bottle"
        case .funk:
            "Funk"
        case .glass:
            "Glass"
        case .pop:
            "Pop"
        case .submarine:
            "Submarine"
        }
    }
}

struct ScreenshotFeedbackPreferences: Equatable {
    static let `default` = ScreenshotFeedbackPreferences(
        playsSound: true,
        flashesScreen: true,
        sound: .glass
    )

    var playsSound: Bool
    var flashesScreen: Bool
    var sound: ScreenshotFeedbackSound
}

struct ScreenshotRecord: Identifiable {
    let id = UUID()
    let url: URL
    let createdAt: Date
    let kind: ScreenshotKind
    let pixelSize: CGSize

    var fileName: String {
        url.lastPathComponent
    }

    var dimensionsText: String {
        "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
    }
}

enum ScreenshotAppError: LocalizedError {
    case screenRecordingPermissionMissing
    case mainDisplayUnavailable
    case captureRegionUnavailable
    case folderUnavailable
    case imageDestinationUnavailable
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            "Screen Recording permission is required."
        case .mainDisplayUnavailable:
            "The main display could not be found."
        case .captureRegionUnavailable:
            "The selected area could not be captured."
        case .folderUnavailable:
            "The screenshots folder could not be created."
        case .imageDestinationUnavailable:
            "The PNG file could not be prepared."
        case .imageWriteFailed:
            "The screenshot could not be saved."
        }
    }
}
