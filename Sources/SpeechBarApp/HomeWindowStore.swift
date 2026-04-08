import Combine
import Foundation
import SpeechBarApplication
import SpeechBarDomain
import SwiftUI

@MainActor
final class HomeWindowStore: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case home = "首页"
        case memory = "记忆"
        case model = "模型"
        case monitor = "监控"
        case debug = "调试"
        case settings = "设置"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .home:
                return "square.grid.2x2.fill"
            case .memory:
                return "brain.head.profile"
            case .model:
                return "slider.horizontal.3"
            case .monitor:
                return "rectangle.3.group.bubble.left.fill"
            case .debug:
                return "waveform.badge.magnifyingglass"
            case .settings:
                return "gearshape.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .home:
                return "统计与记录"
            case .memory:
                return "关系星图"
            case .model:
                return "接口配置"
            case .monitor:
                return "任务与链路"
            case .debug:
                return "诊断与回放"
            case .settings:
                return "主题与关于"
            }
        }
    }

    enum ThemePreset: String, CaseIterable, Codable, Identifiable {
        case apple
        case sunrise
        case ocean
        case forest
        case graphite

        var id: String { rawValue }

        var title: String {
            switch self {
            case .apple:
                return "Apple"
            case .sunrise:
                return "日光橙"
            case .ocean:
                return "海盐蓝"
            case .forest:
                return "苔原绿"
            case .graphite:
                return "石墨灰"
            }
        }

        var subtitle: String {
            switch self {
            case .apple:
                return "浅灰画布、黑白层级与单一蓝色强调"
            case .sunrise:
                return "更接近效率工具的暖色桌面感"
            case .ocean:
                return "偏冷静、专业的工作流风格"
            case .forest:
                return "更柔和，适合长时间使用"
            case .graphite:
                return "更克制，接近深色工业设计"
            }
        }

        var palette: HomeThemePalette {
            switch self {
            case .apple:
                return HomeThemePalette(
                    accent: Color(red: 0.00, green: 0.44, blue: 0.89),
                    accentSecondary: Color(red: 0.00, green: 0.40, blue: 0.80),
                    highlight: Color(red: 0.11, green: 0.11, blue: 0.12),
                    sidebarTop: Color.white.opacity(0.96),
                    sidebarBottom: Color(red: 0.97, green: 0.97, blue: 0.98),
                    canvasTop: Color(red: 0.96, green: 0.96, blue: 0.97),
                    canvasBottom: Color(red: 0.95, green: 0.95, blue: 0.96),
                    cardTop: Color.white.opacity(0.98),
                    cardBottom: Color.white.opacity(0.94),
                    border: Color.black.opacity(0.08),
                    softFill: Color.black.opacity(0.035)
                )
            case .sunrise:
                return HomeThemePalette(
                    accent: Color(red: 0.92, green: 0.47, blue: 0.24),
                    accentSecondary: Color(red: 0.98, green: 0.76, blue: 0.41),
                    highlight: Color(red: 0.96, green: 0.59, blue: 0.34),
                    sidebarTop: Color(red: 0.98, green: 0.95, blue: 0.92),
                    sidebarBottom: Color(red: 0.95, green: 0.89, blue: 0.85),
                    canvasTop: Color(red: 0.99, green: 0.98, blue: 0.96),
                    canvasBottom: Color(red: 0.96, green: 0.93, blue: 0.90),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.99, green: 0.96, blue: 0.93),
                    border: Color(red: 0.90, green: 0.84, blue: 0.79),
                    softFill: Color(red: 0.98, green: 0.93, blue: 0.88)
                )
            case .ocean:
                return HomeThemePalette(
                    accent: Color(red: 0.17, green: 0.47, blue: 0.78),
                    accentSecondary: Color(red: 0.27, green: 0.77, blue: 0.86),
                    highlight: Color(red: 0.21, green: 0.62, blue: 0.86),
                    sidebarTop: Color(red: 0.92, green: 0.96, blue: 0.99),
                    sidebarBottom: Color(red: 0.87, green: 0.92, blue: 0.97),
                    canvasTop: Color(red: 0.96, green: 0.98, blue: 1.00),
                    canvasBottom: Color(red: 0.91, green: 0.95, blue: 0.99),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.94, green: 0.98, blue: 1.00),
                    border: Color(red: 0.80, green: 0.88, blue: 0.95),
                    softFill: Color(red: 0.90, green: 0.96, blue: 0.99)
                )
            case .forest:
                return HomeThemePalette(
                    accent: Color(red: 0.25, green: 0.53, blue: 0.37),
                    accentSecondary: Color(red: 0.65, green: 0.78, blue: 0.45),
                    highlight: Color(red: 0.41, green: 0.66, blue: 0.44),
                    sidebarTop: Color(red: 0.94, green: 0.97, blue: 0.93),
                    sidebarBottom: Color(red: 0.89, green: 0.93, blue: 0.87),
                    canvasTop: Color(red: 0.97, green: 0.99, blue: 0.95),
                    canvasBottom: Color(red: 0.92, green: 0.96, blue: 0.91),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.95, green: 0.98, blue: 0.93),
                    border: Color(red: 0.82, green: 0.88, blue: 0.79),
                    softFill: Color(red: 0.92, green: 0.96, blue: 0.89)
                )
            case .graphite:
                return HomeThemePalette(
                    accent: Color(red: 0.28, green: 0.34, blue: 0.48),
                    accentSecondary: Color(red: 0.73, green: 0.53, blue: 0.36),
                    highlight: Color(red: 0.39, green: 0.47, blue: 0.62),
                    sidebarTop: Color(red: 0.92, green: 0.93, blue: 0.95),
                    sidebarBottom: Color(red: 0.86, green: 0.88, blue: 0.91),
                    canvasTop: Color(red: 0.96, green: 0.97, blue: 0.98),
                    canvasBottom: Color(red: 0.90, green: 0.92, blue: 0.95),
                    cardTop: Color.white,
                    cardBottom: Color(red: 0.95, green: 0.95, blue: 0.97),
                    border: Color(red: 0.81, green: 0.83, blue: 0.87),
                    softFill: Color(red: 0.92, green: 0.93, blue: 0.95)
                )
            }
        }
    }

    struct HomeThemePalette {
        let accent: Color
        let accentSecondary: Color
        let highlight: Color
        let sidebarTop: Color
        let sidebarBottom: Color
        let canvasTop: Color
        let canvasBottom: Color
        let cardTop: Color
        let cardBottom: Color
        let border: Color
        let softFill: Color
    }

    struct TranscriptHistoryItem: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        let createdAt: Date
        let characterCount: Int
        let durationSeconds: TimeInterval
        let deliveryLabel: String
    }

    struct ModelConfiguration: Codable, Equatable {
        var speechProvider: String = "Deepgram"
        var speechEndpoint: String = "https://api.deepgram.com/v1/listen"
        var speechModel: String = "nova-2"
        var language: String = "zh-CN"
        var apiBase: String = ""
        var polishProvider: String = "预留"
        var polishEndpoint: String = ""
        var notes: String = "当前支持 Deepgram、Whisper API、本地 Whisper 和本地 SenseVoice 转写，其余字段继续保留给后续多模型架构。"
    }

    struct DailyUsagePoint: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let isToday: Bool
    }

    @Published var selectedSection: Section
    @Published var memoryProfile: String
    @Published var selectedTheme: ThemePreset
    @Published var modelConfiguration: ModelConfiguration
    @Published var subscriptionPurchaseURL: String
    @Published var subscriptionManageURL: String
    @Published var apiKeyInput = ""
    @Published private(set) var history: [TranscriptHistoryItem]

    let coordinator: VoiceSessionCoordinator
    private static let currentThemeStyleVersion = 2

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(
        coordinator: VoiceSessionCoordinator,
        defaults: UserDefaults = .standard
    ) {
        self.coordinator = coordinator
        self.defaults = defaults
        self.selectedSection = Self.loadSection(from: defaults)
        self.memoryProfile = Self.loadString(forKey: Keys.memoryProfile, from: defaults)
        let loadedTheme = Self.loadTheme(from: defaults)
        let shouldAdoptAppleTheme = defaults.integer(forKey: Keys.themeStyleVersion) < Self.currentThemeStyleVersion
        self.selectedTheme = shouldAdoptAppleTheme ? .apple : loadedTheme
        self.modelConfiguration = Self.loadModelConfiguration(from: defaults)
        self.subscriptionPurchaseURL = Self.loadString(
            forKey: Keys.subscriptionPurchaseURL,
            from: defaults,
            fallback: "https://your-domain.com/pricing"
        )
        self.subscriptionManageURL = Self.loadString(
            forKey: Keys.subscriptionManageURL,
            from: defaults,
            fallback: "https://your-domain.com/account/billing"
        )
        self.history = Self.loadHistory(from: defaults)
        if shouldAdoptAppleTheme {
            defaults.set(ThemePreset.apple.rawValue, forKey: Keys.selectedTheme)
            defaults.set(Self.currentThemeStyleVersion, forKey: Keys.themeStyleVersion)
        }
        bindPersistence()
        bindCoordinator()
    }

    var palette: HomeThemePalette {
        selectedTheme.palette
    }

    var totalSessionCount: Int {
        history.count
    }

    var todaySessionCount: Int {
        history.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    var totalCharacterCount: Int {
        history.reduce(0) { $0 + $1.characterCount }
    }

    var totalDurationSeconds: TimeInterval {
        history.reduce(0) { $0 + $1.durationSeconds }
    }

    var totalDictationMinutes: Int {
        guard totalDurationSeconds > 0 else { return 0 }
        return Int((totalDurationSeconds / 60.0).rounded(.up))
    }

    var averageCharacterCount: Int {
        guard !history.isEmpty else { return 0 }
        return Int(Double(totalCharacterCount) / Double(history.count))
    }

    var averageDictationCharactersPerMinute: Int {
        let totalMinutes = totalDurationSeconds / 60.0
        guard totalMinutes > 0 else { return 0 }
        return Int((Double(totalCharacterCount) / totalMinutes).rounded())
    }

    var estimatedSavedMinutes: Int {
        let spokenMinutes = totalDurationSeconds / 60.0
        let typingMinutes = Double(totalCharacterCount) / Self.defaultManualTypingCharactersPerMinute
        return max(0, Int((typingMinutes - spokenMinutes).rounded()))
    }

    var weeklyUsage: [DailyUsagePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let count = history.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }.count
            let label = Self.weekdayFormatter.string(from: day)
            return DailyUsagePoint(
                label: label,
                count: count,
                isToday: calendar.isDateInToday(day)
            )
        }
    }

    var currentVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "SlashVibe v\(version) (\(build))"
    }

    var currentStatusTitle: String {
        switch coordinator.sessionState {
        case .idle:
            return "空闲"
        case .requestingPermission:
            return "请求麦克风权限"
        case .connecting:
            return "连接转写服务"
        case .recording:
            return "正在录音"
        case .finalizing:
            return "整理语音结果"
        case .failed:
            return "出现异常"
        }
    }

    var isRecordingFlowActive: Bool {
        switch coordinator.sessionState {
        case .requestingPermission, .connecting, .recording:
            return true
        case .idle, .finalizing, .failed:
            return false
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

    func clearHistory() {
        history = []
        saveHistory()
    }

    func saveSelectedSection(_ section: Section) {
        selectedSection = section
    }

    func resetModelConfiguration() {
        modelConfiguration = ModelConfiguration()
    }

    func formattedDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0m" }
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        if minutes == 0 {
            return "\(remainingSeconds)s"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    func formattedDate(_ date: Date) -> String {
        Self.historyDateFormatter.string(from: date)
    }

    private func bindPersistence() {
        $selectedSection
            .sink { [weak self] section in
                self?.defaults.set(section.rawValue, forKey: Keys.selectedSection)
            }
            .store(in: &cancellables)

        $memoryProfile
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.memoryProfile)
            }
            .store(in: &cancellables)

        $selectedTheme
            .sink { [weak self] theme in
                self?.defaults.set(theme.rawValue, forKey: Keys.selectedTheme)
            }
            .store(in: &cancellables)

        $modelConfiguration
            .dropFirst()
            .sink { [weak self] configuration in
                self?.save(configuration: configuration)
            }
            .store(in: &cancellables)

        $subscriptionPurchaseURL
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.subscriptionPurchaseURL)
            }
            .store(in: &cancellables)

        $subscriptionManageURL
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.subscriptionManageURL)
            }
            .store(in: &cancellables)
    }

    private func bindCoordinator() {
        coordinator.$lastCompletedTranscript
            .compactMap { $0 }
            .sink { [weak self] transcript in
                self?.record(transcript)
            }
            .store(in: &cancellables)
    }

    private func record(_ transcript: PublishedTranscript) {
        let normalizedText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        let signature = Self.historySignature(for: normalizedText, createdAt: transcript.createdAt)
        if let existingItem = history.first,
           Self.historySignature(for: existingItem.text, createdAt: existingItem.createdAt) == signature {
            return
        }

        let item = TranscriptHistoryItem(
            id: UUID(),
            text: normalizedText,
            createdAt: transcript.createdAt,
            characterCount: normalizedText.count,
            durationSeconds: coordinator.lastCompletedSessionDuration ?? 0,
            deliveryLabel: Self.deliveryLabel(for: coordinator.lastDeliveryOutcome)
        )

        history.insert(item, at: 0)
        if history.count > 120 {
            history = Array(history.prefix(120))
        }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Keys.history)
        }
    }

    private func save(configuration: ModelConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Keys.modelConfiguration)
        }
    }

    private static func loadSection(from defaults: UserDefaults) -> Section {
        guard
            let rawValue = defaults.string(forKey: Keys.selectedSection),
            let section = Section(rawValue: rawValue)
        else {
            return .home
        }
        return section
    }

    private static func loadTheme(from defaults: UserDefaults) -> ThemePreset {
        guard
            let rawValue = defaults.string(forKey: Keys.selectedTheme),
            let theme = ThemePreset(rawValue: rawValue)
        else {
            return .apple
        }
        return theme
    }

    private static func loadString(forKey key: String, from defaults: UserDefaults, fallback: String = "") -> String {
        defaults.string(forKey: key) ?? fallback
    }

    private static func loadModelConfiguration(from defaults: UserDefaults) -> ModelConfiguration {
        guard
            let data = defaults.data(forKey: Keys.modelConfiguration),
            let configuration = try? JSONDecoder().decode(ModelConfiguration.self, from: data)
        else {
            return ModelConfiguration()
        }
        return configuration
    }

    private static func loadHistory(from defaults: UserDefaults) -> [TranscriptHistoryItem] {
        guard
            let data = defaults.data(forKey: Keys.history),
            let items = try? JSONDecoder().decode([TranscriptHistoryItem].self, from: data)
        else {
            return []
        }
        return items
    }

    private static func historySignature(for text: String, createdAt: Date) -> String {
        "\(text)|\(createdAt.timeIntervalSince1970)"
    }

    private static func deliveryLabel(for outcome: TranscriptDeliveryOutcome?) -> String {
        switch outcome {
        case .insertedIntoFocusedApp:
            return "已直接写入"
        case .typedIntoFocusedApp:
            return "已模拟输入"
        case .pasteShortcutSent:
            return "已触发粘贴"
        case .copiedToClipboard:
            return "已复制剪贴板"
        case .publishedOnly, .none:
            return "已完成转写"
        }
    }

    private enum Keys {
        static let selectedSection = "home.selectedSection"
        static let memoryProfile = "home.memoryProfile"
        static let selectedTheme = "home.selectedTheme"
        static let themeStyleVersion = "home.themeStyleVersion"
        static let modelConfiguration = "home.modelConfiguration"
        static let history = "home.history"
        static let subscriptionPurchaseURL = "home.subscriptionPurchaseURL"
        static let subscriptionManageURL = "home.subscriptionManageURL"
    }

    private static let defaultManualTypingCharactersPerMinute: Double = 30

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter
    }()

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
