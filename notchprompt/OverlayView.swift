//
//  OverlayView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import SwiftUI

private extension Color {
    /// `#000000` (darkest black for seamless notch blending)
    static let notchBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1.0)
}

/// MacBook-style notch contour:
/// - flat top edge with square top corners
/// - straight side walls
/// - rounded lower corners
private struct AppleNotchShape: InsettableShape {
    /// Lower corner radius relative to height.
    var bottomCornerRadiusRatio: CGFloat = 0.18
    /// Portion of total height used by the straight side wall.
    var sideWallDepthRatio: CGFloat = 0.82
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }

        let w = r.width
        let h = r.height

        // sideWallDepthRatio controls how much vertical wall exists before lower arcs.
        let depthRatio = max(0.60, min(sideWallDepthRatio, 0.95))
        let lowerArcStartY = r.minY + (h * depthRatio)
        let maxBottomRadiusFromDepth = max(0, r.maxY - lowerArcStartY)
        let maxBottomRadiusFromWidth = w * 0.5
        let targetBottomRadius = h * bottomCornerRadiusRatio
        let bottomRadius = max(
            0,
            min(targetBottomRadius, min(maxBottomRadiusFromDepth, maxBottomRadiusFromWidth))
        )

        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))

        // Right side wall into large lower corner.
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))
        if bottomRadius > 0 {
            p.addArc(
                center: CGPoint(x: r.maxX - bottomRadius, y: r.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }

        p.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))
        if bottomRadius > 0 {
            p.addArc(
                center: CGPoint(x: r.minX + bottomRadius, y: r.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }

        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()

        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.insetAmount += amount
        return s
    }
}

struct OverlayView: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject private var catalog = DisplayCatalog.shared
    /// Opens an AppKit menu under the overlay.
    let presentMenu: (NSMenu) -> Void
    /// Called with the mouse location (screen coordinates) when the user drops
    /// the overlay after dragging it.
    let onDragEnded: (NSPoint) -> Void

    private var isPlaying: Bool {
        model.isRunning || model.isCountingDown
    }

    private var playButtonHelp: String {
        if model.isCountingDown { return "Cancel the countdown" }
        return model.isRunning ? "Pause (then scroll with the trackpad to move by hand)" : "Start scrolling"
    }

    /// Room for one group of controls between the overlay's edge and the
    /// camera housing, which hides anything drawn behind it.
    private var sideWidth: CGFloat {
        let notchWidth = catalog
            .selectionState(selectedID: model.selectedScreenID, selectedName: model.selectedScreenName)
            .overlayDisplay?.notchWidth ?? 0
        return (CGFloat(model.overlayWidth) - notchWidth) / 2 - 10
    }

    var body: some View {
        // Ratio-driven contour tuned to Apple notch geometry and scaled to the
        // current overlay dimensions.
        let shape = AppleNotchShape()
        let hideTopStrokeHeight: CGFloat = 2

        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(shape)
                // Blur can brighten the surface; keep it effectively off for notch matching.
                .opacity(0.0)

            shape
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: model.backgroundOpacity))

            shape
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                // Hard-cut the stroke off at the very top so the edge blends into the notch.
                .mask(
                    VStack(spacing: 0) {
                        Color.clear.frame(height: hideTopStrokeHeight)
                        Color.white
                    }
                )

            // The scroller is hard-clipped (so text truly "cuts off") and we add
            // subtle blur bands at the top/bottom to soften the exit.
            ScrollingTextView(
                text: model.script,
                fontSize: CGFloat(model.fontSize),
                speedPointsPerSecond: model.speedPointsPerSecond,
                isRunning: model.isRunning,
                hasStartedSession: model.hasStartedSession,
                resetToken: model.resetToken,
                jumpBackToken: model.jumpBackToken,
                jumpBackDistancePoints: model.jumpBackDistancePoints,
                manualScrollToken: model.manualScrollToken,
                manualScrollDeltaPoints: model.manualScrollDeltaPoints,
                fadeFraction: CGFloat(model.edgeFadeFraction),
                backgroundOpacity: model.backgroundOpacity,
                isHovering: false,
                scrollMode: model.scrollMode,
                savedScrollPhaseForResume: model.savedScrollPhaseForResume,
                onSaveScrollPhaseForResume: { phase in
                    model.saveScrollPhaseForResume(phase)
                },
                onReachedEnd: {
                    if model.isRunning {
                        model.markReachedEndInStopMode()
                    }
                }
            )
            .padding(.horizontal, 18)
            .padding(.top, 58)
            .padding(.bottom, 16)
            .clipShape(Rectangle())
            .overlay {
                // Covers the whole overlay: trackpad scrolling, dragging to
                // another display, and double-click to edit.
                TrackpadScrollCaptureView(
                    onScroll: { delta in
                        model.handleManualScroll(deltaPoints: delta)
                    },
                    onDragEnded: onDragEnded,
                    onDoubleClick: {
                        MainWindowController.shared.show(.script)
                    }
                )
            }

            if model.isCountingDown {
                ZStack {
                    Color.black.opacity(0.92)
                    Text("\(model.countdownRemaining)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            } else if !model.hasScript {
                emptyState
            }

            controls
        }
        .frame(width: model.overlayWidth, height: model.overlayHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No script yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 8) {
                OverlayPillButton(title: "Paste from Clipboard", symbol: "doc.on.clipboard", isProminent: true) {
                    model.pasteFromClipboard()
                }
                .help("Use the text on your clipboard as the script (or click here and press ⌘V)")

                OverlayPillButton(title: "Open Editor", symbol: "square.and.pencil") {
                    MainWindowController.shared.show(.script)
                }
                .help("Type, paste or import your script in the editor")
            }
        }
        // Keep clear of the control row and the camera housing above it.
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(alignment: .top) {
            OverlayControlGroup {
                OverlayControlButton(symbol: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Start") {
                    model.switchPlaybackModeFromOverlayControl()
                }
                .help(playButtonHelp)
                .disabled(!model.hasScript && !isPlaying)

                OverlayControlButton(symbol: "gobackward.5", label: "Jump Back 5 Seconds") {
                    model.jumpBack(seconds: 5)
                }
                .help("Jump back 5 seconds")
                .disabled(!model.hasScript)

                OverlayControlButton(symbol: "minus", label: "Slower", repeatWhilePressed: true) {
                    model.adjustSpeed(delta: -PrompterModel.speedStep)
                }
                .help("Slower")

                // Shown only when it fits beside the camera housing.
                if sideWidth >= 152 {
                    Text("\(Int(model.speedPointsPerSecond))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 24, height: 22)
                        .help("Scroll speed")
                }

                OverlayControlButton(symbol: "plus", label: "Faster", repeatWhilePressed: true) {
                    model.adjustSpeed(delta: PrompterModel.speedStep)
                }
                .help("Faster")
            }

            Spacer(minLength: 8)

            OverlayControlGroup {
                OverlayControlButton(symbol: "square.and.pencil", label: "Edit Script") {
                    MainWindowController.shared.show(.script)
                }
                .help("Edit script")

                if catalog.displays.count > 1 {
                    OverlayControlButton(symbol: "display.2", label: "Move to Display") {
                        presentMenu(AppMenus.displayMenu(model: model))
                    }
                    .help("Move to another display")
                }

                OverlayControlButton(symbol: "ellipsis", label: "More") {
                    presentMenu(AppMenus.overlayMenu(model: model))
                }
                .help("More")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct OverlayControlGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct OverlayControlButton: View {
    let symbol: String
    /// Spoken by VoiceOver; SF Symbol names make poor labels ("Add", "Remove").
    let label: String
    var isActive: Bool = false
    var repeatWhilePressed: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // Use SwiftUI Button (not onLongPressGesture) so we benefit from
        // the macOS 15 click-through fix for non-activating panels (FB13720950).
        Button {
            if !repeatWhilePressed { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(
            OverlayCircleButtonStyle(
                isActive: isActive,
                repeatWhilePressed: repeatWhilePressed,
                repeatAction: action
            )
        )
        .accessibilityLabel(label)
    }
}

/// A labeled capsule button for the overlay's empty state.
private struct OverlayPillButton: View {
    let title: String
    let symbol: String
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(OverlayPillButtonStyle(isProminent: isProminent))
    }
}

private struct OverlayPillButtonStyle: ButtonStyle {
    var isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let base = isProminent ? 0.24 : 0.12
        return configuration.label
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? base + 0.1 : base))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

/// Button style that provides press-highlight and optional repeat-while-held.
private struct OverlayCircleButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var repeatWhilePressed: Bool = false
    var repeatAction: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed || isActive ? 0.18 : 0.10))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .background {
                if repeatWhilePressed {
                    RepeatWhileHeldHelper(
                        isPressed: configuration.isPressed,
                        action: repeatAction ?? {}
                    )
                }
            }
    }
}

/// Zero-size helper that fires an action on press-down and repeats while held.
private struct RepeatWhileHeldHelper: View {
    let isPressed: Bool
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    action()
                    startRepeating()
                } else {
                    stopRepeating()
                }
            }
            .onDisappear { stopRepeating() }
    }

    private func startRepeating() {
        stopRepeating()
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            while !Task.isCancelled {
                await MainActor.run { action() }
                try? await Task.sleep(nanoseconds: 85_000_000)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct TrackpadScrollCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    var onDragEnded: (NSPoint) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        let view = ScrollCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: ScrollCaptureNSView) {
        let onScroll = onScroll
        view.onScroll = { event in
            let rawDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
            let semanticDelta = event.isDirectionInvertedFromDevice ? rawDelta : -rawDelta
            onScroll(semanticDelta)
        }
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
    }
}

/// Catches trackpad scrolling, drags (the window follows the pointer until
/// it is dropped) and double-clicks on the overlay background.
final class ScrollCaptureNSView: NSView {
    var onScroll: ((NSEvent) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onDoubleClick: (() -> Void)?

    /// How far the pointer moves before a press becomes a drag.
    private static let dragThreshold: CGFloat = 4

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        isDragging = false
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        if !isDragging {
            guard hypot(dx, dy) >= Self.dragThreshold else { return }
            isDragging = true
            NSCursor.closedHand.push()
        }
        window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        dragStartMouse = nil
        dragStartOrigin = nil
        isDragging = false
        guard wasDragging else { return }
        NSCursor.pop()
        onDragEnded?(NSEvent.mouseLocation)
    }
}
