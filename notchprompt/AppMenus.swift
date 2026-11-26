//
//  AppMenus.swift
//  notchprompt
//

import AppKit

/// A menu item that runs a closure, so menus can be built without a target object.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(performHandler(_:)), keyEquivalent: keyEquivalent)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performHandler(_ sender: Any?) {
        handler()
    }
}

extension PrompterModel {
    /// Replaces the script with the text on the clipboard. Beeps and returns
    /// false when the clipboard holds no text.
    @discardableResult
    func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return false
        }
        pasteScript(text)
        return true
    }

    var pasteMenuTitle: String {
        hasScript ? "Replace Script with Clipboard" : "Paste Script from Clipboard"
    }
}

/// Menus shared by the menu bar item, the overlay's buttons and its
/// right-click menu, so every entry point offers the same choices.
@MainActor
enum AppMenus {
    /// "Automatic" and every connected display, with the current choice checked.
    static func displayMenu(model: PrompterModel) -> NSMenu {
        let catalog = DisplayCatalog.shared
        catalog.refresh()
        let state = catalog.selectionState(selectedID: model.selectedScreenID, selectedName: model.selectedScreenName)

        let menu = NSMenu(title: "Display")
        menu.autoenablesItems = false

        let automatic = ActionMenuItem(title: catalog.automaticTitle) {
            model.selectDisplay(id: 0, name: "")
        }
        automatic.toolTip = "Use the built-in display when it is available, otherwise the main display."
        if case .automatic = state {
            automatic.state = .on
        }
        menu.addItem(automatic)
        menu.addItem(.separator())

        for display in catalog.displays {
            let item = ActionMenuItem(title: display.name) {
                model.selectDisplay(id: display.id, name: display.name)
            }
            item.image = NSImage(
                systemSymbolName: display.isBuiltIn ? "laptopcomputer" : "display",
                accessibilityDescription: nil
            )
            if case .display(let selected) = state, selected.id == display.id {
                item.state = .on
            }
            menu.addItem(item)
        }

        if case .disconnected(let name, _) = state {
            let missing = NSMenuItem(
                title: "\(name.isEmpty ? "Saved display" : name) (not connected)",
                action: nil,
                keyEquivalent: ""
            )
            missing.state = .on
            missing.isEnabled = false
            menu.addItem(missing)
        }

        return menu
    }

    static func displaySubmenuItem(title: String, model: PrompterModel) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        item.submenu = displayMenu(model: model)
        return item
    }

    /// The overlay's "more" menu and right-click menu.
    static func overlayMenu(model: PrompterModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ActionMenuItem(title: "Edit Script…") {
            MainWindowController.shared.show(.script)
        })
        menu.addItem(ActionMenuItem(title: model.pasteMenuTitle) {
            model.pasteFromClipboard()
        })
        let clear = ActionMenuItem(title: "Clear Script") {
            model.clearScript()
        }
        clear.isEnabled = model.hasScript
        menu.addItem(clear)

        if DisplayCatalog.shared.displays.count > 1 {
            menu.addItem(.separator())
            menu.addItem(displaySubmenuItem(title: "Move to Display", model: model))
        }

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Settings…") {
            MainWindowController.shared.show(.settings)
        })
        menu.addItem(ActionMenuItem(
            title: "Hide Overlay",
            keyEquivalent: ShortcutCommand.toggleOverlay.keyEquivalent,
            modifiers: [.command, .option]
        ) {
            model.isOverlayVisible = false
        })

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Quit Notchprompt") {
            NSApp.terminate(nil)
        })
        return menu
    }
}
