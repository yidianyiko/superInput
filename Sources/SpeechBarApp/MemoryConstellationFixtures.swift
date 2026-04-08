import Foundation
import MemoryDomain

enum MemoryScenario: String, CaseIterable, Sendable {
    case live
    case `default`
    case sparse
    case privacy
    case dominant
    case noBridge
}

enum MemoryConstellationFixtures {
    static func catalogProvider(for scenario: MemoryScenario, now: Date) -> any MemoryCatalogProviding {
        StaticMemoryCatalogProvider(memories: memories(for: scenario, now: now))
    }

    static func memories(for scenario: MemoryScenario, now: Date) -> [MemoryItem] {
        switch scenario {
        case .live:
            return liveMemories(now: now)
        case .default:
            return defaultMemories(now: now)
        case .sparse:
            return sparseMemories(now: now)
        case .privacy:
            return privacyMemories(now: now)
        case .dominant:
            return dominantMemories(now: now)
        case .noBridge:
            return noBridgeMemories(now: now)
        }
    }

    private static func liveMemories(now: Date) -> [MemoryItem] {
        defaultMemories(now: now) + [
            makeMemory(
                id: uuid("66666666-6666-4666-8666-666666666666"),
                type: .scene,
                key: "scene:live-review",
                fingerprint: "实时复盘",
                identityHash: "scene|live-review",
                confidence: 0.70,
                updatedAt: now.addingTimeInterval(-7),
                sourceEventIDs: [uuid("44444444-4444-4444-8444-444444444444")]
            )
        ]
    }

    static func defaultMemories(now: Date) -> [MemoryItem] {
        demoThreads.enumerated().flatMap { index, thread in
            let eventID = demoEventID(index + 1)
            let threadBaseOffset = TimeInterval(index * 540)

            return [
                makeMemory(
                    id: demoMemoryID(index * 3 + 1),
                    type: .vocabulary,
                    key: "vocabulary:\(thread.vocabularySlug)",
                    fingerprint: thread.vocabulary,
                    identityHash: "vocabulary|\(thread.vocabularySlug)",
                    confidence: max(0.72, 0.92 - (Double(index) * 0.018)),
                    updatedAt: now.addingTimeInterval(-(threadBaseOffset + 5)),
                    sourceEventIDs: [eventID]
                ),
                makeMemory(
                    id: demoMemoryID(index * 3 + 2),
                    type: .style,
                    key: "style:\(thread.styleSlug)",
                    fingerprint: thread.style,
                    identityHash: "style|\(thread.styleSlug)",
                    confidence: max(0.70, 0.88 - (Double(index) * 0.017)),
                    updatedAt: now.addingTimeInterval(-(threadBaseOffset + 9)),
                    sourceEventIDs: [eventID]
                ),
                makeMemory(
                    id: demoMemoryID(index * 3 + 3),
                    type: .scene,
                    key: "scene:\(thread.sceneSlug)",
                    fingerprint: thread.scene,
                    identityHash: "scene|\(thread.sceneSlug)",
                    confidence: max(0.68, 0.84 - (Double(index) * 0.016)),
                    updatedAt: now.addingTimeInterval(-(threadBaseOffset + 16)),
                    sourceEventIDs: [eventID]
                )
            ]
        }
    }

    static func sparseMemories(now: Date) -> [MemoryItem] {
        [
            makeMemory(
                id: uuid("11111111-1111-4111-8111-111111111111"),
                type: .vocabulary,
                key: "vocabulary:single",
                fingerprint: "稀疏词条",
                identityHash: "vocabulary|single",
                confidence: 0.61,
                updatedAt: now.addingTimeInterval(-10),
                sourceEventIDs: [uuid("bbbbbbb1-0000-4000-8000-000000000001")]
            )
        ]
    }

    static func privacyMemories(now: Date) -> [MemoryItem] {
        [
            makeMemory(
                id: uuid("11111111-1111-4111-8111-111111111111"),
                type: .vocabulary,
                key: "vocabulary:client-name",
                fingerprint: "保密客户名称",
                identityHash: "vocabulary|client-name",
                confidence: 0.90,
                updatedAt: now.addingTimeInterval(-6),
                sourceEventIDs: [uuid("ccccccc1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("22222222-2222-4222-8222-222222222222"),
                type: .style,
                key: "style:private-tone",
                fingerprint: "私密语气",
                identityHash: "style|private-tone",
                confidence: 0.83,
                updatedAt: now.addingTimeInterval(-7),
                sourceEventIDs: [uuid("ccccccc1-0000-4000-8000-000000000001"), uuid("ccccccc2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("33333333-3333-4333-8333-333333333333"),
                type: .scene,
                key: "scene:deal",
                fingerprint: "私密交易记录",
                identityHash: "scene|deal",
                confidence: 0.75,
                updatedAt: now.addingTimeInterval(-9),
                sourceEventIDs: [uuid("ccccccc2-0000-4000-8000-000000000002")]
            )
        ]
    }

    static func dominantMemories(now: Date) -> [MemoryItem] {
        [
            makeMemory(
                id: uuid("10101010-1010-4010-8010-101010101010"),
                type: .vocabulary,
                key: "vocabulary:core-1",
                fingerprint: "核心术语 1",
                identityHash: "vocabulary|core-1",
                confidence: 0.94,
                updatedAt: now.addingTimeInterval(-2),
                sourceEventIDs: [uuid("ddddddd1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("20202020-2020-4020-8020-202020202020"),
                type: .vocabulary,
                key: "vocabulary:core-2",
                fingerprint: "核心术语 2",
                identityHash: "vocabulary|core-2",
                confidence: 0.91,
                updatedAt: now.addingTimeInterval(-3),
                sourceEventIDs: [uuid("ddddddd2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("30303030-3030-4030-8030-303030303030"),
                type: .vocabulary,
                key: "vocabulary:core-3",
                fingerprint: "核心术语 3",
                identityHash: "vocabulary|core-3",
                confidence: 0.88,
                updatedAt: now.addingTimeInterval(-4),
                sourceEventIDs: [uuid("ddddddd3-0000-4000-8000-000000000003")]
            ),
            makeMemory(
                id: uuid("40404040-4040-4040-8040-404040404040"),
                type: .vocabulary,
                key: "vocabulary:core-4",
                fingerprint: "核心术语 4",
                identityHash: "vocabulary|core-4",
                confidence: 0.86,
                updatedAt: now.addingTimeInterval(-5),
                sourceEventIDs: [uuid("ddddddd4-0000-4000-8000-000000000004")]
            ),
            makeMemory(
                id: uuid("50505050-5050-4050-8050-505050505050"),
                type: .style,
                key: "style:dominant",
                fingerprint: "主导语气",
                identityHash: "style|dominant",
                confidence: 0.84,
                updatedAt: now.addingTimeInterval(-6),
                sourceEventIDs: [uuid("ddddddd1-0000-4000-8000-000000000001"), uuid("ddddddd5-0000-4000-8000-000000000005")]
            ),
            makeMemory(
                id: uuid("60606060-6060-4060-8060-606060606060"),
                type: .scene,
                key: "scene:dominant",
                fingerprint: "主导场景",
                identityHash: "scene|dominant",
                confidence: 0.74,
                updatedAt: now.addingTimeInterval(-7),
                sourceEventIDs: [uuid("ddddddd5-0000-4000-8000-000000000005")]
            )
        ]
    }

    static func noBridgeMemories(now: Date) -> [MemoryItem] {
        [
            makeMemory(
                id: uuid("11111111-1111-4111-8111-111111111111"),
                type: .vocabulary,
                key: "vocabulary:isolated",
                fingerprint: "孤立词条",
                identityHash: "vocabulary|isolated",
                confidence: 0.67,
                updatedAt: now.addingTimeInterval(-10),
                sourceEventIDs: [uuid("eeeeeee1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("22222222-2222-4222-8222-222222222222"),
                type: .style,
                key: "style:isolated",
                fingerprint: "孤立风格",
                identityHash: "style|isolated",
                confidence: 0.66,
                updatedAt: now.addingTimeInterval(-11),
                sourceEventIDs: [uuid("eeeeeee2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("33333333-3333-4333-8333-333333333333"),
                type: .scene,
                key: "scene:isolated",
                fingerprint: "孤立场景",
                identityHash: "scene|isolated",
                confidence: 0.65,
                updatedAt: now.addingTimeInterval(-12),
                sourceEventIDs: [uuid("eeeeeee3-0000-4000-8000-000000000003")]
            )
        ]
    }

    private static func makeMemory(
        id: UUID,
        type: MemoryType,
        key: String,
        fingerprint: String,
        identityHash: String,
        confidence: Double,
        updatedAt: Date,
        sourceEventIDs: [UUID]
    ) -> MemoryItem {
        MemoryItem(
            id: id,
            type: type,
            key: key,
            valuePayload: Data(fingerprint.utf8),
            valueFingerprint: fingerprint,
            identityHash: identityHash,
            scope: .app("com.slashvibe.snapshot"),
            confidence: confidence,
            status: .active,
            createdAt: updatedAt.addingTimeInterval(-10),
            updatedAt: updatedAt,
            lastConfirmedAt: updatedAt.addingTimeInterval(-5),
            sourceEventIDs: sourceEventIDs
        )
    }

    private static func uuid(_ string: String) -> UUID {
        UUID(uuidString: string)!
    }

    private static func demoMemoryID(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "%08d-0000-4000-8000-%012d", seed, seed))!
    }

    private static func demoEventID(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "%08d-0000-4000-9000-%012d", seed, seed))!
    }

    private static let demoThreads: [(
        vocabulary: String,
        vocabularySlug: String,
        style: String,
        styleSlug: String,
        scene: String,
        sceneSlug: String
    )] = [
        ("OpenAI", "openai", "简洁优先", "brevity", "周会复盘", "review"),
        ("路线图", "roadmap", "结论先行", "decision-first", "上线清单", "launch-checklist"),
        ("提示词工程", "prompt-engineering", "下一步明确", "clear-next-steps", "黑客松演示", "hackathon-demo"),
        ("检索增强", "retrieval", "多给具体例子", "concrete-examples", "客户跟进", "customer-follow-up"),
        ("转写清理", "transcript-cleanup", "不要废话", "no-fluff", "QA 分诊", "qa-triage"),
        ("记忆召回", "memory-recall", "平静自信", "calm-confidence", "投资人同步", "investor-sync"),
        ("评测体系", "evaluation-harness", "要点分条", "structured-bullets", "产品规格说明", "product-spec"),
        ("模型路由", "model-routing", "中文尽量简单", "simple-chinese", "晨会同步", "morning-standup"),
        ("时延预算", "latency-budget", "行动优先", "action-first", "缺陷冲刺", "bug-bash"),
        ("个人备忘", "personal-notes", "温和但直接", "warm-but-direct", "创始人更新", "founder-update")
    ]
}

struct StaticMemoryCatalogProvider: MemoryCatalogProviding, Sendable {
    let memories: [MemoryItem]

    func listMemories(matching query: MemoryCenterQuery) async throws -> [MemoryItem] {
        var filtered = memories.filter { memory in
            query.statuses.contains(memory.status) && query.types.contains(memory.type)
        }

        if let limit = query.limit {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }
}
