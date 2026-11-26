//
//  OverlayWindowController.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import CoreGraphics
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Make panel key BEFORE dispatching mouse events so SwiftUI gesture
    /// recognizers process them in a key-window context.  `sendEvent` fires
    /// before any view dispatch, unlike `mouseDown` which fires after.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !isKeyWindow { makeKey() }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Shows the overlay menu on right-click.
    var onRightClick: (() -> Void)?

    /// ⌘V while the overlay is focused replaces the script with the clipboard.
    @objc func paste(_ sender: Any?) {
        Task { @MainActor in
            PrompterModel.shared.pasteFromClipboard()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}

private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayWindowController {
    private let model: PrompterModel
    private let panel: OverlayPanel
    // Keep this at 0 to hug the notch/menu bar boundary like other notch-adjacent apps.
    // We still position using `visibleFrame` so we never enter the reserved top strip.
    private let padding: CGFloat = 0
    private let inMenuBarStrip: Bool = true
    private var lastFrame: NSRect?

    init(model: PrompterModel) {
        self.model = model

        let initialFrame = NSRect(x: 0, y: 0, width: model.overlayWidth, height: model.overlayHeight)
        let panel = OverlayPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        // Use .screenSaver level to ensure it sits above the menu bar and covers the notch area.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // panel.isFloatingPanel = true // This overrides level to .floating (3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 1.0
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.sharingType = model.privacyModeEnabled ? .none : .readOnly
        self.panel = panel

        let overlay = OverlayView(
            model: model,
            presentMenu: { [weak self] menu in
                self?.presentMenu(menu)
            },
            onDragEnded: { [weak self] mouseLocation in
                self?.finishDrag(at: mouseLocation)
            }
        )
        panel.contentView = ClickThroughHostingView(rootView: overlay)
        panel.onRightClick = { [weak self] in
            guard let self else { return }
            self.presentMenu(AppMenus.overlayMenu(model: self.model))
        }

        reposition()

#if DEBUG
        debugDump(reason: "init-after-reposition", intendedScreen: targetScreen(), calc: nil)
#endif
    }

    func setVisible(_ isVisible: Bool) {
#if DEBUG
        debugDump(reason: "setVisible-before isVisible=\(isVisible)", intendedScreen: targetScreen(), calc: nil)
#endif
        if isVisible {
            // Ensure the panel can reappear even when the app is backgrounded.
            reposition()
            panel.level = .screenSaver
            panel.alphaValue = 1.0
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderOut(nil)
        }
#if DEBUG
        debugDump(reason: "setVisible-after isVisible=\(isVisible)", intendedScreen: targetScreen(), calc: nil)
#endif
    }

    func reposition() {
        guard let screen = targetScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let width = CGFloat(model.overlayWidth)
        let desiredHeight = CGFloat(model.overlayHeight)

        let x = (screen.frame.midX - (width / 2)).rounded()

        // Always pin to the very top of the physical screen so we cover the notch/menu bar
        // even when macOS auto-hides the menu bar (reservedTop may report as 0).
        let height = desiredHeight
        let topRefY = screen.frame.maxY
        let y = (topRefY - height - padding).rounded()
        let targetFrame = NSRect(x: x, y: y, width: width.rounded(), height: height.rounded())

#if DEBUG
        debugDump(
            reason: "reposition-pre",
            intendedScreen: screen,
            calc: Calc(width: width, height: height, padding: padding, x: x, y: y, topSafeY: topRefY)
        )
#endif

        // Compare with the live frame, not lastFrame, so an overlay dropped
        // after a drag glides into place.
        let shouldAnimate: Bool
        if lastFrame != nil {
            let currentFrame = panel.frame
            let movedEnough = abs(currentFrame.origin.x - targetFrame.origin.x) > 0.5 ||
                abs(currentFrame.origin.y - targetFrame.origin.y) > 0.5
            let resizedEnough = abs(currentFrame.size.width - targetFrame.size.width) > 0.5 ||
                abs(currentFrame.size.height - targetFrame.size.height) > 0.5
            shouldAnimate = movedEnough || resizedEnough
        } else {
            shouldAnimate = false
        }

        panel.setFrame(targetFrame, display: true, animate: shouldAnimate)
        lastFrame = targetFrame
        
        // Ensure level is re-applied in case something reset it
        panel.level = .screenSaver
        panel.alphaValue = 1.0

#if DEBUG
        debugDump(
            reason: "reposition-post",
            intendedScreen: screen,
            calc: Calc(width: width, height: height, padding: padding, x: x, y: y, topSafeY: topRefY)
        )
#endif
    }

    func setPrivacyMode(_ enabled: Bool) {
        panel.sharingType = enabled ? .none : .readOnly
#if DEBUG
        debugDump(
            reason: "setPrivacyMode enabled=\(enabled) sharingType=\(panel.sharingType.rawValue)",
            intendedScreen: targetScreen(),
            calc: nil
        )
#endif
    }

    /// Opens `menu` just below the overlay, under the pointer. Opening it over
    /// the overlay would hide the script behind the menu.
    func presentMenu(_ menu: NSMenu) {
        let frame = panel.frame
        // Clamped to the overlay for presses that don't come from the mouse
        // (VoiceOver, accessibility tools).
        let x = min(max(NSEvent.mouseLocation.x - 14, frame.minX), frame.maxX - 40)
        let location = NSPoint(x: x, y: frame.minY - 4)
        // Let the click that opened the menu finish first.
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    /// Puts the overlay on the display it was dropped on, at the top center.
    private func finishDrag(at mouseLocation: NSPoint) {
        let catalog = DisplayCatalog.shared
        catalog.refresh()
        if let target = catalog.display(at: mouseLocation) {
            let current = catalog.resolvedDisplay(
                selectedID: model.selectedScreenID,
                selectedName: model.selectedScreenName
            )
            if target.id != current?.id {
                model.selectDisplay(id: target.id, name: target.name)
            }
        }
        reposition()
    }

    private func targetScreen() -> NSScreen? {
        let catalog = DisplayCatalog.shared
        // The screen list may have changed since the catalog last refreshed.
        catalog.refresh()
        guard let display = catalog.resolvedDisplay(
            selectedID: model.selectedScreenID,
            selectedName: model.selectedScreenName
        ) else {
            return nil
        }
        return catalog.screen(for: display.id)
    }
}

#if DEBUG
private extension OverlayWindowController {
    struct Calc {
        let width: CGFloat
        let height: CGFloat
        let padding: CGFloat
        let x: CGFloat
        let y: CGFloat
        let topSafeY: CGFloat
    }

    func debugDump(reason: String, intendedScreen: NSScreen?, calc: Calc?) {
        let level = panel.level

        let intendedName = intendedScreen?.localizedName ?? "nil"
        let intendedFrame = intendedScreen?.frame.debugDescription ?? "nil"
        let intendedVisible = intendedScreen?.visibleFrame.debugDescription ?? "nil"
        let reservedTop: CGFloat = {
            guard let s = intendedScreen else { return .nan }
            return max(0, s.frame.maxY - s.visibleFrame.maxY)
        }()

        let panelFrame = panel.frame
        let panelMaxY = panelFrame.maxY

        let actualScreen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: panelFrame.midX, y: panelFrame.midY))
        }
        let actualName = actualScreen?.localizedName ?? "nil"
        let actualFrame = actualScreen?.frame.debugDescription ?? "nil"
        let actualVisible = actualScreen?.visibleFrame.debugDescription ?? "nil"
        print("[Notchprompt][Overlay] reason=\(reason)")
        print("level=\(String(describing: level))(raw=\(level.rawValue)) ignoresMouseEvents=\(panel.ignoresMouseEvents)")
        print("panel.frame=\(panelFrame.debugDescription) panel.maxY=\(panelMaxY)")
        print("screen(name=\(intendedName), frame=\(intendedFrame), visible=\(intendedVisible), reservedTop=\(reservedTop))")
        if let calc {
            print("calc(width=\(calc.width), height=\(calc.height), padding=\(calc.padding), x=\(calc.x), y=\(calc.y), topSafeY=\(calc.topSafeY))")
        } else {
            print("calc(nil)")
        }
        print("actualScreen(name=\(actualName), frame=\(actualFrame), visible=\(actualVisible))")
        // Overlapping the reserved top region is expected when we intentionally cover the notch/menu bar area.
    }
}
#endif
