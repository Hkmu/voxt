import SwiftUI
import Foundation

struct RemoteProviderConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let providerTitle: String
    let credentialHint: String?
    let showsDoubaoFields: Bool
    let testTarget: RemoteProviderTestTarget
    let configuration: RemoteProviderConfiguration
    let onSave: (RemoteProviderConfiguration) -> Void

    @State private var selectedProviderModel = ""
    @State private var customModelID = ""
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var appID = ""
    @State private var accessToken = ""
    @State private var openAIChunkPseudoRealtimeEnabled = false
    @State private var isTestingConnection = false
    @State private var testResultMessage: String?
    @State private var testResultIsSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.format("Configure %@", providerTitle))
                .font(.headline)

            modelSection

            if !isDoubaoASRTest {
                endpointAndKeySection
            }

            if showsDoubaoFields {
                doubaoCredentialsSection
            }

            if isOpenAIASRTest {
                openAIChunkSection
            }

            if let credentialHint, !credentialHint.isEmpty {
                Text(credentialHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            actionSection

            if let testResultMessage, !testResultMessage.isEmpty {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(testResultIsSuccess ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            configureModelSelection()
            customModelID = configuration.model
            endpoint = configuration.endpoint
            apiKey = configuration.apiKey
            appID = configuration.appID
            accessToken = configuration.accessToken
            openAIChunkPseudoRealtimeEnabled = configuration.openAIChunkPseudoRealtimeEnabled
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Model", selection: providerModelSelectionBinding) {
                if let llmProvider = llmProviderForPicker {
                    ForEach(llmProvider.latestModelOptions, id: \.self) { option in
                        Text(option.title).tag(option.id)
                    }
                    ForEach(llmProvider.basicModelOptions, id: \.self) { option in
                        Text(option.title).tag(option.id)
                    }
                    ForEach(llmProvider.advancedModelOptions, id: \.self) { option in
                        Text(option.title).tag(option.id)
                    }
                    Text("Custom...").tag(customModelOptionID)
                } else {
                    ForEach(providerModelOptions, id: \.self) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if llmProviderForPicker != nil && resolvedSelectionForPicker == customModelOptionID {
                Text("Custom Model ID (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. doubao-seed-2-0-pro-260215", text: $customModelID)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var endpointAndKeySection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("Endpoint (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://...", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                if !endpointPresets.isEmpty {
                    HStack(spacing: 10) {
                        Menu("Apply Preset") {
                            ForEach(endpointPresets, id: \.id) { preset in
                                Button(preset.title) {
                                    endpoint = preset.url
                                }
                            }
                        }
                        .controlSize(.small)

                        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Clear") {
                                endpoint = ""
                            }
                            .controlSize(.small)
                        }

                        Spacer()
                    }
                    Text("Aliyun API keys are region-specific; use the matching endpoint.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Paste API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var doubaoCredentialsSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("App ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("App ID", text: $appID)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Access Token")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Paste access token", text: $accessToken)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var openAIChunkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Chunk Pseudo Realtime Preview", isOn: $openAIChunkPseudoRealtimeEnabled)
                .toggleStyle(.switch)
            Text("Enable segmented OpenAI ASR preview during recording. This roughly doubles usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        HStack {
            if isTestingConnection {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Test") {
                testConnection()
            }
            .disabled(isTestingConnection)

            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Save") {
                onSave(currentConfigurationSnapshot)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var currentConfigurationSnapshot: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            openAIChunkPseudoRealtimeEnabled: isOpenAIASRTest ? openAIChunkPseudoRealtimeEnabled : false
        )
    }

    private func testConnection() {
        let snapshot = currentConfigurationSnapshot
        isTestingConnection = true
        testResultMessage = nil
        testResultIsSuccess = false
        VoxtLog.info(
            "Remote provider test started. target=\(testTargetLogName), provider=\(configuration.providerID), model=\(snapshot.model), endpoint=\(sanitizedEndpointForLog(snapshot.endpoint)), hasAPIKey=\(!snapshot.apiKey.isEmpty), hasAppID=\(!snapshot.appID.isEmpty), hasAccessToken=\(!snapshot.accessToken.isEmpty)"
        )

        Task {
            do {
                let tester = RemoteProviderConnectivityTester(testTarget: testTarget)
                let message = try await tester.run(configuration: snapshot)
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = true
                    testResultMessage = message
                    VoxtLog.info(
                        "Remote provider test succeeded. target=\(testTargetLogName), provider=\(configuration.providerID), model=\(snapshot.model), message=\(message)"
                    )
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = false
                    testResultMessage = error.localizedDescription
                    VoxtLog.warning(
                        "Remote provider test failed. target=\(testTargetLogName), provider=\(configuration.providerID), model=\(snapshot.model), error=\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private var testTargetLogName: String {
        RemoteProviderConfigurationPolicy.testTargetLogName(testTarget)
    }

    private func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }

    private var isDoubaoASRTest: Bool {
        RemoteProviderConfigurationPolicy.isDoubaoASRTest(testTarget)
    }

    private var isOpenAIASRTest: Bool {
        RemoteProviderConfigurationPolicy.isOpenAIASRTest(testTarget)
    }

    private var customModelOptionID: String {
        RemoteProviderConfigurationPolicy.customModelOptionID
    }

    private var providerModelOptions: [RemoteModelOption] {
        RemoteProviderConfigurationPolicy.providerModelOptions(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    private var pickerModelOptionIDs: [String] {
        RemoteProviderConfigurationPolicy.pickerModelOptionIDs(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    private var resolvedSelectionForPicker: String {
        RemoteProviderConfigurationPolicy.resolvedSelection(
            target: testTarget,
            selectedProviderModel: selectedProviderModel,
            configuredModel: configuration.model
        )
    }

    private var providerModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedSelectionForPicker },
            set: {
                selectedProviderModel = $0
                if llmProviderForPicker != nil,
                   $0 != customModelOptionID,
                   customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customModelID = $0
                }
            }
        )
    }

    private var llmProviderForPicker: RemoteLLMProvider? {
        RemoteProviderConfigurationPolicy.llmProvider(for: testTarget)
    }

    private func configureModelSelection() {
        selectedProviderModel = RemoteProviderConfigurationPolicy.initialSelection(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    private func resolvedModelValue() -> String {
        RemoteProviderConfigurationPolicy.resolvedModelValue(
            target: testTarget,
            resolvedSelection: resolvedSelectionForPicker,
            customModelID: customModelID
        )
    }

    private var endpointPresets: [RemoteEndpointPreset] {
        RemoteProviderConfigurationPolicy.endpointPresets(
            target: testTarget,
            resolvedModel: resolvedModelValue()
        )
    }

}
