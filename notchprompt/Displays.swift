//
//  Displays.swift
//  notchprompt
//

import AppKit
import Combine
import CoreGraphics

/// A connected display, as shown in the display menus and the arrangement picker.
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    /// Localized name, numbered when identical monitors are connected.
    let name: String
    /// Frame in global AppKit coordinates (origin at the bottom-left of the primary display).
    let frame: CGRect
    let isBuiltIn: Bool
    let isMenuBarScreen: Bool
    /// Width of the camera housing at the top edge, or 0 when the display has none.
    let notchWidth: CGFloat

    var descriptor: ScreenDescriptor {
        ScreenDescriptor(id: id, localizedName: name, isBuiltIn: isBuiltIn, isMenuBarScreen: isMenuBarScreen)
    }
}

/// Where the overlay goes, as the menus and settings describe it.
enum DisplaySelectionState: Equatable {
    /// "Automatic": the built-in display, else the menu bar display.
    case automatic(resolved: DisplayInfo?)
    /// The user picked this display and it is connected.
    case display(DisplayInfo)
    /// The user picked a display that is not connected; the overlay uses `fallback`.
    case disconnected(name: String, fallback: DisplayInfo?)

    /// The display the overlay is on right now.
    var overlayDisplay: DisplayInfo? {
        switch self {
        case .automatic(let resolved):
            return resolved
        case .display(let display):
            return display
        case .disconnected(_, let fallback):
            return fallback
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Width of the camera housing at the top edge, or 0 when there is none.
    var notchWidth: CGFloat {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else {
            return 0
        }
        return max(0, right.minX - left.maxX)
    }
}

/// Live list of connected displays, refreshed when displays are connected,
/// disconnected or rearranged.
@MainActor
final class DisplayCatalog: ObservableObject {
    static let shared = DisplayCatalog()

    /// Connected displays, ordered left to right as arranged in System Settings.
    @Published private(set) var displays: [DisplayInfo] = []

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        refresh()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        let menuBarID = CGMainDisplayID()
        let current = NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let id = screen.displayID else { return nil }
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMenuBarScreen: id == menuBarID,
                notchWidth: screen.notchWidth
            )
        }
        .sorted { ($0.frame.minX, $0.frame.maxY) < ($1.frame.minX, $1.frame.maxY) }

        let updated = Self.numberingDuplicateNames(current)
        if updated != displays {
            displays = updated
        }
    }

    func display(withID id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    /// The display containing `point` (global coordinates), or the nearest one.
    func display(at point: NSPoint) -> DisplayInfo? {
        if let hit = displays.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return hit
        }
        return displays.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }

    /// The display the overlay lands on for a saved selection.
    func resolvedDisplay(selectedID: CGDirectDisplayID, selectedName: String) -> DisplayInfo? {
        guard let id = ScreenSelection.chooseScreenID(
            selectedScreenID: selectedID,
            selectedScreenName: selectedName,
            screens: displays.map(\.descriptor)
        ) else {
            return nil
        }
        return display(withID: id)
    }

    /// "Automatic", with the rule it follows right now.
    var automaticTitle: String {
        guard let resolved = resolvedDisplay(selectedID: 0, selectedName: "") else {
            return "Automatic"
        }
        if resolved.isBuiltIn {
            return "Automatic (Built-in Display)"
        }
        if resolved.isMenuBarScreen {
            return "Automatic (Main Display)"
        }
        return "Automatic (\(resolved.name))"
    }

    func selectionState(selectedID: CGDirectDisplayID, selectedName: String) -> DisplaySelectionState {
        let automatic = resolvedDisplay(selectedID: 0, selectedName: "")
        guard selectedID != 0 else {
            return .automatic(resolved: automatic)
        }
        if let resolved = resolvedDisplay(selectedID: selectedID, selectedName: selectedName),
           resolved.id == selectedID || (!selectedName.isEmpty && resolved.name == selectedName) {
            return .display(resolved)
        }
        return .disconnected(name: selectedName, fallback: automatic)
    }

    private func distance(from point: NSPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Two identical monitors report the same name; number them left to right.
    private static func numberingDuplicateNames(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        let counts = Dictionary(grouping: displays, by: \.name).mapValues(\.count)
        var seen: [String: Int] = [:]
        return displays.map { display in
            guard let count = counts[display.name], count > 1 else { return display }
            let index = (seen[display.name] ?? 0) + 1
            seen[display.name] = index
            return DisplayInfo(
                id: display.id,
                name: "\(display.name) (\(index))",
                frame: display.frame,
                isBuiltIn: display.isBuiltIn,
                isMenuBarScreen: display.isMenuBarScreen,
                notchWidth: display.notchWidth
            )
        }
    }
}
