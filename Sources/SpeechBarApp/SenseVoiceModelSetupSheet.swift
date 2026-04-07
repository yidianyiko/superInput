import SpeechBarApplication
import SpeechBarInfrastructure
import SwiftUI

struct SenseVoiceModelSetupSheet: View {
    @ObservedObject var coordinator: VoiceSessionCoordinator
    @ObservedObject var modelSettingsStore: OpenAIModelSettingsStore
    @ObservedObject var senseVoiceModelStore: SenseVoiceModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("安装默认 SenseVoice 本地模型")
                    .font(.system(size: 24, weight: .semibold))
                Text("会自动准备 `sherpa-onnx` 运行时，并下载默认 `SenseVoice Small (Int8)`。安装完成后自动切到本地 SenseVoice，可以直接开始录音。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(senseVoiceModelStore.defaultModel.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text(senseVoiceModelStore.defaultModel.sizeLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(senseVoiceModelStore.defaultModel.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(senseVoiceModelStore.defaultModel.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if senseVoiceModelStore.isDownloading {
                            ProgressView(value: senseVoiceModelStore.downloadProgress)
                            Text("安装中 \(Int(senseVoiceModelStore.downloadProgress * 100))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(senseVoiceModelStore.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if let lastErrorMessage = senseVoiceModelStore.lastErrorMessage,
                           !lastErrorMessage.isEmpty {
                            Text(lastErrorMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(18)
                }
                .frame(minHeight: 170)

            HStack {
                Button("稍后再说") {
                    senseVoiceModelStore.dismissInstallPrompt()
                }
                .disabled(senseVoiceModelStore.isDownloading)

                Spacer()

                Button(action: handlePrimaryAction) {
                    Text(primaryButtonTitle)
                        .frame(minWidth: 160)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(senseVoiceModelStore.isDownloading)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private var primaryButtonTitle: String {
        if senseVoiceModelStore.isDownloading {
            return "安装中..."
        }

        if senseVoiceModelStore.isDefaultInstallationReady {
            return "立即启用"
        }

        return "安装并启用"
    }

    private func handlePrimaryAction() {
        if senseVoiceModelStore.isDefaultInstallationReady {
            activateLocalModel()
            return
        }

        Task {
            let didInstall = await senseVoiceModelStore.installDefaultModel()
            guard didInstall else { return }
            await MainActor.run {
                activateLocalModel()
            }
        }
    }

    private func activateLocalModel() {
        modelSettingsStore.activateDefaultSenseVoiceModel()
        coordinator.refreshCredentialStatus()
        senseVoiceModelStore.dismissInstallPrompt()
    }
}
