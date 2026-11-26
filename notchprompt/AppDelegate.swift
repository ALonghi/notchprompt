//
//  AppDelegate.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let shortcutModifiers: NSEvent.ModifierFlags = [.command, .option]

    private let model = PrompterModel.shared

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private lazy var hotkeyManager = GlobalHotkeyManager { [weak self] command in
        self?.performShortcut(command)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.loadFromDefaults()
        // Selections saved by earlier versions have no display name; record it
        // so the display can be found again if its ID changes.
        if model.selectedScreenID != 0, model.selectedScreenName.isEmpty,
           let display = DisplayCatalog.shared.display(withID: model.selectedScreenID) {
            model.selectedScreenName = display.name
        }
        overlayController = OverlayWindowController(model: model)
        overlayController?.setVisible(model.isOverlayVisible)

#if DEBUG
        ScreenSelectionSelfTests.run()
        runShortcutSelfChecks()
#endif

        setupEditMenu()
        wireModel()
        hotkeyManager.registerAll()
        setupStatusBar()
        installEditKeyHandler()

        // First launch, or nothing to prompt: open the editor so it's obvious
        // where the script goes.
        if model.isFirstLaunch || !model.hasScript {
            MainWindowController.shared.show(.script)
        }
    }

    /// Opening the app again (Dock, Finder, Spotlight) shows the editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show(.script)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveToDefaults()
        hotkeyManager.unregisterAll()
        cancellables.removeAll()
    }

    private func wireModel() {
        model.$privacyModeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.overlayController?.setPrivacyMode(enabled)
            }
            .store(in: &cancellables)
        
        model.$isOverlayVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.overlayController?.setVisible(isVisible)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$overlayWidth, model.$overlayHeight)
            .removeDuplicates { lhs, rhs in
                Int(lhs.0) == Int(rhs.0) && Int(lhs.1) == Int(rhs.1)
            }
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        model.$selectedScreenID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
#if DEBUG
                print("[Notchprompt] didChangeScreenParametersNotification")
#endif
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            model.$script.map { _ in () }.eraseToAnyPublisher(),
            model.$isRunning.map { _ in () }.eraseToAnyPublisher(),
            model.$privacyModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            model.$speedPointsPerSecond.map { _ in () }.eraseToAnyPublisher(),
            model.$fontSize.map { _ in () }.eraseToAnyPublisher(),
            model.$overlayWidth.map { _ in () }.eraseToAnyPublisher(),
            model.$overlayHeight.map { _ in () }.eraseToAnyPublisher(),
            model.$countdownSeconds.map { _ in () }.eraseToAnyPublisher(),
            model.$countdownBehavior.map { _ in () }.eraseToAnyPublisher(),
            model.$scrollMode.map { _ in () }.eraseToAnyPublisher(),
            model.$selectedScreenID.map { _ in () }.eraseToAnyPublisher(),
            model.$selectedScreenName.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.model.saveToDefaults()
        }
        .store(in: &cancellables)
    }

    private func setupEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        if let mainMenu = NSApp.mainMenu {
            mainMenu.addItem(editMenuItem)
        } else {
            let mainMenu = NSMenu()
            mainMenu.addItem(editMenuItem)
            NSApp.mainMenu = mainMenu
        }
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "NP"
        item.button?.toolTip = "Notchprompt"

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    // MARK: - NSMenuDelegate

    /// Rebuilt on every open so titles, check marks and the display list are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        addShortcutWarnings(to: menu)

        let isPlaying = model.isRunning || model.isCountingDown
        let startPause = shortcutItem(isPlaying ? "Pause" : "Start", .startPause)
        startPause.isEnabled = isPlaying || model.hasScript
        menu.addItem(startPause)
        menu.addItem(shortcutItem("Reset Scroll", .reset))
        menu.addItem(shortcutItem("Jump Back 5s", .jumpBack))
        menu.addItem(shortcutItem("Increase Speed", .speedUp))
        menu.addItem(shortcutItem("Decrease Speed", .speedDown))

        menu.addItem(.separator())

        let editScript = ActionMenuItem(title: "Edit Script…") {
            MainWindowController.shared.show(.script)
        }
        editScript.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        menu.addItem(editScript)

        let paste = ActionMenuItem(title: model.pasteMenuTitle) { [model] in
            model.pasteFromClipboard()
        }
        paste.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(paste)

        menu.addItem(.separator())

        menu.addItem(AppMenus.displaySubmenuItem(title: "Display", model: model))
        let showOverlay = shortcutItem("Show Overlay", .toggleOverlay)
        showOverlay.state = model.isOverlayVisible ? .on : .off
        menu.addItem(showOverlay)
        let privacyMode = shortcutItem("Privacy Mode", .togglePrivacy)
        privacyMode.state = model.privacyModeEnabled ? .on : .off
        privacyMode.toolTip = "Hide the overlay from screen sharing and recordings (best effort)."
        menu.addItem(privacyMode)

        menu.addItem(.separator())

        menu.addItem(ActionMenuItem(title: "Settings…", keyEquivalent: ",") {
            MainWindowController.shared.show(.settings)
        })

        menu.addItem(.separator())

        menu.addItem(ActionMenuItem(title: "Quit Notchprompt", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    /// A menu item for a command that also has a global shortcut.
    private func shortcutItem(_ title: String, _ command: ShortcutCommand) -> NSMenuItem {
        ActionMenuItem(title: title, keyEquivalent: command.keyEquivalent, modifiers: shortcutModifiers) { [weak self] in
            self?.performShortcut(command)
        }
    }

    // MARK: - Edit key handler (Cmd+C/V/X/A/Z bypass for menu-bar apps)

    private func installEditKeyHandler() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command ||
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] else {
                return event
            }
            let key = event.charactersIgnoringModifiers ?? ""
            let action: Selector? = switch key {
            case "x": #selector(NSText.cut(_:))
            case "c": #selector(NSText.copy(_:))
            case "v": #selector(NSText.paste(_:))
            case "a": #selector(NSText.selectAll(_:))
            case "z" where event.modifierFlags.contains(.shift): NSSelectorFromString("redo:")
            case "z": NSSelectorFromString("undo:")
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: nil) {
                return nil
            }
            return event
        }
    }

    // MARK: - Actions

    private func performShortcut(_ command: ShortcutCommand) {
        switch command {
        case .startPause:
            if !model.hasScript && !model.isRunning && !model.isCountingDown {
                // Nothing to prompt yet: show where the script goes.
                MainWindowController.shared.show(.script)
            } else {
                model.toggleRunning()
            }
        case .reset:
            model.resetScroll()
        case .jumpBack:
            model.jumpBack(seconds: 5)
        case .togglePrivacy:
            model.privacyModeEnabled.toggle()
        case .toggleOverlay:
            model.isOverlayVisible.toggle()
        case .speedUp:
            model.adjustSpeed(delta: PrompterModel.speedStep)
        case .speedDown:
            model.adjustSpeed(delta: -PrompterModel.speedStep)
        }
    }

    private func addShortcutWarnings(to menu: NSMenu) {
        let unavailable = hotkeyManager.failedRegistrations
        guard !unavailable.isEmpty else { return }

        if unavailable.count == 1, let first = unavailable.first {
            let warning = NSMenuItem(
                title: "Shortcut unavailable: \(first.displayShortcut) (in use by another app)",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
        } else {
            let warning = NSMenuItem(
                title: "Shortcuts unavailable (\(unavailable.count))",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)

            let detail = unavailable
                .map(\.displayShortcut)
                .joined(separator: ", ")
            let detailItem = NSMenuItem(
                title: "In use by another app: \(detail)",
                action: nil,
                keyEquivalent: ""
            )
            detailItem.isEnabled = false
            menu.addItem(detailItem)
        }

        menu.addItem(.separator())
    }

#if DEBUG
    private func runShortcutSelfChecks() {
        GlobalHotkeyManager.runSelfChecks()
    }
#endif
}
