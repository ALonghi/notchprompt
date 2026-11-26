//
//  SettingsView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import SwiftUI
import AppKit
import CoreGraphics

struct SettingsView: View {
    @ObservedObject private var model = PrompterModel.shared
    @ObservedObject private var catalog = DisplayCatalog.shared

    var body: some View {
        Form {
            displaySection
            playbackSection
            appearanceSection
            shortcutsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Display

    private var displaySection: some View {
        let state = catalog.selectionState(
            selectedID: model.selectedScreenID,
            selectedName: model.selectedScreenName
        )

        return Section {
            DisplayArrangementView(
                displays: catalog.displays,
                overlayDisplayID: state.overlayDisplay?.id,
                overlaySize: CGSize(width: model.overlayWidth, height: model.overlayHeight)
            ) { display in
                model.selectDisplay(id: display.id, name: display.name)
            }
            .frame(height: 136)

            Picker("Show on", selection: displayPickerSelection(for: state)) {
                Text(catalog.automaticTitle).tag(CGDirectDisplayID(0))
                Divider()
                ForEach(catalog.displays) { display in
                    Text(display.name).tag(display.id)
                }
                if case .disconnected(let name, _) = state {
                    Text("\(name.isEmpty ? "Saved display" : name) (not connected)")
                        .tag(model.selectedScreenID)
                }
            }

            Toggle("Show overlay", isOn: $model.isOverlayVisible)

            Toggle(isOn: $model.privacyModeEnabled) {
                Text("Privacy mode")
                Text("Hide the overlay from screen sharing and recordings. Best effort: some apps may still capture it.")
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Click a display to move the teleprompter there, or drag the overlay onto another screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func displayPickerSelection(for state: DisplaySelectionState) -> Binding<CGDirectDisplayID> {
        Binding(
            get: {
                switch state {
                case .automatic:
                    return 0
                case .display(let display):
                    return display.id
                case .disconnected:
                    return model.selectedScreenID
                }
            },
            set: { id in
                if id == 0 {
                    model.selectDisplay(id: 0, name: "")
                } else if let display = catalog.display(withID: id) {
                    model.selectDisplay(id: display.id, name: display.name)
                }
            }
        )
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section("Playback") {
            LabeledContent("Speed") {
                slider(
                    $model.speedPointsPerSecond,
                    in: PrompterModel.speedRange,
                    step: PrompterModel.speedStep,
                    valueText: "\(Int(model.speedPointsPerSecond))"
                )
            }

            Picker("When the script ends", selection: Binding(
                get: { model.scrollMode },
                set: { model.setScrollMode($0) }
            )) {
                Text("Loop").tag(PrompterModel.ScrollMode.infinite)
                Text("Stop").tag(PrompterModel.ScrollMode.stopAtEnd)
            }
            .pickerStyle(.segmented)

            Picker("Countdown", selection: $model.countdownBehavior) {
                ForEach(PrompterModel.CountdownBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.label).tag(behavior)
                }
            }

            LabeledContent("Countdown length") {
                Stepper(value: $model.countdownSeconds, in: 0...10) {
                    Text("\(model.countdownSeconds) s")
                        .monospacedDigit()
                }
            }
            .disabled(model.countdownBehavior == .never)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            LabeledContent("Text size") {
                slider($model.fontSize, in: 12...40, step: 1, valueText: "\(Int(model.fontSize))")
            }
            LabeledContent("Overlay width") {
                slider($model.overlayWidth, in: 400...1200, step: 10, valueText: "\(Int(model.overlayWidth))")
            }
            LabeledContent("Overlay height") {
                slider($model.overlayHeight, in: 120...300, step: 2, valueText: "\(Int(model.overlayHeight))")
            }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        Section("Keyboard Shortcuts") {
            ForEach(ShortcutCommand.allCases, id: \.self) { command in
                LabeledContent(command.title) {
                    Text(command.displayShortcut)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slider(
        _ value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: 8) {
            // Rounded here rather than with `step:`, which draws a tick mark per step.
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = (($0 / step).rounded() * step) }
                ),
                in: range
            )
            .labelsHidden()
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 360, height: 640)
    }
}
#endif
