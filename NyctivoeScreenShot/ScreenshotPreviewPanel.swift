//
//  ScreenshotPreviewPanel.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenshotPreviewPanelController {
    private let minimumWindowSize = CGSize(width: 190, height: 130)
    private let optionsOverflowSize = CGSize(width: 70, height: 120)
    private let shadowOverflow: CGFloat = 18
    private var panel: NSPanel?

    func show(
        record: ScreenshotRecord,
        automationSteps: [ScreenshotAutomationStep],
        onRunAutomationStep: @escaping (ScreenshotAutomationStep, ScreenshotRecord) -> Void
    ) {
        let previewSize = size(for: record)
        let windowSize = contentWindowSize(for: previewSize)
        let panelFrame = frame(for: windowSize)

        let previewPanel = panel ?? makePanel(frame: panelFrame)
        previewPanel.minSize = contentWindowSize(for: minimumWindowSize)
        previewPanel.setFrame(panelFrame, display: true)

        let hostingController = NSHostingController(
            rootView: ScreenshotPreviewPanelView(
                previewSize: previewSize,
                record: record,
                automationSteps: automationSteps,
                onRunAutomationStep: onRunAutomationStep,
                onClose: { [weak self] in
                    self?.close()
                }
            )
            .frame(width: windowSize.width, height: windowSize.height)
        )
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        previewPanel.contentViewController = hostingController
        previewPanel.setContentSize(windowSize)
        previewPanel.setFrame(panelFrame, display: true)

        panel = previewPanel
        previewPanel.orderFrontRegardless()
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = ScreenshotPreviewPanelWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        return panel
    }

    private func size(for record: ScreenshotRecord) -> CGSize {
        let maximumSize = CGSize(width: 320, height: 220)
        guard record.pixelSize.width > 0, record.pixelSize.height > 0 else {
            return maximumSize
        }

        let scale = min(maximumSize.width / record.pixelSize.width, maximumSize.height / record.pixelSize.height)
        let fittedSize = CGSize(width: record.pixelSize.width * scale, height: record.pixelSize.height * scale)
        return CGSize(
            width: max(minimumWindowSize.width, fittedSize.width),
            height: max(minimumWindowSize.height, fittedSize.height)
        )
    }

    private func contentWindowSize(for previewSize: CGSize) -> CGSize {
        CGSize(
            width: previewSize.width + optionsOverflowSize.width + shadowOverflow,
            height: previewSize.height + optionsOverflowSize.height + shadowOverflow
        )
    }

    private func frame(for size: CGSize) -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let margin: CGFloat = 22
        return CGRect(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.minY + margin,
            width: size.width,
            height: size.height
        )
    }
}

private final class ScreenshotPreviewPanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct ScreenshotPreviewPanelView: View {
    let previewSize: CGSize
    let record: ScreenshotRecord
    let automationSteps: [ScreenshotAutomationStep]
    let onRunAutomationStep: (ScreenshotAutomationStep, ScreenshotRecord) -> Void
    let onClose: () -> Void

    private let shadowOverflow: CGFloat = 18

    @State private var isHoveringPanel = false
    @State private var isShowingActions = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear

            ZStack {
                visiblePanel
                centeredControls
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .padding(.trailing, shadowOverflow)
            .padding(.bottom, shadowOverflow)
        }
        .onDrag {
            NSItemProvider(contentsOf: record.url) ?? NSItemProvider(object: record.url as NSURL)
        }
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHoveringPanel = isHovering
                if !isHovering {
                    isShowingActions = false
                }
            }
        }
    }

    private var visiblePanel: some View {
        ZStack {
            panelBackground

            imagePreview
                .padding(14)
        }
        .overlay(panelOutline)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.34), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 11)
    }

    private var imagePreview: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
            .overlay {
                if let image = NSImage(contentsOf: record.url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }

    private var centeredControls: some View {
        HStack(spacing: 14) {
            actionMenu
            closeButton
        }
        .opacity(isHoveringPanel || isShowingActions ? 1 : 0)
        .allowsHitTesting(isHoveringPanel || isShowingActions)
    }

    private var actionMenu: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                isShowingActions.toggle()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(ScreenshotPreviewIconButtonStyle())
        .help("Options")
        .overlay(alignment: .bottom) {
            optionsPanel
                .offset(y: -54)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var optionsPanel: some View {
        if isShowingActions {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(automationSteps) { step in
                    Button {
                        onRunAutomationStep(step, record)
                        isShowingActions = false
                    } label: {
                        Label(step.title, systemImage: step.primaryEventKind.systemImage)
                    }
                    .help(step.resolvedDetails)
                }
            }
            .buttonStyle(ScreenshotPreviewMenuButtonStyle())
            .font(.system(size: 12, weight: .medium))
            .padding(7)
            .fixedSize(horizontal: true, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(ScreenshotPreviewIconButtonStyle())
        .help("Close")
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.ultraThinMaterial)
    }

    private var panelOutline: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.58), .white.opacity(0.18), .black.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

}

private struct ScreenshotPreviewIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScreenshotPreviewIconButton(configuration: configuration)
    }

    private struct ScreenshotPreviewIconButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background(.regularMaterial, in: Circle())
                .overlay(
                    Circle()
                        .fill(backgroundColor)
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(isHovering || configuration.isPressed ? 0.42 : 0.28), lineWidth: 1)
                )
                .contentShape(Circle())
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var backgroundColor: Color {
            if configuration.isPressed {
                return Color.gray.opacity(0.34)
            }

            return isHovering ? Color.gray.opacity(0.2) : Color.clear
        }
    }
}

private struct ScreenshotPreviewMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScreenshotPreviewMenuButton(configuration: configuration)
    }

    private struct ScreenshotPreviewMenuButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(backgroundColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var backgroundColor: Color {
            if configuration.isPressed {
                return Color.gray.opacity(0.28)
            }

            return isHovering ? Color.gray.opacity(0.18) : Color.clear
        }
    }
}
