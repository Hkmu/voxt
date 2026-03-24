import SwiftUI

struct VoiceEndCommandSettingsSection: View {
    @AppStorage(AppPreferenceKey.voiceEndCommandEnabled) private var voiceEndCommandEnabled = false
    @AppStorage(AppPreferenceKey.voiceEndCommandPreset) private var voiceEndCommandPresetRaw = VoiceEndCommandPreset.over.rawValue
    @AppStorage(AppPreferenceKey.voiceEndCommandText) private var voiceEndCommandText = ""

    private var voiceEndCommandPreset: Binding<VoiceEndCommandPreset> {
        Binding(
            get: { VoiceEndCommandPreset(rawValue: voiceEndCommandPresetRaw) ?? .over },
            set: { voiceEndCommandPresetRaw = $0.rawValue }
        )
    }

    private var voiceEndCommandTextBinding: Binding<String> {
        Binding(
            get: { voiceEndCommandPreset.wrappedValue.resolvedCommand ?? voiceEndCommandText },
            set: { newValue in
                guard voiceEndCommandPreset.wrappedValue == .custom else { return }
                voiceEndCommandText = newValue
            }
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Voice End Command")
                    .font(.headline)
                Toggle("Enable Voice End Command", isOn: $voiceEndCommandEnabled)
                Text("When enabled, Voxt treats the configured spoken command as a stop action. If that command appears at the end of the transcript and there is about 1 second of silence after it, the session ends automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Preset")
                        .foregroundStyle(.secondary)
                    Spacer()
                    SettingsMenuPicker(
                        selection: voiceEndCommandPreset,
                        options: VoiceEndCommandPreset.allCases.map { preset in
                            SettingsMenuOption(value: preset, title: preset.title)
                        },
                        selectedTitle: voiceEndCommandPreset.wrappedValue.title,
                        width: 220
                    )
                }
                .disabled(!voiceEndCommandEnabled)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Command")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("over", text: voiceEndCommandTextBinding)
                        .textFieldStyle(.plain)
                        .settingsFieldSurface(width: 220)
                }
                .disabled(!voiceEndCommandEnabled || voiceEndCommandPreset.wrappedValue != .custom)

                Text("Available presets are over, end, and 完毕. Command matching ignores surrounding spaces and punctuation, including Asian punctuation such as ， 。 ！ ？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
