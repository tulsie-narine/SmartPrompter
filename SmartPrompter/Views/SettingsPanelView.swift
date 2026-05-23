import SwiftData
import SwiftUI

struct SettingsPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var script: Script
    @ObservedObject var speechScrollController: SpeechScrollController

    private var settings: PrompterSettings {
        script.settings
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    Slider(
                        value: setting(\.fontSize),
                        in: 24...96,
                        step: 1
                    ) {
                        Text("Font Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }

                    ColorPicker("Font Color", selection: fontColor, supportsOpacity: false)
                }

                Section("Scroll") {
                    Slider(
                        value: setting(\.scrollSpeed),
                        in: 8...110,
                        step: 1
                    ) {
                        Text("Scroll Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }

                    Slider(
                        value: setting(\.margins),
                        in: 12...180,
                        step: 2
                    ) {
                        Text("Margins")
                    } minimumValueLabel: {
                        Image(systemName: "arrow.left.and.right")
                    } maximumValueLabel: {
                        Image(systemName: "rectangle.inset.filled")
                    }
                }

                Section("Display") {
                    ColorPicker("Background Color", selection: backgroundColor, supportsOpacity: false)
                    Toggle("Mirror Mode", isOn: setting(\.mirrorMode))
                    Toggle("Reading Marker", isOn: setting(\.showMarker))
                }

                Section("Smart Scroll") {
                    Toggle("Smart Voice Scroll", isOn: smartVoiceScroll)

                    LabeledContent("Permission State", value: speechScrollController.permissionState.rawValue)
                    LabeledContent("Listening", value: speechScrollController.isListening ? "On" : "Off")

                    if speechScrollController.isListening {
                        LabeledContent(
                            "Estimated Pace",
                            value: "\(Int(speechScrollController.estimatedWordsPerMinute)) WPM"
                        )
                    }
                }
            }
            .navigationTitle("Prompter Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func setting<Value>(_ keyPath: ReferenceWritableKeyPath<PrompterSettings, Value>) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { newValue in
            settings[keyPath: keyPath] = newValue
            ScriptStore.markUpdated(script, in: modelContext)
        }
    }

    private var fontColor: Binding<Color> {
        Binding {
            settings.fontColor
        } set: { newValue in
            settings.fontColor = newValue
            ScriptStore.markUpdated(script, in: modelContext)
        }
    }

    private var backgroundColor: Binding<Color> {
        Binding {
            settings.backgroundColor
        } set: { newValue in
            settings.backgroundColor = newValue
            ScriptStore.markUpdated(script, in: modelContext)
        }
    }

    private var smartVoiceScroll: Binding<Bool> {
        Binding {
            settings.smartVoiceScroll
        } set: { isEnabled in
            settings.smartVoiceScroll = isEnabled
            ScriptStore.markUpdated(script, in: modelContext)

            if isEnabled {
                Task {
                    let isAllowed = await speechScrollController.requestPermissions()
                    if isAllowed {
                        speechScrollController.startListening()
                    }
                }
            } else {
                speechScrollController.stopListening()
            }
        }
    }
}
