import AppKit
import Foundation
import SpeechBarApplication
import SpeechBarDomain
import SpeechBarInfrastructure
import SwiftUI

struct HomeWindowView: View {
    @ObservedObject var coordinator: VoiceSessionCoordinator
    @ObservedObject var agentMonitorCoordinator: AgentMonitorCoordinator
    @ObservedObject var embeddedDisplayCoordinator: EmbeddedDisplayCoordinator
    @ObservedObject var diagnosticsCoordinator: DiagnosticsCoordinator
    @ObservedObject var store: HomeWindowStore
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var audioInputSettingsStore: AudioInputSettingsStore
    @ObservedObject var modelSettingsStore: OpenAIModelSettingsStore
    @ObservedObject var polishPlaygroundStore: PolishPlaygroundStore
    @ObservedObject var localWhisperModelStore: LocalWhisperModelStore
    @ObservedObject var senseVoiceModelStore: SenseVoiceModelStore
    @ObservedObject var memoryConstellationStore: MemoryConstellationStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore
    let pushToTalkSource: OnScreenPushToTalkSource

    private let contentMaxWidth: CGFloat = 1_080
    private let polishCharacterThresholdOptions = [4, 8, 12, 20]
    private let polishTimeoutOptions: [Double] = [1.0, 1.5, 1.8, 2.5, 3.0]
    @State private var modelActionMessage = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            Divider()

            GeometryReader { proxy in
                let availableContentWidth = max(680, proxy.size.width - 40)

                ZStack {
                    SlashVibeCanvas(palette: store.palette)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            contentView
                        }
                        .frame(
                            maxWidth: min(contentMaxWidth, availableContentWidth),
                            alignment: .leading
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
            }
        }
        .background(store.palette.canvasTop)
        .environment(\.colorScheme, .light)
        .sheet(
            isPresented: Binding(
                get: { localWhisperModelStore.shouldShowInstallPrompt },
                set: { isPresented in
                    if !isPresented {
                        localWhisperModelStore.dismissInstallPrompt()
                    }
                }
            )
        ) {
            LocalWhisperModelSetupSheet(
                coordinator: coordinator,
                modelSettingsStore: modelSettingsStore,
                localWhisperModelStore: localWhisperModelStore
            )
        }
        .sheet(
            isPresented: Binding(
                get: { senseVoiceModelStore.shouldShowInstallPrompt },
                set: { isPresented in
                    if !isPresented {
                        senseVoiceModelStore.dismissInstallPrompt()
                    }
                }
            )
        ) {
            SenseVoiceModelSetupSheet(
                coordinator: coordinator,
                modelSettingsStore: modelSettingsStore,
                senseVoiceModelStore: senseVoiceModelStore
            )
        }
    }

    private var polishEnabledBinding: Binding<Bool> {
        Binding(
            get: { userProfileStore.isPolishEnabled },
            set: { userProfileStore.setPolishEnabled($0) }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    store.palette.accent,
                                    store.palette.accentSecondary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
                                    .padding(4)

                                Image(systemName: "mic.and.signal.meter.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 54, height: 54)
                        .shadow(color: store.palette.accent.opacity(0.18), radius: 16, x: 0, y: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SlashVibe")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Voice input")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("自然说话，快速成文。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(HomeWindowStore.Section.allCases) { section in
                    SidebarTabButton(
                        title: section.rawValue,
                        subtitle: section.subtitle,
                        systemImage: section.icon,
                        isSelected: store.selectedSection == section,
                        palette: store.palette
                    ) {
                        store.saveSelectedSection(section)
                    }
                }
            }

            subscriptionSidebarCard

            HStack {
                Text(store.currentVersionText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(coordinator.credentialStatus == .available ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(store.palette.sidebarTop)
    }

    @ViewBuilder
    private var contentView: some View {
        switch store.selectedSection {
        case .home:
            homePage
        case .memory:
            MemoryConstellationScreen(
                constellationStore: memoryConstellationStore,
                userProfileStore: userProfileStore,
                memoryFeatureFlagStore: memoryFeatureFlagStore
            )
        case .model:
            modelPage
        case .monitor:
            monitorPage
        case .debug:
            debugPage
        case .settings:
            settingsPage
        }
    }

    private var subscriptionSidebarCard: some View {
        GlassCard(palette: store.palette, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("订阅中心")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Web")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text("购买或管理 SlashVibe Pro。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("升级 Pro") {
                        openExternalURL(store.subscriptionPurchaseURL)
                    }
                    .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))
                    .frame(maxWidth: .infinity)

                    Button("管理订阅") {
                        openExternalURL(store.subscriptionManageURL)
                    }
                    .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var homePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(
                eyebrow: "首页",
                title: "SlashVibe 控制台",
                subtitle: "集中管理录音、转写、历史与订阅。"
            )

            dashboardHero
            subscriptionBanner

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                MetricCard(
                    title: "累计录音次数",
                    value: "\(store.totalSessionCount)",
                    detail: "总共完成的转写会话",
                    symbol: "waveform.path.ecg.rectangle.fill",
                    tint: store.palette.accent
                )
                MetricCard(
                    title: "今日次数",
                    value: "\(store.todaySessionCount)",
                    detail: "今天已经触发的转写",
                    symbol: "calendar.badge.clock",
                    tint: store.palette.highlight
                )
                MetricCard(
                    title: "口述字数",
                    value: "\(store.totalCharacterCount)",
                    detail: "已转写出的文本字符",
                    symbol: "textformat.characters",
                    tint: store.palette.accentSecondary
                )
                MetricCard(
                    title: "总口述时间",
                    value: "\(store.totalDictationMinutes) min",
                    detail: "累计口述时长",
                    symbol: "timer",
                    tint: store.palette.accent
                )
                MetricCard(
                    title: "节省时间",
                    value: "\(store.estimatedSavedMinutes) min",
                    detail: "按 30 字/分钟手动输入估算",
                    symbol: "hourglass",
                    tint: store.palette.highlight
                )
                MetricCard(
                    title: "平均口述速度",
                    value: "\(store.averageDictationCharactersPerMinute) 字/分钟",
                    detail: "按历史会话实时计算",
                    symbol: "bolt",
                    tint: store.palette.accentSecondary
                )
            }

            HStack(alignment: .top, spacing: 18) {
                livePanel
                usagePanel
            }

            historyPanel
        }
    }

    private var dashboardHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SlashVibe")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.48))
                        .textCase(.uppercase)
                        .tracking(1.6)

                    Text("让语音输入像系统功能一样自然")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("按右侧 Command 开始或结束录音。转写、润色与写入整合为一个更安静的工作流。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 14) {
                    SessionBadge(
                        title: store.currentStatusTitle,
                        tint: sessionTint
                    )

                    ShortcutKeyCaps(symbols: ["⌘", "Press", "Talk"])
                }
            }

            HStack(spacing: 10) {
                Button(action: toggleRecording) {
                    Label(
                        store.isRecordingFlowActive ? "结束录音" : "开始录音",
                        systemImage: store.isRecordingFlowActive ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: store.isRecordingFlowActive))
                .disabled(coordinator.credentialStatus == .missing || isBusyWithoutStopAction)

                Button("打开辅助功能设置") {
                    AccessibilityPermissionManager.openSystemSettings()
                }
                .buttonStyle(SlashVibeHeroSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                InlineTag(title: "写入方式", value: "当前聚焦输入框", symbol: "text.cursor", palette: store.palette, inHero: true)
                InlineTag(title: "转写服务", value: modelSettingsStore.selectedSpeechProviderName, symbol: "bolt.horizontal.circle", palette: store.palette, inHero: true)
                InlineTag(title: "模型语言", value: "\(modelSettingsStore.currentSpeechModel) / \(modelSettingsStore.currentSpeechLanguage)", symbol: "globe", palette: store.palette, inHero: true)
            }
        }
        .padding(20)
        .slashVibeHeroSurface(palette: store.palette)
    }

    private var subscriptionBanner: some View {
        GlassCard(palette: store.palette, padding: 18) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SlashVibe Pro")
                        .font(.system(size: 16, weight: .semibold))
                    Text("解锁更高配额与团队协作能力。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("升级 Pro") {
                        openExternalURL(store.subscriptionPurchaseURL)
                    }
                    .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))

                    Button("管理订阅") {
                        openExternalURL(store.subscriptionManageURL)
                    }
                    .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                }
            }
        }
    }

    private var livePanel: some View {
        GlassCard(palette: store.palette, padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "实时状态",
                    subtitle: "展示当前会话的临时文本、原始结果和最终输出。"
                )

                StatusLine(label: "状态", value: store.currentStatusTitle)
                StatusLine(
                    label: "密钥状态",
                    value: coordinator.credentialStatus == .available ? "可用" : "缺失"
                )
                StatusLine(
                    label: "权限",
                    value: AccessibilityPermissionManager.isTrusted() ? "辅助功能已授权" : "需要授权"
                )

                transcriptBubble(
                    title: "临时文本",
                    text: coordinator.interimTranscript,
                    placeholder: "录音过程中会显示临时识别内容。"
                )

                transcriptBubble(
                    title: "原始转写",
                    text: coordinator.rawFinalTranscript,
                    placeholder: "转写服务返回的原始结果会显示在这里。"
                )

                transcriptBubble(
                    title: "最终输出",
                    text: coordinator.finalTranscript,
                    placeholder: "轻润色或硬回退后的最终结果会显示在这里。"
                )

                if let fallbackReason = coordinator.lastPolishFallbackReason,
                   !fallbackReason.isEmpty {
                    Text("轻润色已回退：\(fallbackReason)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var usagePanel: some View {
        GlassCard(palette: store.palette, padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "近 7 天活跃度",
                    subtitle: "轻量回顾最近一周使用情况。"
                )

                HStack(alignment: .bottom, spacing: 12) {
                    let points = store.weeklyUsage
                    let maxCount = max(points.map(\.count).max() ?? 0, 1)

                    ForEach(points) { point in
                        VStack(spacing: 8) {
                            Spacer(minLength: 0)

                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: point.isToday
                                            ? [store.palette.accent, store.palette.accentSecondary]
                                            : [store.palette.highlight.opacity(0.7), store.palette.highlight.opacity(0.35)],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: CGFloat(max(20, Int((Double(point.count) / Double(maxCount)) * 128.0))))

                            Text("\(point.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text(point.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(point.isToday ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 190, alignment: .bottom)

                Divider()

                HStack(spacing: 14) {
                    CompactSummary(
                        title: "平均字数",
                        value: "\(store.averageCharacterCount)",
                        palette: store.palette
                    )
                    CompactSummary(
                        title: "最近输出",
                        value: store.history.first?.deliveryLabel ?? "暂无",
                        palette: store.palette
                    )
                }
            }
        }
        .frame(width: 330, alignment: .topLeading)
    }

    private var historyPanel: some View {
        GlassCard(palette: store.palette, padding: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    sectionHeader(
                        title: "历史记录",
                        subtitle: "本地保存转写记录，便于回看和统计。"
                    )

                    Spacer()

                    if !store.history.isEmpty {
                        Button("清空记录") {
                            store.clearHistory()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                    }
                }

                if store.history.isEmpty {
                    EmptyStateCard(
                        title: "还没有历史记录",
                        detail: "完成一次录音转写后，这里会自动新增一条记录，用于统计和回看。"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(store.history.prefix(12))) { item in
                            HistoryRow(item: item, palette: store.palette, store: store)
                        }
                    }
                }
            }
        }
    }

    private var memoryPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(
                eyebrow: "记忆",
                title: "用户背景与表达偏好",
                subtitle: "职业、术语与表达偏好会共同影响识别和润色。"
                
            )

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "职业与术语研究",
                        subtitle: "保存职业后自动生成领域术语用于识别增强。"
                    )

                    HStack(alignment: .top, spacing: 12) {
                        TextField("例如：AI 创业者、跨境电商运营、VC 投资人、独立开发者", text: $userProfileStore.profession)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task {
                                    await userProfileStore.saveProfessionAndGenerateTerminology()
                                }
                            }

                        Button(userProfileStore.isGeneratingTerminology ? "生成中..." : "保存并生成术语") {
                            Task {
                                await userProfileStore.saveProfessionAndGenerateTerminology()
                            }
                        }
                        .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))
                        .disabled(userProfileStore.isGeneratingTerminology)

                        Button("重新生成") {
                            Task {
                                await userProfileStore.refreshTerminology()
                            }
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                        .disabled(userProfileStore.isGeneratingTerminology)
                    }

                    HStack(spacing: 12) {
                        Text(userProfileStore.terminologyStatusMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        if let lastGeneratedAt = userProfileStore.lastGeneratedAt {
                            Text("最近更新：\(store.formattedDate(lastGeneratedAt))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "背景与表达偏好",
                        subtitle: "描述常见场景、语气偏好和高频术语。"
                    )

                    PlaceholderTextEditor(
                        text: $userProfileStore.memoryProfile,
                        placeholder: "例如：我是 AI 创业者，常用中文交流但会夹杂英文产品术语。我偏好结论先行、结构清晰、适合直接发送给同事或 AI 助手的表达。"
                    )
                    .frame(minHeight: 300)

                    HStack(spacing: 10) {
                        SuggestionChip(title: "职业背景") {
                            userProfileStore.addMemoryTemplate("我是创业者，平时会围绕 AI 产品、增长、融资和团队协作做高频沟通。")
                        }
                        SuggestionChip(title: "表达风格") {
                            userProfileStore.addMemoryTemplate("我希望输出更自然、有段落感，尽量避免机械口语和重复表达。")
                        }
                        SuggestionChip(title: "术语偏好") {
                            userProfileStore.addMemoryTemplate("请保留常见英文产品词汇、技术术语和模型名称，不要强行翻译。")
                        }
                    }

                    Toggle(isOn: polishEnabledBinding) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI 后处理润色")
                                .font(.system(size: 14, weight: .semibold))
                            Text("录音结束后，使用 OpenAI 对原始转写做纠错和表达整理。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if userProfileStore.isPolishEnabled {
                        Picker("润色模式", selection: $userProfileStore.polishMode) {
                            Text("轻润色").tag(TranscriptPolishMode.light)
                            Text("聊天表达").tag(TranscriptPolishMode.chat)
                            Text("回复模式").tag(TranscriptPolishMode.reply)
                        }
                        .pickerStyle(.segmented)

                        Text(polishModeDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("跳过短句润色", isOn: $userProfileStore.skipShortPolish)
                                .toggleStyle(.switch)

                            if userProfileStore.skipShortPolish {
                                HStack {
                                    Text("短句阈值")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Picker("短句阈值", selection: $userProfileStore.shortPolishCharacterThreshold) {
                                        ForEach(polishCharacterThresholdOptions, id: \.self) { value in
                                            Text(polishThresholdLabel(value)).tag(value)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 180)
                                }
                            }

                            Toggle("使用前台应用上下文", isOn: $userProfileStore.useFrontmostAppContextForPolish)
                                .toggleStyle(.switch)

                            Toggle("使用剪贴板上下文", isOn: $userProfileStore.useClipboardContextForPolish)
                                .toggleStyle(.switch)

                            HStack {
                                Text("请求超时")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Picker("请求超时", selection: $userProfileStore.polishTimeoutSeconds) {
                                    ForEach(polishTimeoutOptions, id: \.self) { value in
                                        Text(polishTimeoutLabel(value)).tag(value)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }

                            Text("提速逻辑会优先跳过短句，并且只在你启用时才读取前台应用或剪贴板上下文。")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("关闭后将直接使用原始转写结果；重新开启时会恢复你上次使用的润色模式。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "输入记忆",
                        subtitle: "采集和召回默认开启，可随时按需关闭。"
                    )

                    Toggle("启用记忆采集", isOn: $memoryFeatureFlagStore.captureEnabled)
                        .toggleStyle(.switch)

                    Toggle("启用记忆召回", isOn: $memoryFeatureFlagStore.recallEnabled)
                        .toggleStyle(.switch)

                    Text("记忆仅保存在本机，敏感输入会被排除或脱敏处理。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        sectionHeader(
                            title: "术语词表",
                            subtitle: "开启后参与识别增强与 AI 润色，关闭后仅保存词表。"
                        )
                        Spacer()
                        Button("添加术语") {
                            userProfileStore.appendGlossaryTerm()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                    }

                    Toggle("术语词表增强", isOn: $userProfileStore.isTerminologyGlossaryEnabled)
                        .toggleStyle(.switch)

                    Text(
                        userProfileStore.isTerminologyGlossaryEnabled
                            ? "当前会把已启用术语用于识别增强和 AI 润色。术语越多，OpenAI 润色请求会稍慢一些。"
                            : "当前不会把术语词表带入转写或 AI 润色。这样通常能略微减少请求体积。"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                    if userProfileStore.terminologyGlossary.isEmpty {
                        EmptyStateCard(
                            title: "还没有术语词表",
                            detail: "先填写职业并生成术语，或手动添加词条。"
                        )
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(userProfileStore.terminologyGlossary) { entry in
                                    HStack(spacing: 12) {
                                        Toggle("", isOn: Binding(
                                            get: { entry.isEnabled },
                                            set: { _ in userProfileStore.toggleGlossaryTerm(id: entry.id) }
                                        ))
                                        .toggleStyle(.switch)
                                        .labelsHidden()

                                        TextField(
                                            "术语",
                                            text: Binding(
                                                get: { entry.term },
                                                set: { userProfileStore.updateGlossaryTerm(id: entry.id, term: $0) }
                                            )
                                        )
                                        .textFieldStyle(.roundedBorder)

                                        Button {
                                            userProfileStore.removeGlossaryTerm(id: entry.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 240, maxHeight: 360)
                    }
                }
            }
        }
    }

    private var monitorPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(
                eyebrow: "监控",
                title: "多 Agent 任务看板",
                subtitle: "查看任务卡、provider 摘要和设备链路状态。"
            )

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "链路摘要",
                        subtitle: "上位机生成快照，下位机仅接收并渲染。"
                    )

                    HStack(spacing: 12) {
                        MetricCard(
                            title: "活跃任务",
                            value: "\(agentMonitorCoordinator.taskBoardSnapshot.cards.count)",
                            detail: "当前可见卡片",
                            symbol: "rectangle.stack.person.crop.fill",
                            tint: store.palette.accent
                        )
                        MetricCard(
                            title: "隐藏任务",
                            value: "\(agentMonitorCoordinator.taskBoardSnapshot.hiddenCount)",
                            detail: "超出 5 张后的数量",
                            symbol: "ellipsis.rectangle",
                            tint: store.palette.highlight
                        )
                        MetricCard(
                            title: "传输状态",
                            value: transportStatusTitle,
                            detail: embeddedDisplayCoordinator.connectionState.reason ?? "链路正常",
                            symbol: "display.2",
                            tint: store.palette.accentSecondary
                        )
                    }

                    HStack(spacing: 12) {
                        Button("生成模拟任务") {
                            agentMonitorCoordinator.runDemoSequence()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))

                        Button("生成错误任务") {
                            agentMonitorCoordinator.runErrorDemoSequence()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))

                        Button("停止模拟") {
                            agentMonitorCoordinator.stopDemoSequence()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        sectionHeader(
                            title: "任务卡",
                            subtitle: "按 RUN / CHECK / INPUT / APPROVE / ERROR 排序。"
                        )
                        Spacer()
                        if !agentMonitorCoordinator.taskBoardSnapshot.cards.isEmpty {
                            Button("下一张") {
                                agentMonitorCoordinator.moveToNextCard()
                            }
                            .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                        }
                    }

                    if agentMonitorCoordinator.taskBoardSnapshot.cards.isEmpty {
                        EmptyStateCard(
                            title: "还没有采集到任务",
                            detail: "Codex 会优先从 JSONL 会话目录读取，Claude/Gemini/Cursor 会等待 hook inbox 事件落盘。"
                        )
                    } else {
                        VStack(spacing: 12) {
                        ForEach(agentMonitorCoordinator.taskBoardSnapshot.cards) { card in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center, spacing: 12) {
                                        Label(card.provider.shortLabel, systemImage: card.provider.symbolName)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(card.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(card.boardState.rawValue)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(cardStateColor(card.boardState))
                                        Text("\(card.elapsedSeconds)s")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(card.progressText.isEmpty ? "暂无进度文本" : card.progressText)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(card.isSelected ? store.palette.softFill.opacity(0.95) : Color.white.opacity(0.82))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(card.isSelected ? store.palette.accent.opacity(0.75) : store.palette.border.opacity(0.75), lineWidth: 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    agentMonitorCoordinator.selectCard(id: card.id, userInitiated: true)
                                }
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 18) {
                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(
                            title: "Provider 摘要",
                            subtitle: "额度信息作为补充展示，不占主卡空间。"
                        )

                        ForEach(agentMonitorCoordinator.taskBoardSnapshot.providerSummaries) { summary in
                            HStack {
                                Label(summary.provider.displayName, systemImage: summary.provider.symbolName)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("任务 \(summary.activeTaskCount)")
                                    .font(.system(size: 12, weight: .medium))
                                Text("输入 \(summary.waitingInputCount)")
                                    .font(.system(size: 12, weight: .medium))
                                Text("审批 \(summary.waitingApprovalCount)")
                                    .font(.system(size: 12, weight: .medium))
                                Text("异常 \(summary.errorCount)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(
                            title: "设备输出",
                            subtitle: "显示模式、最近发送与编码负载大小。"
                        )

                        StatusLine(label: "显示模式", value: embeddedDisplayCoordinator.lastSnapshot?.mode.rawValue ?? "blank")
                        StatusLine(label: "最近发送", value: embeddedDisplayCoordinator.lastSentAt.map(store.formattedDate) ?? "暂无")
                        StatusLine(label: "已确认序列", value: embeddedDisplayCoordinator.lastAckedSequence.map(String.init) ?? "暂无")
                        StatusLine(label: "编码字节数", value: "\(embeddedDisplayCoordinator.lastEncodedByteCount)")
                        StatusLine(label: "分片数", value: "\(embeddedDisplayCoordinator.lastFrameCount)")
                    }
                }
                .frame(width: 320, alignment: .topLeading)
            }
        }
    }

    private var debugPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(
                eyebrow: "调试",
                title: "诊断与回放",
                subtitle: "查看 collector 健康、诊断事件与回放包。"
            )

            HStack(alignment: .top, spacing: 18) {
                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(
                            title: "Collector 健康状态",
                            subtitle: "单个 provider 异常不应拖垮整体监控。"
                        )

                        ForEach(AgentProvider.allCases) { provider in
                            let health = agentMonitorCoordinator.collectorHealth[provider] ?? CollectorHealthSnapshot(provider: provider)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(provider.displayName, systemImage: provider.symbolName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Text(health.isRunning ? "运行中" : "未启动")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(health.isRunning ? .green : .secondary)
                                }
                                Text("tracked: \(health.trackedSourceCount)  dropped: \(health.droppedEventCount)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if let lastError = health.lastError, !lastError.isEmpty {
                                    Text(lastError)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(
                            title: "链路调试",
                            subtitle: "链路保持无关抽象，当前先用 loopback / file dump。"
                        )
                        StatusLine(label: "连接状态", value: transportStatusTitle)
                        StatusLine(label: "MTU", value: embeddedDisplayCoordinator.connectionState.deviceInfo.map { "\($0.maxPayloadBytes)" } ?? "未知")
                        StatusLine(label: "协议版本", value: embeddedDisplayCoordinator.connectionState.deviceInfo.map { "\($0.protocolVersion)" } ?? "未知")
                        StatusLine(label: "NACK", value: embeddedDisplayCoordinator.lastNackCode ?? "无")
                    }
                }
                .frame(width: 320, alignment: .topLeading)
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "最近诊断事件",
                        subtitle: "monitor、reducer、display、transport 诊断统一汇总。"
                    )

                    if diagnosticsCoordinator.recentDiagnostics.isEmpty {
                        EmptyStateCard(
                            title: "还没有诊断事件",
                            detail: "启动后 collector、快照构建和 transport 发送都会自动写入诊断日志。"
                        )
                    } else {
                        ForEach(diagnosticsCoordinator.recentDiagnostics.prefix(12)) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(event.subsystem)
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Text(event.severity == .info ? "INFO" : event.severity == .warning ? "WARN" : event.severity == .error ? "ERROR" : "CRITICAL")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(event.severity.rawValue >= DiagnosticSeverity.error.rawValue ? .red : .secondary)
                                }
                                Text(event.message)
                                    .font(.system(size: 12))
                                if !event.metadata.isEmpty {
                                    Text(event.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "  "))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Divider()
                        }
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "Replay Bundle",
                        subtitle: "collector 或 transport 错误时自动抓取回放现场。"
                    )

                    if diagnosticsCoordinator.recentBundles.isEmpty {
                        EmptyStateCard(
                            title: "还没有回放包",
                            detail: "当出现发送失败、严重诊断事件时，这里会记录 bundle 路径。"
                        )
                    } else {
                        ForEach(diagnosticsCoordinator.recentBundles.prefix(8)) { bundle in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(bundle.bundleID)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(bundle.rawEventsFile.path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(bundle.createdAt, style: .time)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "润色测试台",
                        subtitle: "直接调用当前 OpenAI 润色链路，不需要录音，也不会触发短句跳过逻辑。"
                    )

                    PlaceholderTextEditor(
                        text: $polishPlaygroundStore.inputText,
                        placeholder: "粘贴一段待润色的原始文本，例如一段口语化、重复较多的转写结果。"
                    )
                    .frame(minHeight: 180)

                    HStack(spacing: 10) {
                        Button(polishPlaygroundStore.isRunning ? "测试中..." : "直接测试润色") {
                            Task {
                                await polishPlaygroundStore.runCurrentInput()
                            }
                        }
                        .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))
                        .disabled(polishPlaygroundStore.isRunning)

                        Button("填入当前最终文本") {
                            let latestTranscript = coordinator.finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? coordinator.rawFinalTranscript
                                : coordinator.finalTranscript
                            polishPlaygroundStore.inputText = latestTranscript
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                        .disabled(
                            coordinator.finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                coordinator.rawFinalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    Text(polishPlaygroundStore.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    transcriptBubble(
                        title: "润色输出",
                        text: polishPlaygroundStore.outputText,
                        placeholder: "点击按钮后，这里会显示当前 persona、术语词表和润色模型共同作用下的输出。"
                    )
                }
            }
        }
    }

    private func polishThresholdLabel(_ value: Int) -> String {
        "\(value) 个有效字符以下跳过"
    }

    private func polishTimeoutLabel(_ value: Double) -> String {
        if value == floor(value) {
            return "\(Int(value)) 秒"
        }
        return String(format: "%.1f 秒", value)
    }

    private var polishModeDescription: String {
        switch userProfileStore.polishMode {
        case .off:
            return "关闭后将直接使用原始转写结果。"
        case .light:
            return "轻润色会尽量贴近原话，只修正明显识别错误、重复和标点。"
        case .chat:
            return "聊天表达会更顺口，适合直接发给同事或 AI，但仍会保留原意。"
        case .reply:
            return "回复模式会把口语意图整理成可直接发送的消息，更像你本人平时会发出去的话。"
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

    private func cardStateColor(_ state: BoardState) -> Color {
        switch state {
        case .run:
            return store.palette.highlight
        case .check:
            return .green
        case .input:
            return .orange
        case .approve:
            return store.palette.accent
        case .error:
            return .red
        }
    }

    private var modelPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(
                eyebrow: "模型",
                title: "接口与模型配置",
                subtitle: "可在 Deepgram、Whisper API、本地 Whisper 与本地 SenseVoice 间切换。"
            )

            HStack(alignment: .top, spacing: 18) {
                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(
                            title: "当前转写服务",
                            subtitle: modelSettingsStore.currentSpeechHint
                        )

                        Picker("服务商", selection: $modelSettingsStore.configuration.speechProvider) {
                            ForEach(SpeechTranscriptionProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: modelSettingsStore.configuration.speechProvider) { _ in
                            modelSettingsStore.refreshCredentialStatus()
                            coordinator.refreshCredentialStatus()
                        }

                        if modelSettingsStore.selectedSpeechProvider == .deepgram {
                            modelField(title: "模型", text: $modelSettingsStore.configuration.deepgramSpeechModel)
                            modelField(title: "语言", text: $modelSettingsStore.configuration.deepgramSpeechLanguage)
                            modelField(title: "接口地址", text: $modelSettingsStore.configuration.deepgramSpeechEndpoint)

                            SecureField("输入新的 Deepgram API Key", text: $modelSettingsStore.deepgramAPIKeyInput)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 10) {
                                Button("保存 Key") {
                                    do {
                                        try modelSettingsStore.saveDeepgramAPIKey()
                                        coordinator.refreshCredentialStatus()
                                        modelActionMessage = "Deepgram API Key 已保存。"
                                    } catch {
                                        modelActionMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))

                                Button("移除 Key") {
                                    do {
                                        try modelSettingsStore.removeDeepgramAPIKey()
                                        coordinator.refreshCredentialStatus()
                                        modelActionMessage = "Deepgram API Key 已移除。"
                                    } catch {
                                        modelActionMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                            }
                        } else if modelSettingsStore.selectedSpeechProvider == .whisper {
                            modelField(title: "模型", text: $modelSettingsStore.configuration.openAISpeechModel)
                            modelField(title: "语言", text: $modelSettingsStore.configuration.openAISpeechLanguage)
                            modelField(title: "共享 OpenAI 接口", text: $modelSettingsStore.configuration.researchEndpoint)
                            modelField(title: "Whisper 转写接口", text: $modelSettingsStore.configuration.openAISpeechEndpoint, editable: false)

                            SecureField("输入 OpenAI API Key", text: $modelSettingsStore.openAIAPIKeyInput)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 10) {
                                Button("保存 OpenAI Key") {
                                    do {
                                        try modelSettingsStore.saveOpenAIAPIKey()
                                        coordinator.refreshCredentialStatus()
                                        modelActionMessage = "OpenAI API Key 已保存。"
                                    } catch {
                                        modelActionMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))

                                Button("移除 OpenAI Key") {
                                    do {
                                        try modelSettingsStore.removeOpenAIAPIKey()
                                        coordinator.refreshCredentialStatus()
                                        modelActionMessage = "OpenAI API Key 已移除。"
                                    } catch {
                                        modelActionMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                            }
                        } else if modelSettingsStore.selectedSpeechProvider == .localWhisper {
                            modelField(title: "默认模型", text: $modelSettingsStore.configuration.localWhisperModel, editable: false)
                            modelField(title: "语言", text: $modelSettingsStore.configuration.localWhisperLanguage)
                            modelField(title: "模型目录", text: .constant(localWhisperModelStore.modelsDirectory.path), editable: false)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("本地模型状态")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Text(
                                    localWhisperModelStore.isDefaultModelInstalled
                                        ? "默认本地模型已安装，当前可以直接录音。"
                                        : "默认本地模型尚未安装。首次下载完成后会自动切换到本地 Whisper。"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                if localWhisperModelStore.isDownloading {
                                    ProgressView(value: localWhisperModelStore.downloadProgress)
                                    Text("下载进度：\(Int(localWhisperModelStore.downloadProgress * 100))%")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                if let lastErrorMessage = localWhisperModelStore.lastErrorMessage,
                                   !lastErrorMessage.isEmpty {
                                    Text(lastErrorMessage)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.red)
                                }
                            }

                            HStack(spacing: 10) {
                                Button(localWhisperModelStore.isDefaultModelInstalled ? "设为当前转写" : "下载并启用默认模型") {
                                    Task {
                                        if !localWhisperModelStore.isDefaultModelInstalled {
                                            let didInstall = await localWhisperModelStore.installDefaultModel()
                                            guard didInstall else { return }
                                        }

                                        modelSettingsStore.activateDefaultLocalWhisperModel()
                                        coordinator.refreshCredentialStatus()
                                    }
                                }
                                .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))
                                .disabled(localWhisperModelStore.isDownloading)

                                Button("重新显示首次提示") {
                                    localWhisperModelStore.shouldShowInstallPrompt = true
                                }
                                .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                            }
                        } else {
                            modelField(title: "默认模型", text: $modelSettingsStore.configuration.localSenseVoiceModel, editable: false)
                            modelField(title: "语言", text: $modelSettingsStore.configuration.localSenseVoiceLanguage)
                            modelField(title: "模型目录", text: .constant(senseVoiceModelStore.modelsDirectory.path), editable: false)
                            modelField(title: "运行时目录", text: .constant(senseVoiceModelStore.runtimeDirectory.path), editable: false)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("SenseVoice 状态")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Text(
                                    senseVoiceModelStore.isDefaultInstallationReady
                                        ? "SenseVoice 运行时和默认模型都已安装，当前可以直接录音。"
                                        : "SenseVoice 需要先安装运行时和默认模型。安装完成后会自动切换到本地 SenseVoice。"
                                )
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                                Text(senseVoiceModelStore.statusMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)

                                if senseVoiceModelStore.isDownloading {
                                    ProgressView(value: senseVoiceModelStore.downloadProgress)
                                    Text("安装进度：\(Int(senseVoiceModelStore.downloadProgress * 100))%")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                if let lastErrorMessage = senseVoiceModelStore.lastErrorMessage,
                                   !lastErrorMessage.isEmpty {
                                    Text(lastErrorMessage)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.red)
                                }
                            }

                            HStack(spacing: 10) {
                                Button(senseVoiceModelStore.isDefaultInstallationReady ? "设为当前转写" : "安装并启用默认模型") {
                                    Task {
                                        if !senseVoiceModelStore.isDefaultInstallationReady {
                                            let didInstall = await senseVoiceModelStore.installDefaultModel()
                                            guard didInstall else { return }
                                        }

                                        modelSettingsStore.activateDefaultSenseVoiceModel()
                                        coordinator.refreshCredentialStatus()
                                    }
                                }
                                .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))
                                .disabled(senseVoiceModelStore.isDownloading)

                                Button("重新显示首次提示") {
                                    senseVoiceModelStore.shouldShowInstallPrompt = true
                                }
                                .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                            }
                        }

                        Text(
                            (
                                modelSettingsStore.selectedSpeechProvider == .localWhisper ||
                                modelSettingsStore.selectedSpeechProvider == .localSenseVoice
                            )
                                ? (
                                    modelSettingsStore.currentSpeechCredentialStatus == .available
                                        ? "当前状态：本地模型已就绪"
                                        : "当前状态：本地模型未安装，录音按钮会保持不可用"
                                )
                                : (
                                    modelSettingsStore.currentSpeechCredentialStatus == .available
                                        ? "当前状态：\(modelSettingsStore.currentSpeechCredentialLabel) 已就绪"
                                        : "当前状态：还没有可用 \(modelSettingsStore.currentSpeechCredentialLabel)"
                                )
                        )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionHeader(
                            title: "OpenAI 研究与轻润色",
                            subtitle: "术语研究走 Responses API + web_search；轻润色走 Responses API，不启用 web_search。"
                        )

                        modelField(title: "Research Model", text: $modelSettingsStore.configuration.researchModel)
                        modelField(title: "Polish Model", text: $modelSettingsStore.configuration.polishModel)
                        modelField(title: "Shared Endpoint", text: $modelSettingsStore.configuration.researchEndpoint)
                        modelField(title: "Polish Endpoint (Auto)", text: $modelSettingsStore.configuration.polishEndpoint, editable: false)

                        SecureField("输入 OpenAI API Key", text: $modelSettingsStore.openAIAPIKeyInput)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Button("保存 OpenAI Key") {
                                do {
                                    try modelSettingsStore.saveOpenAIAPIKey()
                                    modelActionMessage = "OpenAI API Key 已保存。"
                                } catch {
                                    modelActionMessage = error.localizedDescription
                                }
                            }
                            .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))

                            Button("移除 OpenAI Key") {
                                do {
                                    try modelSettingsStore.removeOpenAIAPIKey()
                                    modelActionMessage = "OpenAI API Key 已移除。"
                                } catch {
                                    modelActionMessage = error.localizedDescription
                                }
                            }
                            .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("说明")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextEditor(text: .constant("术语生成会在保存职业后自动触发；轻润色默认走轻模式，并在输出为空、差异过大或超时时硬回退到原始转写。"))
                                .font(.system(size: 14))
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(store.palette.softFill.opacity(0.85))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(store.palette.border.opacity(0.8), lineWidth: 1)
                                )
                                .frame(minHeight: 120)
                                .disabled(true)
                        }

                        Text(modelSettingsStore.openAICredentialStatus == .available ? "当前状态：OpenAI Key 已就绪" : "当前状态：没有可用 OpenAI Key，轻润色会自动回退。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        if !modelActionMessage.isEmpty {
                            Text(modelActionMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(
                eyebrow: "设置",
                title: "设置与音频输入",
                subtitle: "集中管理主题、系统状态和录音设备。"
            )

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        sectionHeader(
                            title: "音频输入",
                            subtitle: "选择录音使用的麦克风。切换后会在下次开始录音时生效。"
                        )

                        Spacer()

                        Button("刷新设备") {
                            audioInputSettingsStore.refreshAvailableDevices()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                    }

                    StatusLine(label: "当前选择", value: audioInputSettingsStore.selectionSummary)
                    Text(audioInputSettingsStore.selectionHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        AudioInputOptionRow(
                            title: "系统默认",
                            subtitle: audioInputSettingsStore.defaultInputDeviceName,
                            isSelected: audioInputSettingsStore.selectedSelectionID == AudioInputSettingsStore.systemDefaultSelectionID,
                            palette: store.palette
                        ) {
                            audioInputSettingsStore.selectSystemDefault()
                        }

                        if audioInputSettingsStore.availableDevices.isEmpty {
                            EmptyStateCard(
                                title: "还没有检测到可用麦克风",
                                detail: "点击“刷新设备”重新扫描，或先在 macOS 中连接输入设备。"
                            )
                        } else {
                            ForEach(audioInputSettingsStore.availableDevices) { device in
                                AudioInputOptionRow(
                                    title: device.name,
                                    subtitle: "使用这个设备作为录音输入",
                                    isSelected: audioInputSettingsStore.selectedSelectionID == device.uid,
                                    palette: store.palette
                                ) {
                                    audioInputSettingsStore.selectDevice(uid: device.uid)
                                }
                            }
                        }
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "主题颜色",
                        subtitle: "选择后会立即应用到当前主界面。"
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        ForEach(HomeWindowStore.ThemePreset.allCases) { theme in
                            ThemePresetCard(
                                theme: theme,
                                isSelected: store.selectedTheme == theme
                            ) {
                                store.selectedTheme = theme
                            }
                        }
                    }
                }
            }

            GlassCard(palette: store.palette, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader(
                        title: "订阅接口",
                        subtitle: "预留网页订阅入口，后续接支付页面时无需改 UI 结构。"
                    )

                    modelField(title: "购买页面 URL", text: $store.subscriptionPurchaseURL)
                    modelField(title: "管理订阅 URL", text: $store.subscriptionManageURL)

                    HStack(spacing: 10) {
                        Button("打开购买页") {
                            openExternalURL(store.subscriptionPurchaseURL)
                        }
                        .buttonStyle(PrimaryPanelButtonStyle(palette: store.palette, isActive: false))
                        .disabled(normalizedExternalURL(from: store.subscriptionPurchaseURL) == nil)

                        Button("打开管理页") {
                            openExternalURL(store.subscriptionManageURL)
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                        .disabled(normalizedExternalURL(from: store.subscriptionManageURL) == nil)
                    }

                    Text("这两个入口仅负责跳转网页，不耦合支付 SDK，适合后续接你自己的订阅站点。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(
                            title: "关于",
                            subtitle: "当前软件版本与基础说明。"
                        )

                        StatusLine(label: "软件名", value: "SlashVibe")
                        StatusLine(label: "版本", value: store.currentVersionText)
                        StatusLine(label: "系统要求", value: "macOS 13+")
                        StatusLine(label: "当前转写", value: "\(modelSettingsStore.selectedSpeechProviderName) \(modelSettingsStore.currentSpeechModel) / \(modelSettingsStore.currentSpeechLanguage)")
                    }
                }

                GlassCard(palette: store.palette, padding: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(
                            title: "系统权限",
                            subtitle: "保留常用的系统入口，便于排查权限问题。"
                        )

                        PermissionStatusRow(
                            title: "辅助功能",
                            value: AccessibilityPermissionManager.isTrusted() ? "已授权" : "待授权"
                        )
                        PermissionStatusRow(
                            title: "麦克风",
                            value: audioInputSettingsStore.selectionSummary
                        )
                        PermissionStatusRow(
                            title: modelSettingsStore.currentSpeechCredentialLabel,
                            value: coordinator.credentialStatus == .available ? "已配置" : "未配置"
                        )

                        Button("打开辅助功能设置") {
                            AccessibilityPermissionManager.openSystemSettings()
                        }
                        .buttonStyle(SecondaryPanelButtonStyle(palette: store.palette))
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func transcriptBubble(title: String, text: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .overlay(alignment: .topLeading) {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .multilineTextAlignment(.leading)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(store.palette.border.opacity(0.65), lineWidth: 1)
                )
                .frame(minHeight: 88)
        }
    }

    private func modelField(title: String, text: Binding<String>, editable: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if editable {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
        }
    }

    private var isBusyWithoutStopAction: Bool {
        if case .finalizing = coordinator.sessionState {
            return true
        }
        return false
    }

    private var sessionTint: Color {
        switch coordinator.sessionState {
        case .idle:
            return Color(red: 0.57, green: 0.61, blue: 0.67)
        case .requestingPermission, .connecting:
            return store.palette.highlight
        case .recording:
            return Color(red: 0.84, green: 0.23, blue: 0.23)
        case .finalizing:
            return Color(red: 0.18, green: 0.44, blue: 0.82)
        case .failed:
            return Color(red: 0.79, green: 0.22, blue: 0.22)
        }
    }

    private func toggleRecording() {
        guard coordinator.credentialStatus == .available else { return }

        if store.isRecordingFlowActive {
            pushToTalkSource.sendReleased()
        } else if !isBusyWithoutStopAction {
            pushToTalkSource.sendPressed()
        }
    }

    private func normalizedExternalURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let directURL = URL(string: trimmed), directURL.scheme != nil {
            return directURL
        }
        return URL(string: "https://\(trimmed)")
    }

    private func openExternalURL(_ rawValue: String) {
        guard let url = normalizedExternalURL(from: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AudioInputOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let palette: HomeWindowStore.HomeThemePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? palette.accent.opacity(0.16) : Color.white.opacity(0.72))
                        .frame(width: 34, height: 34)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? palette.accent : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Text("当前使用")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.accent.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? palette.accent.opacity(0.55) : palette.border.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarTabButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let palette: HomeWindowStore.HomeThemePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.accent : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.90) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? palette.border.opacity(0.9) : Color.clear,
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarInfoCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(value)
                .font(.system(size: 16, weight: .semibold))

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }
}

private struct PageTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.66), in: Capsule())
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GlassCard<Content: View>: View {
    let palette: HomeWindowStore.HomeThemePalette
    let padding: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .slashVibeSurface(palette: palette, cornerRadius: 22)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.18), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .slashVibeSurface(palette: .init(
            accent: tint,
            accentSecondary: tint.opacity(0.7),
            highlight: tint,
            sidebarTop: .white,
            sidebarBottom: .white,
            canvasTop: .white,
            canvasBottom: .white,
            cardTop: .white,
            cardBottom: .white,
            border: tint.opacity(0.20),
            softFill: tint.opacity(0.10)
        ), cornerRadius: 20, accent: tint)
    }
}

private struct SessionBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
    }
}

private struct InlineTag: View {
    let title: String
    let value: String
    let symbol: String
    let palette: HomeWindowStore.HomeThemePalette
    var inHero: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(inHero ? palette.accent : palette.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(inHero ? Color.black.opacity(0.46) : .secondary)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(inHero ? Color(red: 0.11, green: 0.11, blue: 0.12) : .primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(inHero ? Color.white.opacity(0.76) : Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(inHero ? Color.black.opacity(0.08) : Color.clear, lineWidth: 1)
        )
    }
}

private struct StatusLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct CompactSummary: View {
    let title: String
    let value: String
    let palette: HomeWindowStore.HomeThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.softFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.48), lineWidth: 1)
        )
    }
}

private struct HistoryRow: View {
    let item: HomeWindowStore.TranscriptHistoryItem
    let palette: HomeWindowStore.HomeThemePalette
    let store: HomeWindowStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.accent.opacity(0.14))
                .overlay {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.formattedDate(item.createdAt))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(item.deliveryLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(palette.softFill, in: Capsule())
                }

                Text(item.text)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    Text("\(item.characterCount) 字")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(store.formattedDuration(item.durationSeconds))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .slashVibeSurface(palette: palette, cornerRadius: 18)
    }
}

private struct EmptyStateCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slashVibeSurface(palette: .init(
            accent: .gray,
            accentSecondary: .gray,
            highlight: .gray,
            sidebarTop: .white,
            sidebarBottom: .white,
            canvasTop: .white,
            canvasBottom: .white,
            cardTop: Color.white.opacity(0.96),
            cardBottom: Color.white.opacity(0.92),
            border: Color.black.opacity(0.06),
            softFill: Color.black.opacity(0.03)
        ), cornerRadius: 18)
    }
}

private struct SuggestionChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.82), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            )
    }
}

private struct PlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.clear)
                .slashVibeSurface(
                    palette: .init(
                        accent: .gray,
                        accentSecondary: .gray,
                        highlight: .gray,
                        sidebarTop: .white,
                        sidebarBottom: .white,
                        canvasTop: .white,
                        canvasBottom: .white,
                        cardTop: Color.white.opacity(0.98),
                        cardBottom: Color.white.opacity(0.92),
                        border: Color.black.opacity(0.06),
                        softFill: Color.black.opacity(0.03)
                    ),
                    cornerRadius: 18
                )

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
            }
        }
    }
}

private struct ThemePresetCard: View {
    let theme: HomeWindowStore.ThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let palette = theme.palette

        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.accent)
                        .frame(width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.accentSecondary)
                        .frame(width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.highlight)
                        .frame(width: 34, height: 34)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                }

                Text(theme.title)
                    .font(.system(size: 16, weight: .semibold))

                Text(theme.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [palette.cardTop, palette.cardBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? palette.accent : palette.border.opacity(0.8), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? palette.accent.opacity(0.14) : Color.black.opacity(0.04), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutKeyCaps: View {
    let symbols: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrimaryPanelButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                (isActive ? Color(red: 0.86, green: 0.22, blue: 0.18) : palette.accent),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.992 : 1.0)
    }
}

private struct SecondaryPanelButtonStyle: ButtonStyle {
    let palette: HomeWindowStore.HomeThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.border.opacity(0.78), lineWidth: 1)
            )
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
        }
    }
