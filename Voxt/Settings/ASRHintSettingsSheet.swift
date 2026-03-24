import SwiftUI

@MainActor
struct ASRHintSettingsSheet: View {
    let target: ASRHintTarget
    let userLanguageCodes: [String]
    let mlxModelRepo: String?
    let initialSettings: ASRHintSettings
    let onSave: (ASRHintSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftSettings: ASRHintSettings

    init(
        target: ASRHintTarget,
        userLanguageCodes: [String],
        mlxModelRepo: String?,
        initialSettings: ASRHintSettings,
        onSave: @escaping (ASRHintSettings) -> Void
    ) {
        self.target = target
        self.userLanguageCodes = userLanguageCodes
        self.mlxModelRepo = mlxModelRepo
        self.initialSettings = initialSettings
        self.onSave = onSave
        _draftSettings = State(initialValue: initialSettings)
    }

    private var mainLanguage: UserMainLanguageOption {
        UserMainLanguageOption
            .sanitizedSelection(userLanguageCodes)
            .compactMap(UserMainLanguageOption.option(for:))
            .first ?? UserMainLanguageOption.fallbackOption()
    }

    private var resolvedPayload: ResolvedASRHintPayload {
        ASRHintResolver.resolve(
            target: target,
            settings: draftSettings,
            userLanguageCodes: userLanguageCodes,
            mlxModelRepo: mlxModelRepo
        )
    }

    private var languagePreview: String {
        resolvedPayload.language ?? AppLocalization.localizedString("Automatic")
    }

    private var hintsPreview: String {
        let hints = resolvedPayload.languageHints
        return hints.isEmpty ? AppLocalization.localizedString("Not applied") : hints.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Engine Hint Settings")
                    .font(.title3.weight(.semibold))
                Text(target.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Toggle("Follow User Main Language", isOn: $draftSettings.followsUserMainLanguage)

            HStack(alignment: .top, spacing: 16) {
                infoRow(label: "Primary language", value: mainLanguage.title())
                infoRow(label: "Resolved language", value: languagePreview)
            }

            if target == .aliyunBailianASR {
                infoRow(label: "Language hints", value: hintsPreview)
            }

            if target == .doubaoASR {
                infoRow(
                    label: "Chinese output",
                    value: ASRHintResolver.outputVariantDescription(for: mainLanguage)
                )
            }

            if target == .mlxAudio, let mlxModelRepo, !mlxModelRepo.isEmpty {
                infoRow(label: "Current model", value: mlxModelRepo)
            }

            Text(target.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if target.supportsPromptEditor {
                Text("Prompt")
                    .font(.subheadline.weight(.medium))
                PromptEditorView(text: $draftSettings.promptTemplate, height: 128)
                PromptTemplateVariablesView(
                    variables: [
                        PromptTemplateVariableDescriptor(
                            token: AppPreferenceKey.asrUserMainLanguageTemplateVariable,
                            tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
                        )
                    ]
                )
            }

            SettingsDialogActionRow {
                Button("Reset to Default") {
                    draftSettings = ASRHintSettingsStore.defaultSettings(for: target)
                }
                .buttonStyle(SettingsPillButtonStyle())
                .disabled(draftSettings == initialSettings && initialSettings == ASRHintSettingsStore.defaultSettings(for: target))
            } trailing: {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(ASRHintSettingsStore.sanitized(draftSettings, for: target))
                    dismiss()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func infoRow(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
