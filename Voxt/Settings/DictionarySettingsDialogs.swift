import SwiftUI

struct DictionaryAdvancedSettingsDialog: View {
    @Binding var dictionaryHighConfidenceCorrectionEnabled: Bool
    @Binding var isPresented: Bool
    let dictionaryRecognitionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dictionary Advanced Settings")
                .font(.title3.weight(.semibold))

            Toggle("Allow High-Confidence Auto Correction", isOn: $dictionaryHighConfidenceCorrectionEnabled)
                .controlSize(.small)
                .disabled(!dictionaryRecognitionEnabled)

            Text("When enabled, the final output can replace very high-confidence near matches with exact dictionary terms before the text is inserted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsDialogActionRow {
                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct DictionarySuggestionIngestDialog: View {
    let pendingHistoryScanCount: Int
    let localModelOptions: [DictionaryHistoryScanModelOption]
    let remoteModelOptions: [DictionaryHistoryScanModelOption]
    let selectedModelOption: DictionaryHistoryScanModelOption?
    @Binding var selectedModelID: String
    @Binding var draftPrompt: String
    @Binding var isPresented: Bool
    let onIngest: () -> Void

    private var modelOptions: [SettingsMenuOption<String>] {
        (localModelOptions + remoteModelOptions).map { option in
            SettingsMenuOption(value: option.id, title: option.title)
        }
    }

    private var selectedModelTitle: String {
        selectedModelOption?.title ?? modelOptions.first?.title ?? String(localized: "Select Model")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "One-Click Ingest"))
                .font(.title3.weight(.semibold))

            Text(
                AppLocalization.format(
                    "%d new history records will be parsed in batches to extract candidate dictionary terms.",
                    pendingHistoryScanCount
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Model"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SettingsMenuPicker(
                    selection: $selectedModelID,
                    options: modelOptions,
                    selectedTitle: selectedModelTitle,
                    width: 250
                )

                if let selectedModelOption, !selectedModelOption.detail.isEmpty {
                    Text(selectedModelOption.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Ingest Prompt"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                PromptEditorView(
                    text: $draftPrompt,
                    height: 160,
                    contentPadding: 2
                )
            }

            Text("Voxt will scan the new history records with the selected model and write the extracted terms directly into the dictionary.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsDialogActionRow {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Apply", action: onIngest)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedModelID.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 460)
    }
}
