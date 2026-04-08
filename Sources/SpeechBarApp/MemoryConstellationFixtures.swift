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
                fingerprint: "live review",
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
                fingerprint: "Sparse vocabulary",
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
                fingerprint: "Confidential client name",
                identityHash: "vocabulary|client-name",
                confidence: 0.90,
                updatedAt: now.addingTimeInterval(-6),
                sourceEventIDs: [uuid("ccccccc1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("22222222-2222-4222-8222-222222222222"),
                type: .style,
                key: "style:private-tone",
                fingerprint: "Private tone",
                identityHash: "style|private-tone",
                confidence: 0.83,
                updatedAt: now.addingTimeInterval(-7),
                sourceEventIDs: [uuid("ccccccc1-0000-4000-8000-000000000001"), uuid("ccccccc2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("33333333-3333-4333-8333-333333333333"),
                type: .scene,
                key: "scene:deal",
                fingerprint: "Private deal note",
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
                fingerprint: "Core term 1",
                identityHash: "vocabulary|core-1",
                confidence: 0.94,
                updatedAt: now.addingTimeInterval(-2),
                sourceEventIDs: [uuid("ddddddd1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("20202020-2020-4020-8020-202020202020"),
                type: .vocabulary,
                key: "vocabulary:core-2",
                fingerprint: "Core term 2",
                identityHash: "vocabulary|core-2",
                confidence: 0.91,
                updatedAt: now.addingTimeInterval(-3),
                sourceEventIDs: [uuid("ddddddd2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("30303030-3030-4030-8030-303030303030"),
                type: .vocabulary,
                key: "vocabulary:core-3",
                fingerprint: "Core term 3",
                identityHash: "vocabulary|core-3",
                confidence: 0.88,
                updatedAt: now.addingTimeInterval(-4),
                sourceEventIDs: [uuid("ddddddd3-0000-4000-8000-000000000003")]
            ),
            makeMemory(
                id: uuid("40404040-4040-4040-8040-404040404040"),
                type: .vocabulary,
                key: "vocabulary:core-4",
                fingerprint: "Core term 4",
                identityHash: "vocabulary|core-4",
                confidence: 0.86,
                updatedAt: now.addingTimeInterval(-5),
                sourceEventIDs: [uuid("ddddddd4-0000-4000-8000-000000000004")]
            ),
            makeMemory(
                id: uuid("50505050-5050-4050-8050-505050505050"),
                type: .style,
                key: "style:dominant",
                fingerprint: "Dominant tone",
                identityHash: "style|dominant",
                confidence: 0.84,
                updatedAt: now.addingTimeInterval(-6),
                sourceEventIDs: [uuid("ddddddd1-0000-4000-8000-000000000001"), uuid("ddddddd5-0000-4000-8000-000000000005")]
            ),
            makeMemory(
                id: uuid("60606060-6060-4060-8060-606060606060"),
                type: .scene,
                key: "scene:dominant",
                fingerprint: "Dominant scene",
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
                fingerprint: "Isolated vocab",
                identityHash: "vocabulary|isolated",
                confidence: 0.67,
                updatedAt: now.addingTimeInterval(-10),
                sourceEventIDs: [uuid("eeeeeee1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("22222222-2222-4222-8222-222222222222"),
                type: .style,
                key: "style:isolated",
                fingerprint: "Isolated style",
                identityHash: "style|isolated",
                confidence: 0.66,
                updatedAt: now.addingTimeInterval(-11),
                sourceEventIDs: [uuid("eeeeeee2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("33333333-3333-4333-8333-333333333333"),
                type: .scene,
                key: "scene:isolated",
                fingerprint: "Isolated scene",
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
        ("OpenAI", "openai", "Brevity first", "brevity", "Weekly review", "review"),
        ("Roadmap", "roadmap", "Decision first", "decision-first", "Launch checklist", "launch-checklist"),
        ("Prompt engineering", "prompt-engineering", "Clear next steps", "clear-next-steps", "Hackathon demo", "hackathon-demo"),
        ("Retrieval", "retrieval", "Concrete examples", "concrete-examples", "Customer follow-up", "customer-follow-up"),
        ("Transcript cleanup", "transcript-cleanup", "No fluff", "no-fluff", "QA triage", "qa-triage"),
        ("Memory recall", "memory-recall", "Calm confidence", "calm-confidence", "Investor sync", "investor-sync"),
        ("Evaluation harness", "evaluation-harness", "Structured bullets", "structured-bullets", "Product spec", "product-spec"),
        ("Model routing", "model-routing", "Simple Chinese", "simple-chinese", "Morning standup", "morning-standup"),
        ("Latency budget", "latency-budget", "Action first", "action-first", "Bug bash", "bug-bash"),
        ("Personal notes", "personal-notes", "Warm but direct", "warm-but-direct", "Founder update", "founder-update")
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
