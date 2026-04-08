import Foundation

enum MemoryConstellationClusterKind: String, CaseIterable, Identifiable {
    case vocabulary
    case style
    case scenes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary:
            return "Vocabulary"
        case .style:
            return "Style"
        case .scenes:
            return "Scenes"
        }
    }
}

enum MemoryConstellationClusterFilter: String, CaseIterable, Identifiable {
    case all
    case vocabulary
    case style
    case scenes

    var id: String { rawValue }
}

enum MemoryConstellationViewMode: String, CaseIterable, Identifiable {
    case clusterMap = "Cluster Map"
    case bridgeStories = "Bridge Stories"
    case timelineReplay = "Timeline Replay"

    var id: String { rawValue }
}

enum MemoryConstellationDisplayMode: String, CaseIterable {
    case full
    case privacySafe
    case hidden
}

enum MemoryConstellationFocus: Equatable {
    case overview
    case cluster(MemoryConstellationClusterKind)
    case bridge(UUID)
    case star(UUID)
}

struct MemoryConstellationSnapshot: Equatable {
    let title: String
    let subtitle: String
    let statusPills: [String]
    let clusters: [MemoryConstellationCluster]
    let highlightedBridges: [MemoryConstellationBridge]
    let guidanceCards: [MemoryConstellationGuidanceCard]
    let relationshipCards: [MemoryConstellationRelationshipCard]
    let timeline: MemoryConstellationTimeline
    let accessibilitySummary: String

    static let hidden = MemoryConstellationSnapshot(
        title: "My Universe",
        subtitle: "Memory visibility is hidden.",
        statusPills: ["Hidden"],
        clusters: [],
        highlightedBridges: [],
        guidanceCards: [],
        relationshipCards: [],
        timeline: .empty,
        accessibilitySummary: "Memory visibility is hidden. No constellation is shown."
    )
}

struct MemoryConstellationCluster: Identifiable, Equatable {
    let id: MemoryConstellationClusterKind
    let kind: MemoryConstellationClusterKind
    let stars: [MemoryConstellationStar]
    let itemCount: Int
    let emphasis: Double
    let isDimmed: Bool

    var title: String { kind.title }
}

struct MemoryConstellationStar: Identifiable, Equatable {
    let id: UUID
    let label: String
    let strength: Double
}

struct MemoryConstellationBridge: Identifiable, Equatable {
    let id: UUID
    let from: MemoryConstellationClusterKind
    let to: MemoryConstellationClusterKind
    let strength: Double
    let label: String
    let isFocused: Bool
}

struct MemoryConstellationGuidanceCard: Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
}

struct MemoryConstellationRelationshipCard: Identifiable, Equatable {
    let id: UUID
    let bridgeID: UUID?
    let title: String
    let body: String
}

struct MemoryConstellationTimeline: Equatable {
    let windows: [MemoryConstellationTimelineWindow]

    static let empty = MemoryConstellationTimeline(windows: [])
}

struct MemoryConstellationTimelineWindow: Identifiable, Equatable {
    let id: String
    let title: String
    let memoryCount: Int
}
