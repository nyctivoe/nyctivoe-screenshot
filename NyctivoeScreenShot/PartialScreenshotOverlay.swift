//
//  PartialScreenshotOverlay.swift
//  NyctivoeScreenShot
//
//  Created by Spencer Wang on 6/8/26.
//

import AppKit

struct PartialScreenshotSelection {
    let captureRect: CGRect
}

@MainActor
final class PartialScreenshotOverlayController {
    private var window: PartialScreenshotWindow?
    private var completion: ((PartialScreenshotSelection?) -> Void)?

    func begin(completion: @escaping (PartialScreenshotSelection?) -> Void) {
        guard window == nil else {
            completion(nil)
            return
        }

        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }

        self.completion = completion

        let overlayWindow = PartialScreenshotWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        overlayWindow.backgroundColor = .clear
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = false
        overlayWindow.isOpaque = false
        overlayWindow.level = .screenSaver
        overlayWindow.isReleasedWhenClosed = false

        let overlayView = PartialScreenshotOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        overlayView.screenFrame = screen.frame
        overlayView.onFinish = { [weak self] selection in
            self?.finish(selection)
        }
        overlayWindow.contentView = overlayView

        window = overlayWindow
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow.makeKeyAndOrderFront(nil)
        overlayWindow.makeFirstResponder(overlayView)
    }

    private func finish(_ selection: PartialScreenshotSelection?) {
        window?.orderOut(nil)
        window = nil

        let activeCompletion = completion
        completion = nil
        activeCompletion?(selection)
    }
}

private final class PartialScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class PartialScreenshotOverlayView: NSView {
    var onFinish: ((PartialScreenshotSelection?) -> Void)?
    var screenFrame: CGRect = .zero

    private let minimumSelectionSize: CGFloat = 8
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        dirtyRect.fill()

        guard let selectionRect else {
            return
        }

        NSColor.white.withAlphaComponent(0.12).setFill()
        selectionRect.fill()

        let strokePath = NSBezierPath(rect: selectionRect)
        strokePath.lineWidth = 2
        NSColor.systemBlue.setStroke()
        strokePath.stroke()

        drawDimensions(for: selectionRect)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)

        guard let selectionRect,
              selectionRect.width >= minimumSelectionSize,
              selectionRect.height >= minimumSelectionSize
        else {
            cancel()
            return
        }

        onFinish?(PartialScreenshotSelection(captureRect: captureRect(for: selectionRect)))
    }

    override func rightMouseDown(with event: NSEvent) {
        cancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancel()
            return
        }

        super.keyDown(with: event)
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else {
            return nil
        }

        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        ).intersection(bounds)
    }

    private func captureRect(for selectionRect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + selectionRect.minX,
            y: screenFrame.maxY - selectionRect.maxY,
            width: selectionRect.width,
            height: selectionRect.height
        ).integral
    }

    private func drawDimensions(for selectionRect: CGRect) {
        let label = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = label.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: selectionRect.minX,
            y: max(selectionRect.minY - textSize.height - 10, bounds.minY + 10),
            width: textSize.width + 16,
            height: textSize.height + 8
        )

        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.74).setFill()
        backgroundPath.fill()

        label.draw(
            at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4),
            withAttributes: attributes
        )
    }

    private func cancel() {
        onFinish?(nil)
    }
}
