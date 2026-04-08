import Foundation
import MemoryDomain

struct MemoryConstellationBuilder {
    let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    func build(
        memories: [MemoryItem],
        filter: MemoryConstellationClusterFilter,
        focus: MemoryConstellationFocus,
        viewMode: MemoryConstellationViewMode,
        displayMode: MemoryConstellationDisplayMode
    ) -> MemoryConstellationSnapshot {
        guard displayMode != .hidden else {
            return .hidden
        }

        let active = memories.filter { $0.status == .active }
        let filtered = active.filter { include($0, for: filter) }
        let grouped = Dictionary(grouping: filtered, by: clusterKind(for:))
        let clusters = MemoryConstellationClusterKind.allCases.compactMap { kind -> MemoryConstellationCluster? in
            let items = grouped[kind, default: []]
            guard !items.isEmpty else {
                return nil
            }
            return makeCluster(kind: kind, items: items, displayMode: displayMode, focus: focus)
        }

        let bridges = buildBridges(from: filtered, displayMode: displayMode, focus: focus)
        let relationshipCards = buildRelationshipCards(bridges: bridges, displayMode: displayMode)
        let guidanceCards = buildGuidanceCards(bridges: bridges)
        let subtitle = switch viewMode {
        case .clusterMap:
            "Cluster mass first, then the bridge that matters now."
        case .bridgeStories:
            "Read the strongest cross-theme relationships first."
        case .timelineReplay:
            "Replay how memory density changes across recent windows."
        }

        return MemoryConstellationSnapshot(
            title: "My Universe",
            subtitle: subtitle,
            statusPills: [
                "30d local retention",
                "\(active.count) memories",
                displayMode == .privacySafe ? "Private View" : "Memory On"
            ],
            clusters: clusters,
            highlightedBridges: Array(bridges.prefix(2)),
            guidanceCards: guidanceCards,
            relationshipCards: relationshipCards,
            timeline: buildTimeline(from: filtered),
            accessibilitySummary: buildAccessibilitySummary(clusters: clusters, bridges: bridges, displayMode: displayMode),
            accessibilityHint: buildAccessibilityHint(displayMode: displayMode)
        )
    }

    private func clusterKind(for memory: MemoryItem) -> MemoryConstellationClusterKind {
        switch memory.type {
        case .vocabulary, .correction:
            return .vocabulary
        case .style:
            return .style
        case .scene:
            return .scenes
        }
    }

    private func include(_ memory: MemoryItem, for filter: MemoryConstellationClusterFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .vocabulary:
            return clusterKind(for: memory) == .vocabulary
        case .style:
            return clusterKind(for: memory) == .style
        case .scenes:
            return clusterKind(for: memory) == .scenes
        }
    }

    private func buildBridges(
        from memories: [MemoryItem],
        displayMode: MemoryConstellationDisplayMode,
        focus: MemoryConstellationFocus
    ) -> [MemoryConstellationBridge] {
        var weights: [String: Double] = [:]
        let byEvent = Dictionary(
            grouping: memories.flatMap { memory in
                memory.sourceEventIDs.map { ($0, memory) }
            },
            by: { $0.0 }
        )

        for entries in byEvent.values {
            let uniqueMemories = entries.map(\.1)
            for lhs in uniqueMemories {
                for rhs in uniqueMemories where clusterKind(for: lhs) != clusterKind(for: rhs) {
                    let pair = sortedPair(clusterKind(for: lhs), clusterKind(for: rhs))
                    let pairKey = bridgeKey(for: pair)
                    let recency = max(lhs.updatedAt, rhs.updatedAt).timeIntervalSince1970 / 1_000
                    let score = lhs.confidence + rhs.confidence + recency
                    weights[pairKey] = max(weights[pairKey] ?? 0, score)
                }
            }
        }

        return weights
            .sorted { $0.value > $1.value }
            .compactMap { pair in
                let clusters = pair.key.split(separator: "|").compactMap {
                    MemoryConstellationClusterKind(rawValue: String($0))
                }
                guard clusters.count == 2 else {
                    return nil
                }

                let bridgeID = bridgeID(for: pair.key)
                let isFocused: Bool
                if case .bridge(let focusedID) = focus {
                    isFocused = focusedID == bridgeID
                } else {
                    isFocused = false
                }

                return MemoryConstellationBridge(
                    id: bridgeID,
                    from: clusters[0],
                    to: clusters[1],
                    strength: pair.value,
                    label: displayMode == .privacySafe ? "Protected relationship" : "Today's bridge",
                    isFocused: isFocused
                )
            }
    }

    private func makeCluster(
        kind: MemoryConstellationClusterKind,
        items: [MemoryItem],
        displayMode: MemoryConstellationDisplayMode,
        focus: MemoryConstellationFocus
    ) -> MemoryConstellationCluster {
        let stars = items
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(8)
            .map { memory in
                MemoryConstellationStar(
                    id: memory.id,
                    label: displayMode == .privacySafe ? "Protected memory" : memory.valueFingerprint,
                    strength: memory.confidence
                )
            }

        let isDimmed: Bool
        switch focus {
        case .overview:
            isDimmed = false
        case .cluster(let selected):
            isDimmed = selected != kind
        case .bridge, .star:
            isDimmed = false
        }

        return MemoryConstellationCluster(
            id: kind,
            kind: kind,
            stars: Array(stars),
            itemCount: items.count,
            emphasis: min(1.0, Double(items.count) / 6.0),
            isDimmed: isDimmed
        )
    }

    private func buildRelationshipCards(
        bridges: [MemoryConstellationBridge],
        displayMode: MemoryConstellationDisplayMode
    ) -> [MemoryConstellationRelationshipCard] {
        guard !bridges.isEmpty else {
            return [
                MemoryConstellationRelationshipCard(
                    id: UUID(),
                    bridgeID: nil,
                    title: "Emerging Themes",
                    body: displayMode == .privacySafe
                        ? "Protected themes are forming, but no strong bridge is visible yet."
                        : "Themes are present, but no single bridge stands out yet.",
                    accessibilityLabel: displayMode == .privacySafe
                        ? "Emerging Themes. Protected themes are forming, but no strong bridge is visible yet."
                        : "Emerging Themes. Themes are present, but no single bridge stands out yet.",
                    accessibilityHint: "Select to return to the constellation overview."
                )
            ]
        }

        return bridges.prefix(3).enumerated().map { index, bridge in
            let orderedThemes = orderedThemeTitles(for: bridge)
            let title: String
            switch index {
            case 0:
                title = "Strongest Now"
            case 1:
                title = "Rising Bridge"
            default:
                title = "Subtle Link"
            }

            let body: String
            if displayMode == .privacySafe {
                body = "Protected relationship connecting \(orderedThemes.0) and \(orderedThemes.1)."
            } else {
                body = "\(orderedThemes.0) is currently reinforcing \(orderedThemes.1)."
            }

            let accessibilityLabel = "\(title). \(body)"
            let accessibilityHint = bridge.isFocused
                ? "Select to return to the constellation overview."
                : "Select to focus this bridge on the canvas."

            return MemoryConstellationRelationshipCard(
                id: UUID(),
                bridgeID: bridge.id,
                title: title,
                body: body,
                accessibilityLabel: accessibilityLabel,
                accessibilityHint: accessibilityHint
            )
        }
    }

    private func buildGuidanceCards(bridges: [MemoryConstellationBridge]) -> [MemoryConstellationGuidanceCard] {
        if let bridge = bridges.first {
            return [
                MemoryConstellationGuidanceCard(
                    id: UUID(),
                    title: "Today's Bridge",
                    body: "\(bridge.from.title) is the clearest cross-theme relationship right now."
                ),
                MemoryConstellationGuidanceCard(
                    id: UUID(),
                    title: "Reading Cue",
                    body: "Hover a cluster before drilling into individual stars."
                )
            ]
        }

        return [
            MemoryConstellationGuidanceCard(
                id: UUID(),
                title: "Emerging Themes",
                body: "Cluster mass is visible, but the strongest bridge is still forming."
            ),
            MemoryConstellationGuidanceCard(
                id: UUID(),
                title: "Reading Cue",
                body: "Start with the largest cluster and then inspect smaller satellites."
            )
        ]
    }

    private func buildTimeline(from memories: [MemoryItem]) -> MemoryConstellationTimeline {
        let nowDate = now()
        let windows = [
            ("24h", "Today", memories.filter { nowDate.timeIntervalSince($0.updatedAt) <= 24 * 60 * 60 }.count),
            ("7d", "7 Days", memories.filter { nowDate.timeIntervalSince($0.updatedAt) <= 7 * 24 * 60 * 60 }.count),
            ("30d", "30 Days", memories.count)
        ]

        return MemoryConstellationTimeline(
            windows: windows.map { window in
                MemoryConstellationTimelineWindow(
                    id: window.0,
                    title: window.1,
                    memoryCount: window.2
                )
            }
        )
    }

    private func buildAccessibilitySummary(
        clusters: [MemoryConstellationCluster],
        bridges: [MemoryConstellationBridge],
        displayMode: MemoryConstellationDisplayMode
    ) -> String {
        let themesSummary = themeSummary(for: clusters)

        switch displayMode {
        case .hidden:
            return "Memory visibility is hidden. No constellation is shown."
        case .privacySafe:
            let prefix = "Protected memory constellation."
            if let bridge = bridges.first {
                let orderedThemes = orderedThemeTitles(for: bridge)
                return [prefix, themesSummary, "Strongest protected bridge connects \(orderedThemes.0) and \(orderedThemes.1)."]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            if let themesSummary {
                return "\(prefix) \(themesSummary) No strong protected bridge is active today."
            }
            return "\(prefix) No themes are visible yet."
        case .full:
            if let bridge = bridges.first {
                let orderedThemes = orderedThemeTitles(for: bridge)
                return [
                    "Memory constellation ready.",
                    themesSummary,
                    "Strongest bridge connects \(orderedThemes.0) and \(orderedThemes.1)."
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            if let themesSummary {
                return "Memory constellation ready. \(themesSummary) No strong bridge is active today."
            }
            return "Memory constellation ready. No themes are visible yet."
        }
    }

    private func buildAccessibilityHint(displayMode: MemoryConstellationDisplayMode) -> String {
        switch displayMode {
        case .hidden:
            return "Enable memory visibility to restore constellation content."
        case .privacySafe:
            return "Use the cluster and relationship controls to explore themes without exposing protected memory terms."
        case .full:
            return "Use the cluster and relationship controls to explore the main themes and strongest bridges."
        }
    }

    private func themeSummary(for clusters: [MemoryConstellationCluster]) -> String? {
        let titles = clusters
            .sorted { clusterOrderIndex(for: $0.kind) < clusterOrderIndex(for: $1.kind) }
            .map(\.title)
        guard titles.isEmpty == false else {
            return nil
        }
        return "Main themes include \(naturalLanguageList(titles))."
    }

    private func orderedThemeTitles(for bridge: MemoryConstellationBridge) -> (String, String) {
        if clusterOrderIndex(for: bridge.from) <= clusterOrderIndex(for: bridge.to) {
            return (bridge.from.title, bridge.to.title)
        }
        return (bridge.to.title, bridge.from.title)
    }

    private func clusterOrderIndex(for kind: MemoryConstellationClusterKind) -> Int {
        MemoryConstellationClusterKind.allCases.firstIndex(of: kind) ?? .max
    }

    private func naturalLanguageList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) and \(items[1])"
        default:
            let prefix = items.dropLast().joined(separator: ", ")
            return "\(prefix), and \(items.last!)"
        }
    }

    private func sortedPair(
        _ lhs: MemoryConstellationClusterKind,
        _ rhs: MemoryConstellationClusterKind
    ) -> (MemoryConstellationClusterKind, MemoryConstellationClusterKind) {
        if lhs.rawValue <= rhs.rawValue {
            return (lhs, rhs)
        }
        return (rhs, lhs)
    }

    private func bridgeKey(for pair: (MemoryConstellationClusterKind, MemoryConstellationClusterKind)) -> String {
        "\(pair.0.rawValue)|\(pair.1.rawValue)"
    }

    private func bridgeID(for key: String) -> UUID {
        var bytes = Array(key.utf8.prefix(16))
        if bytes.count < 16 {
            bytes.append(contentsOf: repeatElement(0, count: 16 - bytes.count))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}
