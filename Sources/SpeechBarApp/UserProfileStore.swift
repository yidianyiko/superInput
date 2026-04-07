import Combine
import Foundation
import SpeechBarDomain

@MainActor
final class UserProfileStore: ObservableObject, UserProfileContextProviding, @unchecked Sendable {
    @Published var profession: String
    @Published var memoryProfile: String
    @Published var terminologyGlossary: [TerminologyEntry]
    @Published var isTerminologyGlossaryEnabled: Bool
    @Published var polishMode: TranscriptPolishMode
    @Published var skipShortPolish: Bool
    @Published var shortPolishCharacterThreshold: Int
    @Published var useClipboardContextForPolish: Bool
    @Published var useFrontmostAppContextForPolish: Bool
    @Published var polishTimeoutSeconds: Double
    @Published private(set) var isGeneratingTerminology = false
    @Published private(set) var terminologyStatusMessage = "填写职业后会自动生成术语词表。"
    @Published private(set) var lastGeneratedAt: Date?

    private let defaults: UserDefaults
    private let researchClient: (any TerminologyResearchClient)?
    private var cancellables: Set<AnyCancellable> = []
    private var lastActivePolishMode: TranscriptPolishMode

    init(
        defaults: UserDefaults = .standard,
        researchClient: (any TerminologyResearchClient)? = nil
    ) {
        self.defaults = defaults
        self.researchClient = researchClient
        let initialPolishMode = Self.loadPolishMode(from: defaults)
        self.profession = defaults.string(forKey: Keys.profession) ?? ""
        self.memoryProfile = defaults.string(forKey: Keys.memoryProfile) ?? ""
        self.terminologyGlossary = Self.loadGlossary(from: defaults)
        self.isTerminologyGlossaryEnabled = Self.loadTerminologyGlossaryEnabled(from: defaults)
        self.polishMode = initialPolishMode
        self.skipShortPolish = Self.loadSkipShortPolish(from: defaults)
        self.shortPolishCharacterThreshold = Self.loadShortPolishCharacterThreshold(from: defaults)
        self.useClipboardContextForPolish = Self.loadUseClipboardContextForPolish(from: defaults)
        self.useFrontmostAppContextForPolish = Self.loadUseFrontmostAppContextForPolish(from: defaults)
        self.polishTimeoutSeconds = Self.loadPolishTimeoutSeconds(from: defaults)
        self.lastActivePolishMode = Self.loadLastActivePolishMode(from: defaults, current: initialPolishMode)
        self.lastGeneratedAt = defaults.object(forKey: Keys.lastGeneratedAt) as? Date
        bindPersistence()
    }

    var isPolishEnabled: Bool {
        polishMode != .off
    }

    func currentContext() async -> UserProfileContext {
        UserProfileContext(
            profession: profession,
            memoryProfile: memoryProfile,
            terminologyGlossary: terminologyGlossary,
            isTerminologyGlossaryEnabled: isTerminologyGlossaryEnabled,
            polishMode: polishMode,
            skipShortPolish: skipShortPolish,
            shortPolishCharacterThreshold: shortPolishCharacterThreshold,
            useClipboardContextForPolish: useClipboardContextForPolish,
            useFrontmostAppContextForPolish: useFrontmostAppContextForPolish,
            polishTimeoutSeconds: polishTimeoutSeconds
        )
    }

    func setPolishEnabled(_ enabled: Bool) {
        if enabled {
            guard polishMode == .off else { return }
            let restoredMode = lastActivePolishMode == .off ? .light : lastActivePolishMode
            polishMode = restoredMode
            return
        }

        guard polishMode != .off else { return }
        lastActivePolishMode = polishMode
        defaults.set(lastActivePolishMode.rawValue, forKey: Keys.lastActivePolishMode)
        polishMode = .off
    }

    func saveProfessionAndGenerateTerminology() async {
        let trimmedProfession = profession.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedProfession, forKey: Keys.profession)
        profession = trimmedProfession
        await refreshTerminology()
    }

    func refreshTerminology() async {
        let trimmedProfession = profession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfession.isEmpty else {
            terminologyStatusMessage = "先填写职业，再生成术语词表。"
            return
        }
        guard !isGeneratingTerminology else { return }
        guard let researchClient else {
            terminologyStatusMessage = "术语研究服务尚未配置。"
            return
        }

        isGeneratingTerminology = true
        terminologyStatusMessage = "正在研究术语词表..."
        defer { isGeneratingTerminology = false }

        do {
            let glossary = try await researchClient.generateTerminology(
                profession: trimmedProfession,
                memoryProfile: memoryProfile
            )

            guard !glossary.isEmpty else {
                terminologyStatusMessage = "没有生成有效术语，请调整职业描述后重试。"
                return
            }

            terminologyGlossary = glossary
            lastGeneratedAt = Date()
            defaults.set(lastGeneratedAt, forKey: Keys.lastGeneratedAt)
            terminologyStatusMessage = "已生成 \(glossary.count) 个领域术语。"
        } catch {
            terminologyStatusMessage = error.localizedDescription.isEmpty
                ? "术语词表生成失败。"
                : error.localizedDescription
        }
    }

    func addMemoryTemplate(_ template: String) {
        let trimmed = memoryProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            memoryProfile = template
        } else {
            memoryProfile += "\n\n" + template
        }
    }

    func updateGlossaryTerm(id: UUID, term: String) {
        guard let index = terminologyGlossary.firstIndex(where: { $0.id == id }) else { return }
        terminologyGlossary[index].term = term
    }

    func toggleGlossaryTerm(id: UUID) {
        guard let index = terminologyGlossary.firstIndex(where: { $0.id == id }) else { return }
        terminologyGlossary[index].isEnabled.toggle()
    }

    func appendGlossaryTerm() {
        terminologyGlossary.append(TerminologyEntry(term: "", isEnabled: true))
    }

    func removeGlossaryTerm(id: UUID) {
        terminologyGlossary.removeAll { $0.id == id }
    }

    private func bindPersistence() {
        $profession
            .dropFirst()
            .sink { [weak self] profession in
                self?.defaults.set(profession, forKey: Keys.profession)
            }
            .store(in: &cancellables)

        $memoryProfile
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.memoryProfile)
            }
            .store(in: &cancellables)

        $terminologyGlossary
            .dropFirst()
            .sink { [weak self] glossary in
                self?.saveGlossary(glossary)
            }
            .store(in: &cancellables)

        $isTerminologyGlossaryEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.isTerminologyGlossaryEnabled)
            }
            .store(in: &cancellables)

        $polishMode
            .dropFirst()
            .sink { [weak self] mode in
                self?.defaults.set(mode.rawValue, forKey: Keys.polishMode)
                if mode != .off {
                    self?.lastActivePolishMode = mode
                    self?.defaults.set(mode.rawValue, forKey: Keys.lastActivePolishMode)
                }
            }
            .store(in: &cancellables)

        $skipShortPolish
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.skipShortPolish)
            }
            .store(in: &cancellables)

        $shortPolishCharacterThreshold
            .dropFirst()
            .sink { [weak self] value in
                let normalized = Self.clampShortPolishCharacterThreshold(value)
                self?.defaults.set(normalized, forKey: Keys.shortPolishCharacterThreshold)
            }
            .store(in: &cancellables)

        $useClipboardContextForPolish
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.useClipboardContextForPolish)
            }
            .store(in: &cancellables)

        $useFrontmostAppContextForPolish
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.useFrontmostAppContextForPolish)
            }
            .store(in: &cancellables)

        $polishTimeoutSeconds
            .dropFirst()
            .sink { [weak self] value in
                let normalized = Self.clampPolishTimeoutSeconds(value)
                self?.defaults.set(normalized, forKey: Keys.polishTimeoutSeconds)
            }
            .store(in: &cancellables)
    }

    private func saveGlossary(_ glossary: [TerminologyEntry]) {
        if let data = try? JSONEncoder().encode(glossary) {
            defaults.set(data, forKey: Keys.terminologyGlossary)
        }
    }

    private static func loadGlossary(from defaults: UserDefaults) -> [TerminologyEntry] {
        guard
            let data = defaults.data(forKey: Keys.terminologyGlossary),
            let glossary = try? JSONDecoder().decode([TerminologyEntry].self, from: data)
        else {
            return []
        }
        return glossary
    }

    private static func loadTerminologyGlossaryEnabled(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Keys.isTerminologyGlossaryEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.isTerminologyGlossaryEnabled)
    }

    private static func loadPolishMode(from defaults: UserDefaults) -> TranscriptPolishMode {
        guard
            let rawValue = defaults.string(forKey: Keys.polishMode),
            let mode = TranscriptPolishMode(rawValue: rawValue)
        else {
            return .light
        }
        return mode
    }

    private static func loadLastActivePolishMode(
        from defaults: UserDefaults,
        current: TranscriptPolishMode
    ) -> TranscriptPolishMode {
        if let rawValue = defaults.string(forKey: Keys.lastActivePolishMode),
           let mode = TranscriptPolishMode(rawValue: rawValue),
           mode != .off {
            return mode
        }

        if current != .off {
            return current
        }

        return .light
    }

    private static func loadSkipShortPolish(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Keys.skipShortPolish) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.skipShortPolish)
    }

    private static func loadShortPolishCharacterThreshold(from defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: Keys.shortPolishCharacterThreshold) != nil else {
            return 8
        }
        return clampShortPolishCharacterThreshold(defaults.integer(forKey: Keys.shortPolishCharacterThreshold))
    }

    private static func loadUseClipboardContextForPolish(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Keys.useClipboardContextForPolish) == nil {
            return false
        }
        return defaults.bool(forKey: Keys.useClipboardContextForPolish)
    }

    private static func loadUseFrontmostAppContextForPolish(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Keys.useFrontmostAppContextForPolish) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.useFrontmostAppContextForPolish)
    }

    private static func loadPolishTimeoutSeconds(from defaults: UserDefaults) -> Double {
        guard defaults.object(forKey: Keys.polishTimeoutSeconds) != nil else {
            return 1.8
        }
        return clampPolishTimeoutSeconds(defaults.double(forKey: Keys.polishTimeoutSeconds))
    }

    private static func clampShortPolishCharacterThreshold(_ value: Int) -> Int {
        min(max(value, 2), 40)
    }

    private static func clampPolishTimeoutSeconds(_ value: Double) -> Double {
        min(max(value, 1.0), 5.0)
    }

    private enum Keys {
        static let profession = "profile.profession"
        static let memoryProfile = "home.memoryProfile"
        static let terminologyGlossary = "profile.terminologyGlossary"
        static let isTerminologyGlossaryEnabled = "profile.isTerminologyGlossaryEnabled"
        static let polishMode = "profile.polishMode"
        static let lastActivePolishMode = "profile.lastActivePolishMode"
        static let skipShortPolish = "profile.skipShortPolish"
        static let shortPolishCharacterThreshold = "profile.shortPolishCharacterThreshold"
        static let useClipboardContextForPolish = "profile.useClipboardContextForPolish"
        static let useFrontmostAppContextForPolish = "profile.useFrontmostAppContextForPolish"
        static let polishTimeoutSeconds = "profile.polishTimeoutSeconds"
        static let lastGeneratedAt = "profile.lastGeneratedAt"
    }
}
