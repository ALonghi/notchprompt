//
//  notchpromptApp.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import SwiftUI

@main
struct notchpromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .frame(width: 380, height: 600)
        }
        .commands {
            // Settings live beside the script editor in the main window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    MainWindowController.shared.show(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
