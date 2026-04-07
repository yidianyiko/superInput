import Foundation
import SpeechBarDomain

public struct AgentRegistryEntry: Sendable {
    public let provider: AgentProvider
    public let isEnabledByDefault: Bool
    public let makeCollector: @Sendable () -> any AgentCollector

    public init(
        provider: AgentProvider,
        isEnabledByDefault: Bool = true,
        makeCollector: @escaping @Sendable () -> any AgentCollector
    ) {
        self.provider = provider
        self.isEnabledByDefault = isEnabledByDefault
        self.makeCollector = makeCollector
    }
}

public struct DefaultAgentRegistry {
    public let entries: [AgentRegistryEntry]

    public init(entries: [AgentRegistryEntry] = [
        AgentRegistryEntry(provider: .claudeCode) { ClaudeHookCollector() },
        AgentRegistryEntry(provider: .codexCLI) { CodexJSONLCollector() },
        AgentRegistryEntry(provider: .geminiCLI) { GeminiHookCollector() },
        AgentRegistryEntry(provider: .cursorAgent) { CursorHookCollector() }
    ]) {
        self.entries = entries
    }

    public func makeEnabledCollectors() -> [any AgentCollector] {
        entries
            .filter(\.isEnabledByDefault)
            .map { $0.makeCollector() }
    }
}
