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
            "先看星团密度，再看此刻最值得关注的连接。"
        case .bridgeStories:
            "优先阅读跨主题之间最强的关系。"
        case .timelineReplay:
            "回放最近时间窗口里的记忆密度变化。"
        }

        return MemoryConstellationSnapshot(
            title: "我的记忆宇宙",
            subtitle: subtitle,
            statusPills: [
                "本地保留 30 天",
                "\(active.count) 条记忆",
                displayMode == .privacySafe ? "隐私视图" : "记忆已开启"
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
                    label: displayMode == .privacySafe ? "受保护连接" : "今日连接",
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
            .prefix(10)
            .map { memory in
                MemoryConstellationStar(
                    id: memory.id,
                    label: displayMode == .privacySafe ? "受保护记忆" : memory.valueFingerprint,
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
                    title: "正在形成的主题",
                    body: displayMode == .privacySafe
                        ? "受保护的主题正在形成，但暂时还没有明显的强连接。"
                        : "主题轮廓已经出现，但还没有哪条连接特别突出。",
                    accessibilityLabel: displayMode == .privacySafe
                        ? "正在形成的主题。受保护的主题正在形成，但暂时还没有明显的强连接。"
                        : "正在形成的主题。主题轮廓已经出现，但还没有哪条连接特别突出。",
                    accessibilityHint: "点按可返回星图总览。"
                )
            ]
        }

        return bridges.prefix(3).enumerated().map { index, bridge in
            let orderedThemes = orderedThemeTitles(for: bridge)
            let title: String
            switch index {
            case 0:
                title = "当前最强"
            case 1:
                title = "正在升温"
            default:
                title = "隐约关联"
            }

            let body: String
            if displayMode == .privacySafe {
                body = "一条受保护的连接正在串联\(orderedThemes.0)与\(orderedThemes.1)。"
            } else {
                body = "\(orderedThemes.0) 当前正在强化 \(orderedThemes.1)。"
            }

            let accessibilityLabel = "\(title). \(body)"
            let accessibilityHint = bridge.isFocused
                ? "点按可返回星图总览。"
                : "点按可在画布中聚焦这条连接。"

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
                    title: "今日连接",
                    body: "\(bridge.from.title) 是当前最清晰的跨主题关联。"
                ),
                MemoryConstellationGuidanceCard(
                    id: UUID(),
                    title: "阅读提示",
                    body: "先悬停星团，再继续查看具体星点。"
                )
            ]
        }

        return [
            MemoryConstellationGuidanceCard(
                id: UUID(),
                title: "正在形成的主题",
                body: "星团轮廓已经出现，但最强连接仍在形成。"
            ),
            MemoryConstellationGuidanceCard(
                id: UUID(),
                title: "阅读提示",
                body: "先看最大的星团，再观察较小的卫星点。"
            )
        ]
    }

    private func buildTimeline(from memories: [MemoryItem]) -> MemoryConstellationTimeline {
        let nowDate = now()
        let windows = [
            ("24h", "今天", memories.filter { nowDate.timeIntervalSince($0.updatedAt) <= 24 * 60 * 60 }.count),
            ("7d", "近 7 天", memories.filter { nowDate.timeIntervalSince($0.updatedAt) <= 7 * 24 * 60 * 60 }.count),
            ("30d", "近 30 天", memories.count)
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
            return "记忆可见性已隐藏。当前不显示星图。"
        case .privacySafe:
            let prefix = "受保护的记忆星图。"
            if let bridge = bridges.first {
                let orderedThemes = orderedThemeTitles(for: bridge)
                return [prefix, themesSummary, "最强受保护连接出现在\(orderedThemes.0)与\(orderedThemes.1)之间。"]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            if let themesSummary {
                return "\(prefix) \(themesSummary) 今天还没有明显的受保护强连接。"
            }
            return "\(prefix) 目前还没有可见主题。"
        case .full:
            if let bridge = bridges.first {
                let orderedThemes = orderedThemeTitles(for: bridge)
                return [
                    "记忆星图已就绪。",
                    themesSummary,
                    "最强连接出现在\(orderedThemes.0)与\(orderedThemes.1)之间。"
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            if let themesSummary {
                return "记忆星图已就绪。\(themesSummary) 今天还没有明显的强连接。"
            }
            return "记忆星图已就绪。当前还没有可见主题。"
        }
    }

    private func buildAccessibilityHint(displayMode: MemoryConstellationDisplayMode) -> String {
        switch displayMode {
        case .hidden:
            return "开启记忆可见性以恢复星图内容。"
        case .privacySafe:
            return "使用星团和关系控件探索主题，同时避免暴露受保护的记忆词条。"
        case .full:
            return "使用星团和关系控件探索主要主题与最强连接。"
        }
    }

    private func themeSummary(for clusters: [MemoryConstellationCluster]) -> String? {
        let titles = clusters
            .sorted { clusterOrderIndex(for: $0.kind) < clusterOrderIndex(for: $1.kind) }
            .map(\.title)
        guard titles.isEmpty == false else {
            return nil
        }
        return "主要主题包括\(naturalLanguageList(titles))。"
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
            return "\(items[0])和\(items[1])"
        default:
            let prefix = items.dropLast().joined(separator: "、")
            return "\(prefix)和\(items.last!)"
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
