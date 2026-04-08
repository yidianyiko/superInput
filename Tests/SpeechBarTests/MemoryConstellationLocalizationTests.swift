import Foundation
import Testing
@testable import SpeechBarApp

@Suite("MemoryConstellationLocalization")
struct MemoryConstellationLocalizationTests {
    @Test
    func primaryLabelsPreferChineseCopy() {
        #expect(MemoryConstellationClusterKind.vocabulary.title == "词汇")
        #expect(MemoryConstellationClusterKind.style.title == "风格")
        #expect(MemoryConstellationClusterKind.scenes.title == "场景")
        #expect(MemoryConstellationViewMode.clusterMap.rawValue == "星团总览")
        #expect(MemoryConstellationViewMode.bridgeStories.rawValue == "关系解读")
        #expect(MemoryConstellationViewMode.timelineReplay.rawValue == "时间回放")
        #expect(MemoryConstellationTheme.displayModeLabel(.full) == "完整显示")
        #expect(MemoryConstellationTheme.displayModeLabel(.privacySafe) == "隐私保护")
        #expect(MemoryConstellationTheme.displayModeLabel(.hidden) == "隐藏")
        #expect(MemoryConstellationSnapshot.hidden.title == "我的记忆宇宙")
        #expect(MemoryConstellationSnapshot.hidden.subtitle == "记忆可见性已隐藏。")
    }

    @Test
    func demoMemoriesPreferChineseDisplayTerms() {
        let memories = MemoryConstellationFixtures.defaultMemories(now: Date(timeIntervalSince1970: 100))

        #expect(memories.contains(where: { $0.valueFingerprint == "路线图" }))
        #expect(memories.contains(where: { $0.valueFingerprint == "结论先行" }))
        #expect(memories.contains(where: { $0.valueFingerprint == "周会复盘" }))
    }
}
