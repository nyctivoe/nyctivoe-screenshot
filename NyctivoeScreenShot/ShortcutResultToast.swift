//
//  ShortcutResultToast.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/13/26.
//

import AppKit
import SwiftUI

struct AutomationResultToastPreferences: Equatable {
    static let `default` = AutomationResultToastPreferences(
        success: AutomationResultToastConfiguration(
            text: "{automation} complete",
            color: .green
        ),
        failure: AutomationResultToastConfiguration(
            text: "{automation} failed: {message}",
            color: .red
        )
    )

    var success: AutomationResultToastConfiguration
    var failure: AutomationResultToastConfiguration
}

struct AutomationResultToastConfiguration: Equatable {
    var text: String
    var color: AutomationResultToastColor

    func resolvedText(automationName: String, record: ScreenshotRecord, summary: ScreenshotAutomationSummary) -> String {
        var resolvedText = text
        let fallbackMessage = summary.statusMessage ?? automationName
        let replacements = [
            "{automation}": automationName,
            "{message}": fallbackMessage,
            "{fileName}": record.fileName,
            "{failures}": String(summary.failureCount)
        ]

        for (placeholder, value) in replacements {
            resolvedText = resolvedText.replacingOccurrences(of: placeholder, with: value)
        }

        let trimmedText = resolvedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? fallbackMessage : trimmedText
    }
}

enum AutomationResultToastColor: String, CaseIterable, Identifiable {
    case green
    case red
    case blue
    case orange
    case purple
    case gray

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .green:
            "Green"
        case .red:
            "Red"
        case .blue:
            "Blue"
        case .orange:
            "Orange"
        case .purple:
            "Purple"
        case .gray:
            "Gray"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .green:
            .green
        case .red:
            .red
        case .blue:
            .blue
        case .orange:
            .orange
        case .purple:
            .purple
        case .gray:
            .gray
        }
    }
}

@MainActor
final class AutomationResultToastController {
    private let cardSize = CGSize(width: 340, height: 56)
    // Transparent breathing room around the card so the drop shadow renders
    // fully instead of being clipped at the window edge.
    private let shadowPadding: CGFloat = 36
    private let bottomMargin: CGFloat = 48
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    private var windowSize: CGSize {
        CGSize(
            width: cardSize.width + shadowPadding * 2,
            height: cardSize.height + shadowPadding * 2
        )
    }

    func show(text: String, color: AutomationResultToastColor) {
        dismissalTask?.cancel()

        let frame = frame(for: windowSize)
        let toastPanel = panel ?? makePanel(frame: frame)
        toastPanel.setFrame(frame, display: true)
        toastPanel.contentViewController = NSHostingController(
            rootView: AutomationResultToastView(text: text, color: color)
                .frame(width: cardSize.width, height: cardSize.height)
                .padding(shadowPadding)
                .frame(width: windowSize.width, height: windowSize.height)
        )

        panel = toastPanel
        toastPanel.alphaValue = 0
        toastPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toastPanel.animator().alphaValue = 1
        }

        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_400_000_000)
            } catch {
                return
            }

            await MainActor.run {
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil

        guard let panel else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        panel.orderOut(nil)
        self.panel = nil
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        return panel
    }

    private func frame(for size: CGSize) -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        return CGRect(
            x: visibleFrame.midX - size.width / 2,
            // Offset by shadowPadding so the visible card—not the padded
            // window—ends up bottomMargin above the screen edge.
            y: visibleFrame.minY + bottomMargin - shadowPadding,
            width: size.width,
            height: size.height
        )
    }
}

private struct AutomationResultToastView: View {
    let text: String
    let color: AutomationResultToastColor

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        HStack(spacing: 11) {
            // Status indicator: a soft, glowing gradient dot.
            Circle()
                .fill(color.swiftUIColor.gradient)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.40), lineWidth: 0.5)
                )
                .frame(width: 10, height: 10)
                .shadow(color: color.swiftUIColor.opacity(0.35), radius: 8)

            Text(text)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(color.swiftUIColor)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pure liquid-glass surface: no colored tint overlay.
        .background {
            Color.clear
                .nyctivoeGlassBackgroundEffect(in: shape)
        }
        .overlay(
            shape.strokeBorder(.white.opacity(0.25), lineWidth: 1)
        )
        .clipShape(shape)
        // Ambient shadows: subtle depth plus a faint status glow to keep it from
        // blending into the desktop background.
        .shadow(color: color.swiftUIColor.opacity(0.18), radius: 16, x: 0, y: 4)
        .shadow(color: .black.opacity(0.12), radius: 28, x: 0, y: 16)
    }
}
