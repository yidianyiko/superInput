import AppKit
import Foundation
import SpeechBarDomain

public actor OpenAIResponsesTranscriptPostProcessor: TranscriptPostProcessor {
    private let session: URLSession
    private let credentialProvider: any CredentialProvider
    private let configurationProvider: any OpenAIResponsesConfigurationProviding

    public init(
        session: URLSession = .shared,
        credentialProvider: any CredentialProvider,
        configurationProvider: any OpenAIResponsesConfigurationProviding
    ) {
        self.session = session
        self.credentialProvider = credentialProvider
        self.configurationProvider = configurationProvider
    }

    public func polish(
        transcript: String,
        context: UserProfileContext
    ) async throws -> String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return transcript }
        guard context.polishMode != .off else { return trimmedTranscript }

        let apiKey = try loadAPIKey()
        let configuration = await configurationProvider.polishConfiguration()
        let requestConfiguration = OpenAIResponsesRequestConfiguration(
            endpoint: configuration.endpoint,
            model: configuration.model,
            timeoutInterval: effectiveTimeoutInterval(base: configuration.timeoutInterval, context: context)
        )
        let glossary = context.isTerminologyGlossaryEnabled
            ? glossarySection(from: context.terminologyGlossary)
            : "未提供"
        let runtimeContext = await loadRuntimeContext(transcript: trimmedTranscript, context: context)

        let styleGuidance = switch context.polishMode {
        case .off:
            "不要改写。"
        case .light:
            "只做轻润色，尽量贴近原话。"
        case .chat:
            "整理成更自然的聊天表达，但不要改变原意。"
        case .reply:
            "整理成可以直接发送的聊天回复，像本人会发出去的话，简洁自然，不要加标题、解释或项目符号。"
        }

        let instructions = """
        你是中文语音输入的后处理器，只输出最终文本。
        只修正明显识别错误、重复、口头禅和自然标点，不补充事实，不回答，不解释，不续写。
        保留原意、语气、英文术语、品牌名、模型名、API 名、文件名、链接、邮箱、数字、日期和时间。
        上下文只用于判断用词，不能把上下文内容写进结果。
        \(styleGuidance)
        """

        let prompt = makePrompt(
            transcript: trimmedTranscript,
            context: context,
            glossary: glossary,
            runtimeContext: runtimeContext
        )

        let body: [String: Any] = [
            "model": requestConfiguration.model,
            "instructions": instructions,
            "input": prompt,
            "max_output_tokens": maxOutputTokens(for: trimmedTranscript, mode: context.polishMode)
        ]

        let polished = try await performRequest(
            configuration: requestConfiguration,
            apiKey: apiKey,
            body: body
        )

        let normalized = sanitizeModelOutput(polished)
        guard !normalized.isEmpty else {
            throw OpenAIResponsesClientError.emptyOutput
        }
        return normalized
    }

    private func performRequest(
        configuration: OpenAIResponsesRequestConfiguration,
        apiKey: String,
        body: [String: Any]
    ) async throws -> String {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIResponsesClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIResponsesClientError.badHTTPStatus(httpResponse.statusCode, body)
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        let text = envelope.outputText
        guard !text.isEmpty else {
            throw OpenAIResponsesClientError.emptyOutput
        }
        return text
    }

    private func loadAPIKey() throws -> String {
        do {
            return try credentialProvider.loadAPIKey()
        } catch {
            throw OpenAIResponsesClientError.missingAPIKey
        }
    }

    private func glossarySection(from glossary: [TerminologyEntry]) -> String {
        var seen = Set<String>()
        let terms = glossary
            .filter(\.isEnabled)
            .map(\.term)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(40)

        let lines = terms.map { "- \($0)" }
        return lines.isEmpty ? "未提供" : lines.joined(separator: "\n")
    }

    private func loadRuntimeContext(
        transcript: String,
        context: UserProfileContext
    ) async -> RuntimeContext {
        guard context.useFrontmostAppContextForPolish || context.useClipboardContextForPolish else {
            return RuntimeContext(frontmostAppDescription: nil, clipboardDescription: nil)
        }

        let snapshot = await MainActor.run { () -> (String?, String?, String?) in
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            let appName = frontmostApplication?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleIdentifier = frontmostApplication?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipboardText = context.useClipboardContextForPolish
                ? NSPasteboard.general.string(forType: .string)
                : nil
            return (appName, bundleIdentifier, clipboardText)
        }

        return RuntimeContext(
            frontmostAppDescription: context.useFrontmostAppContextForPolish
                ? frontmostAppDescription(
                    appName: snapshot.0,
                    bundleIdentifier: snapshot.1
                )
                : nil,
            clipboardDescription: clipboardDescription(
                clipboardText: snapshot.2,
                transcript: transcript
            )
        )
    }

    private func frontmostAppDescription(
        appName: String?,
        bundleIdentifier: String?
    ) -> String? {
        let normalizedAppName = normalizedSectionText(appName, emptyFallback: "")
        let normalizedBundleIdentifier = normalizedSectionText(bundleIdentifier, emptyFallback: "")

        if !normalizedAppName.isEmpty, !normalizedBundleIdentifier.isEmpty {
            return "当前前台应用：\(normalizedAppName) (\(normalizedBundleIdentifier))"
        }

        if !normalizedAppName.isEmpty {
            return "当前前台应用：\(normalizedAppName)"
        }

        if !normalizedBundleIdentifier.isEmpty {
            return "当前前台应用 Bundle ID：\(normalizedBundleIdentifier)"
        }

        return nil
    }

    private func clipboardDescription(
        clipboardText: String?,
        transcript: String
    ) -> String? {
        let trimmedClipboard = clipboardText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedClipboard.isEmpty else {
            return nil
        }

        guard trimmedClipboard != transcript else {
            return nil
        }

        return clippedText(trimmedClipboard, limit: 240)
    }

    private func sanitizeModelOutput(_ text: String) -> String {
        var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.hasPrefix("```") {
            sanitized = sanitized.replacingOccurrences(
                of: #"^```[A-Za-z0-9_-]*\s*"#,
                with: "",
                options: .regularExpression
            )
            sanitized = sanitized.replacingOccurrences(
                of: #"\s*```$"#,
                with: "",
                options: .regularExpression
            )
            sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        sanitized = sanitized.replacingOccurrences(
            of: #"^(润色后|润色结果|最终文本|输出|结果|Polished text|Polished transcript)\s*[:：]\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
            ("‘", "’"),
            ("「", "」")
        ]

        for (start, end) in quotePairs {
            if sanitized.first == start, sanitized.last == end, sanitized.count >= 2 {
                sanitized.removeFirst()
                sanitized.removeLast()
                sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return sanitized
    }

    private func normalizedSectionText(_ text: String?, emptyFallback: String) -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? emptyFallback : trimmed
    }

    private func clippedText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    private func effectiveTimeoutInterval(
        base: TimeInterval,
        context: UserProfileContext
    ) -> TimeInterval {
        let preferred = min(max(context.polishTimeoutSeconds, 1.0), 5.0)
        return min(max(base, 1.0), preferred)
    }

    private func maxOutputTokens(
        for transcript: String,
        mode: TranscriptPolishMode
    ) -> Int {
        let count = transcript.count

        switch mode {
        case .off:
            return 96
        case .light:
            return min(max(Int(Double(count) * 1.15) + 32, 96), 320)
        case .chat:
            return min(max(Int(Double(count) * 1.35) + 48, 128), 420)
        case .reply:
            return min(max(Int(Double(count) * 1.2) + 48, 128), 360)
        }
    }

    private func makePrompt(
        transcript: String,
        context: UserProfileContext,
        glossary: String,
        runtimeContext: RuntimeContext
    ) -> String {
        var sections: [String] = []

        let profession = normalizedSectionText(context.profession, emptyFallback: "")
        let memoryProfile = normalizedSectionText(context.memoryProfile, emptyFallback: "")
        if !profession.isEmpty || !memoryProfile.isEmpty {
            sections.append(
                """
                <USER_PROFILE>
                职业：\(profession.isEmpty ? "未提供" : profession)
                表达偏好：\(memoryProfile.isEmpty ? "未提供" : memoryProfile)
                </USER_PROFILE>
                """
            )
        }

        if glossary != "未提供" {
            sections.append(
                """
                <CUSTOM_VOCABULARY>
                \(glossary)
                </CUSTOM_VOCABULARY>
                """
            )
        }

        if let frontmostAppDescription = runtimeContext.frontmostAppDescription {
            sections.append(
                """
                <CURRENT_APP_CONTEXT>
                \(frontmostAppDescription)
                </CURRENT_APP_CONTEXT>
                """
            )
        }

        if let clipboardDescription = runtimeContext.clipboardDescription {
            sections.append(
                """
                <CLIPBOARD_CONTEXT>
                \(clipboardDescription)
                </CLIPBOARD_CONTEXT>
                """
            )
        }

        sections.append(
            """
            <TRANSCRIPT>
            \(transcript)
            </TRANSCRIPT>
            """
        )

        return sections.joined(separator: "\n\n")
    }
}

private struct RuntimeContext {
    let frontmostAppDescription: String?
    let clipboardDescription: String?
}
