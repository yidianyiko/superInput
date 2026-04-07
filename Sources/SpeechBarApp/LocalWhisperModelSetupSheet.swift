import SpeechBarApplication
import SpeechBarInfrastructure
import SwiftUI

struct LocalWhisperModelSetupSheet: View {
    @ObservedObject var coordinator: VoiceSessionCoordinator
    @ObservedObject var modelSettingsStore: OpenAIModelSettingsStore
    @ObservedObject var localWhisperModelStore: LocalWhisperModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("安装默认本地语音模型")
                    .font(.system(size: 24, weight: .semibold))
                Text("会下载 VoiceInk 同款默认选择 `ggml-large-v3-turbo-q5_0`。安装完成后自动切到本地 Whisper，可以直接开始录音。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .overlay {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(localWhisperModelStore.defaultModel.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text(localWhisperModelStore.defaultModel.sizeLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(localWhisperModelStore.defaultModel.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(localWhisperModelStore.defaultModel.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if localWhisperModelStore.isDownloading {
                            ProgressView(value: localWhisperModelStore.downloadProgress)
                            Text("下载中 \(Int(localWhisperModelStore.downloadProgress * 100))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(localWhisperModelStore.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if let lastErrorMessage = localWhisperModelStore.lastErrorMessage,
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
                    localWhisperModelStore.dismissInstallPrompt()
                }
                .disabled(localWhisperModelStore.isDownloading)

                Spacer()

                Button(action: handlePrimaryAction) {
                    Text(primaryButtonTitle)
                        .frame(minWidth: 160)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(localWhisperModelStore.isDownloading)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private var primaryButtonTitle: String {
        if localWhisperModelStore.isDownloading {
            return "下载中..."
        }

        if localWhisperModelStore.isDefaultModelInstalled {
            return "立即启用"
        }

        return "下载并启用"
    }

    private func handlePrimaryAction() {
        if localWhisperModelStore.isDefaultModelInstalled {
            activateLocalModel()
            return
        }

        Task {
            let didInstall = await localWhisperModelStore.installDefaultModel()
            guard didInstall else { return }
            await MainActor.run {
                activateLocalModel()
            }
        }
    }

    private func activateLocalModel() {
        modelSettingsStore.activateDefaultLocalWhisperModel()
        coordinator.refreshCredentialStatus()
        localWhisperModelStore.dismissInstallPrompt()
    }
}
