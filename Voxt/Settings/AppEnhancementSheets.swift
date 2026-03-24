import SwiftUI

struct GroupEditorSheet: View {
    let title: String
    let actionTitle: String
    @Binding var name: String
    @Binding var prompt: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("Group Name"))
                    .font(.headline)
                TextField(AppLocalization.localizedString("Enter group name"), text: $name)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("Prompt"))
                    .font(.headline)
                PromptEditorView(text: $prompt, height: 160, contentPadding: 8)
                PromptTemplateVariablesView(
                    variables: [
                        PromptTemplateVariableDescriptor(
                            token: AppDelegate.rawTranscriptionTemplateVariable,
                            tipKey: "Template tip {{RAW_TRANSCRIPTION}}"
                        ),
                        PromptTemplateVariableDescriptor(
                            token: AppDelegate.userMainLanguageTemplateVariable,
                            tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
                        )
                    ]
                )
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                    .buttonStyle(SettingsPillButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle, action: onSave)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

struct URLBatchEditorSheet: View {
    let title: String
    let actionTitle: String
    @Binding var text: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("URL Patterns"))
                    .font(.headline)
                PromptEditorView(text: $text, height: 180, contentPadding: 8)

                Text(AppLocalization.localizedString("Enter one wildcard pattern per line. Examples: google.com/*, *.google.com/*, x.*.google.com/*/doc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                    .buttonStyle(SettingsPillButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle, action: onSave)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

struct URLDetailSheet: View {
    let pattern: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.localizedString("URL Detail"))
                .font(.title3.weight(.semibold))

            Text(pattern)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                        .fill(SettingsUIStyle.controlFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                        .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Close"), action: onClose)
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
