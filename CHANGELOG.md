# Changelog

## Unreleased

- The script editor and settings now share one window. It opens on first launch, when there is no script, and when you open the app again from the Dock or Finder.
- Paste a script straight from the clipboard: from the editor (button or `⌘V`), from the overlay's empty state, its `…` menu or `⌘V` on the overlay, or from the menu bar menu.
- Move the overlay between displays by dragging it, from a display button on the overlay, from a **Display** submenu in the menu bar menu, or by clicking a display in a map in Settings. Display choices are also matched by name, so they survive a display reconnecting with a new ID.
- The overlay shows a pause button while scrolling and the current speed, keeps its controls during the countdown so it can be cancelled, and moves Clear and Quit into a `…` menu instead of one-click buttons.
- The overlay's empty state explains what to do instead of pointing to Settings, and new installs start with an empty script instead of placeholder text.
- The editor and settings window floats above the overlay only while Notchprompt is the active app.

## 1.1.1 - 2026-02-27

- Fixed shortcut reliability by moving app-wide keyboard shortcuts to Carbon system hotkeys instead of fragile event monitors.
- Added explicit status-menu warnings when one or more shortcuts are unavailable because another app already owns them.
- Fixed pause/resume behavior so scrolling resumes from the current position instead of jumping back to the beginning.

## 1.1.0 - 2026-02-25

- Fixed macOS compatibility packaging/build settings so release artifacts advertise a minimum macOS that includes 15.7.x.
- Fixed settings usability by making the settings content scrollable and reachable at smaller window heights while keeping the window resizable.
- Fixed multi-display behavior so the overlay prefers the built-in MacBook display by default, with user-selected display override and robust fallback to menu-bar screen.
- Added release compatibility check script used in CI to print deployment target and built app minimum system version.
