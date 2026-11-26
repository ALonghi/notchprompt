//
//  MainWindowController.swift
//  notchprompt
//

import AppKit
import Combine
import SwiftUI

/// Requests the main window's views react to (focus the editor, and so on).
@MainActor
final class MainWindowState: ObservableObject {
    /// Incremented to move keyboard focus into the script editor.
    @Published var editorFocusRequest = 0
}

/// The one Notchprompt window: the script editor with the settings beside it.
@MainActor
final class MainWindowController: NSWindowController {
    enum Destination {
        case script
        case settings
    }

    static let shared = MainWindowController()

    /// Above the notch overlay (.screenSaver), so the overlay never covers the
    /// title bar. Only while Notchprompt is the active app; otherwise the window
    /// sits at the normal level instead of floating over other apps.
    private static let activeLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    private static let autosaveName = "NotchpromptMainWindow"

    private let state = MainWindowState()
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let hosting = NSHostingController(rootView: MainWindowView(state: state))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchprompt"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 540)
        window.setContentSize(NSSize(width: 960, height: 640))
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)

        super.init(window: window)

        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification),
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.window?.level = NSApp.isActive ? Self.activeLevel : .normal
        }
        .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ destination: Destination = .script) {
        NSApp.activate(ignoringOtherApps: true)
        window?.level = Self.activeLevel
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Last resort if another always-on-top window exists.
        window?.orderFrontRegardless()

        if destination == .script {
            state.editorFocusRequest += 1
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var state: MainWindowState

    var body: some View {
        HStack(spacing: 0) {
            ScriptEditorView(state: state)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            SettingsView()
                .frame(width: 360)
                .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 540)
    }
}
