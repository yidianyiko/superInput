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
        [
            makeMemory(
                id: uuid("11111111-1111-4111-8111-111111111111"),
                type: .vocabulary,
                key: "vocabulary:openai",
                fingerprint: "OpenAI",
                identityHash: "vocabulary|openai",
                confidence: 0.92,
                updatedAt: now.addingTimeInterval(-5),
                sourceEventIDs: [uuid("aaaaaaa1-0000-4000-8000-000000000001")]
            ),
            makeMemory(
                id: uuid("22222222-2222-4222-8222-222222222222"),
                type: .style,
                key: "style:brevity",
                fingerprint: "Brevity first",
                identityHash: "style|brevity",
                confidence: 0.87,
                updatedAt: now.addingTimeInterval(-4),
                sourceEventIDs: [uuid("aaaaaaa1-0000-4000-8000-000000000001"), uuid("aaaaaaa2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("33333333-3333-4333-8333-333333333333"),
                type: .scene,
                key: "scene:review",
                fingerprint: "Weekly review",
                identityHash: "scene|review",
                confidence: 0.78,
                updatedAt: now.addingTimeInterval(-8),
                sourceEventIDs: [uuid("aaaaaaa2-0000-4000-8000-000000000002")]
            ),
            makeMemory(
                id: uuid("44444444-4444-4444-8444-444444444444"),
                type: .vocabulary,
                key: "vocabulary:roadmap",
                fingerprint: "Roadmap",
                identityHash: "vocabulary|roadmap",
                confidence: 0.80,
                updatedAt: now.addingTimeInterval(-11),
                sourceEventIDs: [uuid("aaaaaaa3-0000-4000-8000-000000000003")]
            )
        ]
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
