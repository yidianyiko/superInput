import SpeechBarDomain
import SwiftUI

struct MemoryProfileSettingsSection: View {
    @ObservedObject var userProfileStore: UserProfileStore
    @ObservedObject var memoryFeatureFlagStore: MemoryFeatureFlagStore

    @State private var isExpanded = false

    private let polishCharacterThresholdOptions = [4, 8, 12, 20]
    private let polishTimeoutOptions: [Double] = [1.0, 1.5, 1.8, 2.5, 3.0]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 20) {
                professionSection
                memoryProfileSection
                polishSection
                inputMemorySection
                glossarySection
            }
            .padding(.top, 18)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Secondary Memory Controls")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(MemoryConstellationTheme.primaryText)
                    Text("Keep the manual profile, recall, and glossary controls close at hand without overpowering the constellation.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MemoryConstellationTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(isExpanded ? "Hide" : "Show")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(MemoryConstellationTheme.focusGold)
            }
        }
        .tint(MemoryConstellationTheme.focusGold)
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(18)
    }

    private var professionSection: some View {
        section(title: "职业与术语研究", subtitle: "保存职业后自动生成领域术语用于识别增强。") {
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
                .buttonStyle(.borderedProminent)
                .disabled(userProfileStore.isGeneratingTerminology)

                Button("重新生成") {
                    Task {
                        await userProfileStore.refreshTerminology()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(userProfileStore.isGeneratingTerminology)
            }

            HStack(spacing: 10) {
                Text(userProfileStore.terminologyStatusMessage)
                if let lastGeneratedAt = userProfileStore.lastGeneratedAt {
                    Text("最近更新：\(formattedDate(lastGeneratedAt))")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var memoryProfileSection: some View {
        section(title: "背景与表达偏好", subtitle: "描述常见场景、语气偏好和高频术语。") {
            TextEditor(text: $userProfileStore.memoryProfile)
                .font(.system(size: 13))
                .padding(10)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 8) {
                suggestionChip("职业背景") {
                    userProfileStore.addMemoryTemplate("我是创业者，平时会围绕 AI 产品、增长、融资和团队协作做高频沟通。")
                }
                suggestionChip("表达风格") {
                    userProfileStore.addMemoryTemplate("我希望输出更自然、有段落感，尽量避免机械口语和重复表达。")
                }
                suggestionChip("术语偏好") {
                    userProfileStore.addMemoryTemplate("请保留常见英文产品词汇、技术术语和模型名称，不要强行翻译。")
                }
            }
        }
    }

    private var polishSection: some View {
        section(title: "AI 后处理润色", subtitle: "录音结束后，使用 OpenAI 对原始转写做纠错和表达整理。") {
            Toggle("启用 AI 润色", isOn: polishEnabledBinding)

            if userProfileStore.isPolishEnabled {
                Picker("润色模式", selection: $userProfileStore.polishMode) {
                    Text("轻润色").tag(TranscriptPolishMode.light)
                    Text("聊天表达").tag(TranscriptPolishMode.chat)
                }
                .pickerStyle(.segmented)

                Toggle("跳过短句润色", isOn: $userProfileStore.skipShortPolish)

                if userProfileStore.skipShortPolish {
                    Picker("短句阈值", selection: $userProfileStore.shortPolishCharacterThreshold) {
                        ForEach(polishCharacterThresholdOptions, id: \.self) { value in
                            Text(polishThresholdLabel(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("使用前台应用上下文", isOn: $userProfileStore.useFrontmostAppContextForPolish)
                Toggle("使用剪贴板上下文", isOn: $userProfileStore.useClipboardContextForPolish)

                Picker("请求超时", selection: $userProfileStore.polishTimeoutSeconds) {
                    ForEach(polishTimeoutOptions, id: \.self) { value in
                        Text(polishTimeoutLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Text("关闭后将直接使用原始转写结果；重新开启时会恢复你上次使用的润色模式。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputMemorySection: some View {
        section(title: "输入记忆", subtitle: "采集默认开启，召回默认关闭，便于先观察本地学习效果。") {
            Toggle("启用记忆采集", isOn: $memoryFeatureFlagStore.captureEnabled)
            Toggle("启用记忆召回", isOn: $memoryFeatureFlagStore.recallEnabled)

            Text("记忆仅保存在本机，敏感输入会被排除或脱敏处理。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var glossarySection: some View {
        section(title: "术语词表", subtitle: "开启后参与识别增强与 AI 润色，关闭后仅保存词表。") {
            HStack {
                Toggle("术语词表增强", isOn: $userProfileStore.isTerminologyGlossaryEnabled)
                Spacer()
                Button("添加术语") {
                    userProfileStore.appendGlossaryTerm()
                }
                .buttonStyle(.bordered)
            }

            if userProfileStore.terminologyGlossary.isEmpty {
                Text("还没有术语词表。先填写职业并生成术语，或手动添加词条。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(userProfileStore.terminologyGlossary) { entry in
                        HStack(spacing: 12) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { entry.isEnabled },
                                    set: { _ in userProfileStore.toggleGlossaryTerm(id: entry.id) }
                                )
                            )
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
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var polishEnabledBinding: Binding<Bool> {
        Binding(
            get: { userProfileStore.isPolishEnabled },
            set: { userProfileStore.setPolishEnabled($0) }
        )
    }

    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func suggestionChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func polishThresholdLabel(_ value: Int) -> String {
        "\(value) 字以下"
    }

    private func polishTimeoutLabel(_ value: Double) -> String {
        String(format: "%.1f 秒", value)
    }
}
