import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var coordinator: VoiceSessionCoordinator
    @ObservedObject var agentMonitorCoordinator: AgentMonitorCoordinator
    @ObservedObject var embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    @ObservedObject var diagnosticsCoordinator: DiagnosticsCoordinator
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var audioInputSettingsStore: AudioInputSettingsStore
    @ObservedObject var modelSettingsStore: OpenAIModelSettingsStore
    @ObservedObject var localWhisperModelStore: LocalWhisperModelStore
    @ObservedObject var senseVoiceModelStore: SenseVoiceModelStore
    let pushToTalkSource: OnScreenPushToTalkSource
    let openHomeAction: (() -> Void)?

    static let defaultThemeRawValue = HomeWindowStore.ThemePreset.green.rawValue
    static let triggerCardHeight: CGFloat = 72
    static let triggerCardHorizontalPadding: CGFloat = 14
    static let triggerCardVerticalPadding: CGFloat = 8
    static let triggerCardContentSpacing: CGFloat = 6
    static let triggerCardTextSpacing: CGFloat = 2
    static let triggerChipVerticalPadding: CGFloat = 4

    @AppStorage("home.selectedTheme") private var selectedThemeRaw = Self.defaultThemeRawValue
    @State private var apiKeyInput = ""

    private var selectedTheme: HomeWindowStore.ThemePreset {
        Self.resolvedThemePreset(from: selectedThemeRaw)
    }

    private var palette: HomeWindowStore.HomeThemePalette {
        selectedTheme.palette
    }

    var body: some View {
        ZStack {
            SlashVibeCanvas(palette: palette)

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard

                    triggerCard

                    HStack(spacing: 12) {
                        CompactStatusCard(
                            palette: palette,
                            title: "状态",
                            value: sessionTitle,
                            tint: sessionTint
                        )
                        CompactStatusCard(
                            palette: palette,
                            title: "输出",
                            value: "当前输入框",
                            tint: palette.highlight
                        )
                    }

                    monitorSummaryCard
                    transcriptPreviewCard
                    polishCard

                    HStack(alignment: .top, spacing: 12) {
                        permissionCard
                        apiKeyCard
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .preferredColorScheme(palette.preferredColorScheme)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.accent, palette.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "mic.and.signal.meter.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("SlashVibe")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Text("Voice input")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    Text("右侧 Command 单击开始，再次单击结束。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textMuted)
                }

                Spacer(minLength: 12)

                if let openHomeAction {
                    Button("打开主页", action: openHomeAction)
                        .buttonStyle(StatusSecondaryButtonStyle(palette: palette))
                }
            }

            HStack(spacing: 8) {
                SmallTag(palette: palette, title: "模型", value: modelSettingsStore.selectedSpeechProviderName, tint: palette.accent, filled: true)
                SmallTag(palette: palette, title: "语言", value: modelSettingsStore.currentSpeechLanguage, tint: palette.highlight, filled: true)
                SmallTag(palette: palette, title: "转写", value: modelSettingsStore.currentSpeechModel, tint: palette.accentSecondary, filled: true)
            }
        }
        .padding(16)
        .slashVibeHeroSurface(palette: palette, cornerRadius: 24)
    }

    private var triggerCard: some View {
        Button(action: toggleRecording) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isRecordingFlowActive
                        ? LinearGradient(
                            colors: [Color(red: 0.83, green: 0.22, blue: 0.22), Color(red: 0.95, green: 0.41, blue: 0.34)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [palette.accent, palette.accentSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
                .overlay {
                    VStack(spacing: Self.triggerCardContentSpacing) {
                        HStack {
                            Text(isRecordingFlowActive ? "Live" : "Ready")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, Self.triggerChipVerticalPadding)
                                .background(palette.controlFill, in: Capsule())
                                .foregroundStyle(palette.controlText)
                            Spacer()
                            Image(systemName: isRecordingFlowActive ? "waveform.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                        }

                        VStack(spacing: Self.triggerCardTextSpacing) {
                            Text(recordButtonTitle)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(recordButtonSubtitle)
                                .font(.system(size: 11, weight: .medium))
                                .multilineTextAlignment(.center)
                                .opacity(0.92)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Self.triggerCardHorizontalPadding)
                    .padding(.vertical, Self.triggerCardVerticalPadding)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.controlStroke, lineWidth: 1)
                )
                .frame(height: Self.triggerCardHeight)
                .opacity(isActionDisabled ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isActionDisabled)
    }

    private var monitorSummaryCard: some View {
        PanelCard(palette: palette, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("监控摘要")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(transportStatusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(embeddedDisplayCoordinator.connectionState.phase == .ready ? palette.accent : palette.textSecondary)
                }

                HStack(spacing: 10) {
                    SmallTag(palette: palette, title: "任务", value: "\(agentMonitorCoordinator.taskBoardSnapshot.cards.count)", tint: palette.accent)
                    SmallTag(palette: palette, title: "审批", value: "\(agentMonitorCoordinator.taskBoardSnapshot.cards.filter { $0.boardState == .approve }.count)", tint: palette.highlight)
                    SmallTag(palette: palette, title: "异常", value: "\(agentMonitorCoordinator.taskBoardSnapshot.cards.filter { $0.boardState == .error }.count)", tint: palette.accentSecondary)
                }

                HStack {
                    Text("最近发送")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(embeddedDisplayCoordinator.lastSentAt.map(shortTimestamp) ?? "暂无")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }

                if let openHomeAction {
                    Button("打开主页查看详情", action: openHomeAction)
                        .buttonStyle(StatusSecondaryButtonStyle(palette: palette))
                }
            }
        }
    }

    private var transcriptPreviewCard: some View {
        PanelCard(palette: palette, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("文本预览")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(coordinator.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                PreviewBubble(
                    palette: palette,
                    title: "临时",
                    text: coordinator.interimTranscript,
                    placeholder: "录音时显示临时识别内容。"
                )

                PreviewBubble(
                    palette: palette,
                    title: "最终",
                    text: coordinator.finalTranscript,
                    placeholder: "结束录音后显示最终文本。"
                )

                if !coordinator.activeInputHints.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本次记忆提示")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(coordinator.activeInputHints, id: \.self) { hint in
                                    SmallTag(palette: palette, title: "记忆", value: hint, tint: palette.highlight)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var permissionCard: some View {
        PanelCard(palette: palette, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("权限")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                StatusRow(
                    palette: palette,
                    label: "辅助功能",
                    value: AccessibilityPermissionManager.isTrusted() ? "已授权" : "待授权",
                    tint: AccessibilityPermissionManager.isTrusted() ? .green : .orange
                )
                StatusRow(
                    palette: palette,
                    label: "麦克风",
                    value: audioInputSettingsStore.selectionSummary,
                    tint: palette.highlight
                )

                Button("打开系统设置") {
                    Task { @MainActor in
                        AccessibilityPermissionManager.openSystemSettings()
                    }
                }
                .buttonStyle(StatusSecondaryButtonStyle(palette: palette))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var apiKeyCard: some View {
        PanelCard(palette: palette, padding: 16) {
            if isSelectedLocalProvider {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("本地模型")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(coordinator.credentialStatus == .available ? "已安装" : "未安装")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(coordinator.credentialStatus == .available ? .green : .orange)
                    }

                    Text(
                        coordinator.credentialStatus == .available
                            ? "当前默认模型：\(selectedLocalModelName)"
                            : selectedLocalInstallHint
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)

                    if selectedLocalProviderIsDownloading {
                        ProgressView(value: selectedLocalDownloadProgress)
                        Text("\(Int(selectedLocalDownloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }

                    if let openHomeAction {
                        Button(
                            coordinator.credentialStatus == .available ? "打开主页管理模型" : "打开主页安装模型",
                            action: openHomeAction
                        )
                        .buttonStyle(StatusPrimaryButtonStyle(palette: palette))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(modelSettingsStore.currentSpeechCredentialLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(coordinator.credentialStatus == .available ? "已保存" : "缺失")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(coordinator.credentialStatus == .available ? .green : .orange)
                    }

                    SecureField(
                        coordinator.credentialStatus == .available ? "替换 API Key" : "输入当前转写服务 API Key",
                        text: $apiKeyInput
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button(coordinator.credentialStatus == .available ? "更新" : "保存") {
                            coordinator.saveAPIKey(apiKeyInput)
                            apiKeyInput = ""
                        }
                        .buttonStyle(StatusPrimaryButtonStyle(palette: palette))

                        if coordinator.credentialStatus == .available {
                            Button("移除") {
                                coordinator.clearAPIKey()
                            }
                            .buttonStyle(StatusSecondaryButtonStyle(palette: palette))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var polishEnabledBinding: Binding<Bool> {
        Binding(
            get: { userProfileStore.isPolishEnabled },
            set: { userProfileStore.setPolishEnabled($0) }
        )
    }

    private var polishCard: some View {
        PanelCard(palette: palette, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("AI 后处理")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(polishSummary)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(userProfileStore.isPolishEnabled ? palette.accent : palette.textSecondary)
                }

                Toggle("录音结束后润色文本", isOn: polishEnabledBinding)
                    .toggleStyle(.switch)

                if userProfileStore.isPolishEnabled {
                    Picker("润色模式", selection: $userProfileStore.polishMode) {
                        Text("轻润色").tag(TranscriptPolishMode.light)
                        Text("聊天表达").tag(TranscriptPolishMode.chat)
                        Text("回复模式").tag(TranscriptPolishMode.reply)
                    }
                    .pickerStyle(.segmented)

                    Text(
                        polishDescription
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                } else {
                    Text("关闭后会直接使用原始转写，速度最快。")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                }

                HStack(spacing: 8) {
                    Button("载入 Demo Seed Pack") {
                        userProfileStore.applyReplyDemoSeedPack()
                    }
                    .buttonStyle(StatusPrimaryButtonStyle(palette: palette))

                    if let openHomeAction {
                        Button("打开主页调整策略", action: openHomeAction)
                            .buttonStyle(StatusSecondaryButtonStyle(palette: palette))
                    }
                }

                Text(userProfileStore.terminologyStatusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textMuted)
            }
        }
    }

    private var isRecordingFlowActive: Bool {
        switch coordinator.sessionState {
        case .requestingPermission, .connecting, .recording:
            return true
        case .idle, .finalizing, .failed:
            return false
        }
    }

    private var isBusyWithoutStopAction: Bool {
        if case .finalizing = coordinator.sessionState {
            return true
        }
        return false
    }

    private var isActionDisabled: Bool {
        coordinator.credentialStatus == .missing || isBusyWithoutStopAction
    }

    private var recordButtonTitle: String {
        if isRecordingFlowActive {
            return "结束本次录音"
        }
        if case .finalizing = coordinator.sessionState {
            return "正在整理文本"
        }
        return "开始一次语音输入"
    }

    private var recordButtonSubtitle: String {
        if coordinator.credentialStatus == .missing {
            if modelSettingsStore.selectedSpeechProvider == .localWhisper {
                return "先安装默认本地 Whisper 模型，再开始录音。"
            }
            if modelSettingsStore.selectedSpeechProvider == .localSenseVoice {
                return "先安装 SenseVoice 运行时和默认模型，再开始录音。"
            }
            return "先保存当前转写服务的 API Key，再开始录音。"
        }
        if isRecordingFlowActive {
            return "正在听你说话，再点一次按钮或按右侧 Command 结束。"
        }
        if case .finalizing = coordinator.sessionState {
            return "正在把最终文本写入当前窗口。"
        }
        return "也可以直接点击这里开始，适合快速试录。"
    }

    private func toggleRecording() {
        guard coordinator.credentialStatus == .available else { return }

        if isRecordingFlowActive {
            pushToTalkSource.sendReleased()
        } else if !isBusyWithoutStopAction {
            pushToTalkSource.sendPressed()
        }
    }

    private var sessionTitle: String {
        switch coordinator.sessionState {
        case .idle:
            return "空闲"
        case .requestingPermission:
            return "请求麦克风"
        case .connecting:
            return "连接云端"
        case .recording:
            return "录音中"
        case .finalizing:
            return "整理文本"
        case .failed:
            return "异常"
        }
    }

    private var sessionTint: Color {
        switch coordinator.sessionState {
        case .idle:
            return Color(red: 0.58, green: 0.61, blue: 0.67)
        case .requestingPermission, .connecting:
            return palette.highlight
        case .recording:
            return Color(red: 0.84, green: 0.23, blue: 0.23)
        case .finalizing:
            return Color(red: 0.18, green: 0.44, blue: 0.82)
        case .failed:
            return Color(red: 0.79, green: 0.22, blue: 0.22)
        }
    }

    private var polishSummary: String {
        guard userProfileStore.isPolishEnabled else { return "已关闭" }

        switch userProfileStore.polishMode {
        case .off:
            return "已关闭"
        case .light:
            return "轻润色"
        case .chat:
            return "聊天表达"
        case .reply:
            return "回复模式"
        }
    }

    private var polishDescription: String {
        switch userProfileStore.polishMode {
        case .off:
            return "关闭后会直接使用原始转写，速度最快。"
        case .light:
            return userProfileStore.skipShortPolish
                ? "短句会直接跳过润色，当前阈值：\(userProfileStore.shortPolishCharacterThreshold) 个有效字符。"
                : "所有句子都会尝试轻润色。"
        case .chat:
            return "会把口语整理成更顺口的聊天表达，但仍尽量保留原意。"
        case .reply:
            return "会把你的口语意图整理成可直接发送的回复，并带入当前 persona 和记忆提示。"
        }
    }

    private var isSelectedLocalProvider: Bool {
        modelSettingsStore.selectedSpeechProvider == .localWhisper ||
            modelSettingsStore.selectedSpeechProvider == .localSenseVoice
    }

    private var selectedLocalModelName: String {
        switch modelSettingsStore.selectedSpeechProvider {
        case .localWhisper:
            return modelSettingsStore.configuration.localWhisperModel
        case .localSenseVoice:
            return modelSettingsStore.configuration.localSenseVoiceModel
        case .deepgram, .whisper:
            return modelSettingsStore.currentSpeechModel
        }
    }

    private var selectedLocalInstallHint: String {
        switch modelSettingsStore.selectedSpeechProvider {
        case .localWhisper:
            return "先下载默认本地 Whisper 模型，安装完成后即可直接录音。"
        case .localSenseVoice:
            return "先安装 SenseVoice 运行时和默认模型，安装完成后即可直接录音。"
        case .deepgram, .whisper:
            return ""
        }
    }

    private var selectedLocalProviderIsDownloading: Bool {
        switch modelSettingsStore.selectedSpeechProvider {
        case .localWhisper:
            return localWhisperModelStore.isDownloading
        case .localSenseVoice:
            return senseVoiceModelStore.isDownloading
        case .deepgram, .whisper:
            return false
        }
    }

    private var selectedLocalDownloadProgress: Double {
        switch modelSettingsStore.selectedSpeechProvider {
        case .localWhisper:
            return localWhisperModelStore.downloadProgress
        case .localSenseVoice:
            return senseVoiceModelStore.downloadProgress
        case .deepgram, .whisper:
            return 0
        }
    }

    private var transportStatusTitle: String {
        switch embeddedDisplayCoordinator.connectionState.phase {
        case .disconnected:
            return "未连接"
        case .discovering:
            return "发现中"
        case .connecting:
            return "连接中"
        case .ready:
            return "已就绪"
        case .degraded:
            return "降级"
        case .failed:
            return "失败"
        }
    }

    private func shortTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct PanelCard<Content: View>: View {
    let palette: HomeWindowStore.HomeThemePalette
    let padding: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .slashVibeSurface(palette: palette, cornerRadius: 20)
    }
}

private struct CompactStatusCard: View {
    let palette: HomeWindowStore.HomeThemePalette
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.elevatedFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.controlStroke, lineWidth: 1)
        )
    }
}

private struct SmallTag: View {
    let palette: HomeWindowStore.HomeThemePalette
    let title: String
    let value: String
    let tint: Color
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(filled ? palette.controlText.opacity(0.78) : palette.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? palette.controlText : tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            filled ? palette.controlFill : palette.elevatedFill,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(filled ? palette.controlStroke : palette.border, lineWidth: 1)
        )
    }
}

private struct PreviewBubble: View {
    let palette: HomeWindowStore.HomeThemePalette
    let title: String
    let text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.elevatedFill)
                .overlay(alignment: .topLeading) {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(text.isEmpty ? palette.textSecondary : palette.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.controlStroke, lineWidth: 1)
                )
                .frame(height: 60)
        }
    }
}

private struct StatusRow: View {
    let palette: HomeWindowStore.HomeThemePalette
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12), in: Capsule())
                .foregroundStyle(palette.controlText)
        }
    }
}

private struct StatusPrimaryButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                palette.accent,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

private struct StatusSecondaryButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(palette.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.controlStroke, lineWidth: 1)
            )
            .foregroundStyle(palette.controlText)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

extension StatusPanelView {
    static func resolvedThemePreset(from rawValue: String?) -> HomeWindowStore.ThemePreset {
        guard let rawValue, let theme = HomeWindowStore.ThemePreset(rawValue: rawValue) else {
            return .green
        }
        return theme
    }
}
