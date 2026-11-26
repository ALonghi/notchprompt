//
//  ScriptEditorView.swift
//  notchprompt
//
//  Created by Codex on 2026-02-23.
//

import AppKit
import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject private var model = PrompterModel.shared
    @ObservedObject var state: MainWindowState

    @FocusState private var isEditorFocused: Bool
    @State private var isConfirmingClear = false
    @State private var fileErrorMessage: String?

    private var isPlaying: Bool {
        model.isRunning || model.isCountingDown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            editor
            footer
        }
        .padding(20)
        .onAppear {
            DispatchQueue.main.async { isEditorFocused = true }
        }
        .onChange(of: state.editorFocusRequest) { _, _ in
            isEditorFocused = true
        }
        .confirmationDialog("Clear the script?", isPresented: $isConfirmingClear) {
            Button("Clear Script", role: .destructive) {
                model.clearScript()
            }
        } message: {
            Text("All text in the script will be removed. This can't be undone.")
        }
        .alert("File Operation Failed", isPresented: Binding(
            get: { fileErrorMessage != nil },
            set: { _ in fileErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileErrorMessage ?? "This file operation could not be completed.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Script")
                    .font(.title2.weight(.semibold))
                Text("Your transcript or talking points. Edits show in the notch overlay right away.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await importScriptAsync() }
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .help("Replace the script with text from a document")

            Button {
                Task { await exportScriptAsync() }
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .disabled(!model.hasScript)
            .help("Save the script as TXT, Markdown, RTF, Word or OpenDocument")
        }
    }

    private var editor: some View {
        ZStack {
            TextEditor(text: $model.script)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .focused($isEditorFocused)

            if model.script.isEmpty {
                emptyEditorPrompt
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var emptyEditorPrompt: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Your script goes here")
                    .font(.title3.weight(.semibold))
                Text("Copy your transcript from anywhere and paste it here,\nor start typing. Have a file? Import TXT, Markdown, RTF, Word, Pages or PDF.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            // Clicks that miss the buttons go to the text editor underneath.
            .allowsHitTesting(false)

            HStack(spacing: 10) {
                Button {
                    model.pasteFromClipboard()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .help("Use the text on your clipboard as the script (or click in the editor and press ⌘V)")

                Button {
                    Task { await importScriptAsync() }
                } label: {
                    Label("Import File…", systemImage: "doc")
                }
            }
            .controlSize(.large)
        }
        .padding(24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(statsText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!model.hasScript)

            Button {
                model.toggleRunning()
            } label: {
                Label(isPlaying ? "Pause" : "Start Prompting", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.hasScript && !isPlaying)
            .help("Start or pause the overlay (⌘↩ here, ⌥⌘P anywhere)")
        }
        .controlSize(.large)
    }

    private var statsText: String {
        guard model.hasScript else { return "No script yet" }
        let words = model.wordCount
        return "\(words) word\(words == 1 ? "" : "s") · \(model.formattedEstimatedReadDuration()) at the current speed"
    }

    @MainActor
    private func importScriptAsync() async {
        let url = await FilePanelCoordinator.presentImportPanel(from: NSApp.keyWindow)
        guard let url else { return }
        do {
            model.script = try await ScriptFileIO.importText(from: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportScriptAsync() async {
        let url = await FilePanelCoordinator.presentExportPanel(from: NSApp.keyWindow)
        guard let url else { return }
        do {
            try await ScriptFileIO.exportText(model.script, to: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }
}
