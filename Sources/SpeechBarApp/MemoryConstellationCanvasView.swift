import Foundation
import SwiftUI

struct MemoryConstellationCanvasView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: MemoryConstellationSnapshot
    let focus: MemoryConstellationFocus
    let selectedViewMode: MemoryConstellationViewMode
    let hoverCluster: (MemoryConstellationClusterKind?) -> Void
    let focusBridge: (UUID?) -> Void

    @State private var interactionState = MemoryConstellationClusterInteractionState()

    private let clusterAnchors: [MemoryConstellationClusterKind: UnitPoint] = [
        .vocabulary: UnitPoint(x: 0.24, y: 0.34),
        .style: UnitPoint(x: 0.74, y: 0.30),
        .scenes: UnitPoint(x: 0.54, y: 0.73)
    ]

    var body: some View {
        MemoryConstellationPanel(padding: 16) {
            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(MemoryConstellationTheme.canvasBackground)

                    ambientGrid(size: size)

                    ForEach(snapshot.highlightedBridges) { bridge in
                        bridgeLayer(bridge, size: size)
                    }

                    ForEach(snapshot.clusters) { cluster in
                        clusterLayer(cluster, size: size)
                    }

                    VStack {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(snapshot.guidanceCards) { card in
                                    guidanceCard(card)
                                }
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .frame(minHeight: 470)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .accessibilityLabel(Text(snapshot.accessibilitySummary))
        .accessibilityHint(Text(snapshot.accessibilityHint))
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: focusAccessibilityKey)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: snapshot.highlightedBridges.map(\.id))
        .onChange(of: focus) { newFocus in
            interactionState.sync(with: newFocus)
        }
    }

    private func ambientGrid(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<24, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index.isMultiple(of: 5) ? 0.22 : 0.10))
                    .frame(width: index.isMultiple(of: 4) ? 4 : 2, height: index.isMultiple(of: 4) ? 4 : 2)
                    .position(
                        x: size.width * ambientX(for: index),
                        y: size.height * ambientY(for: index)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func bridgeLayer(_ bridge: MemoryConstellationBridge, size: CGSize) -> some View {
        let from = point(for: bridge.from, size: size)
        let to = point(for: bridge.to, size: size)
        let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let focused = bridge.isFocused || focus == .bridge(bridge.id)

        return ZStack {
            Path { path in
                path.move(to: from)
                path.addQuadCurve(
                    to: to,
                    control: CGPoint(
                        x: midpoint.x,
                        y: min(from.y, to.y) - (focused ? 84 : 54)
                    )
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        MemoryConstellationTheme.accentGold.opacity(focused ? 0.95 : 0.45),
                        MemoryConstellationTheme.focusGold.opacity(focused ? 0.88 : 0.38)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: focused ? 4 : 2, lineCap: .round, dash: focused ? [] : [8, 8])
            )
            .shadow(color: MemoryConstellationTheme.accentGold.opacity(focused ? 0.42 : 0.18), radius: focused ? 10 : 4)
            .accessibilityHidden(true)

            Button {
                focusBridge(focused ? nil : bridge.id)
            } label: {
                VStack(spacing: 4) {
                    Text(bridge.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text(bridgeNarrative(for: bridge))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MemoryConstellationTheme.secondaryText)
                }
                .foregroundStyle(MemoryConstellationTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.34))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(MemoryConstellationTheme.accentGold.opacity(focused ? 0.75 : 0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .position(x: midpoint.x, y: midpoint.y - (focused ? 28 : 10))
            .accessibilityLabel(Text(bridgeAccessibilityLabel(for: bridge, focused: focused)))
            .accessibilityHint(Text(focused ? "Select to return to the constellation overview." : "Select to focus this bridge on the canvas."))
        }
    }

    private func clusterLayer(_ cluster: MemoryConstellationCluster, size: CGSize) -> some View {
        let anchor = point(for: cluster.kind, size: size)
        let focused = isClusterFocused(cluster.kind)
        let radius: CGFloat = focused ? 172 : 150
        let opacity = cluster.isDimmed ? 0.34 : 1.0

        return ZStack {
            Circle()
                .fill(MemoryConstellationTheme.clusterGlow(for: cluster.kind, emphasis: cluster.emphasis))
                .frame(width: radius * 2, height: radius * 2)
                .blur(radius: focused ? 10 : 18)
                .accessibilityHidden(true)

            Circle()
                .stroke(MemoryConstellationTheme.clusterColor(for: cluster.kind).opacity(focused ? 0.68 : 0.28), lineWidth: focused ? 1.6 : 1)
                .frame(width: radius * 1.18, height: radius * 1.18)
                .accessibilityHidden(true)

            ForEach(Array(cluster.stars.enumerated()), id: \.element.id) { index, star in
                Circle()
                    .fill(starColor(for: cluster.kind, focused: focused))
                    .frame(width: starDiameter(star), height: starDiameter(star))
                    .shadow(color: Color.white.opacity(focused ? 0.32 : 0.18), radius: focused ? 7 : 3)
                    .position(starPosition(index: index, around: anchor, radius: radius * 0.50))
                    .accessibilityHidden(true)
            }

            Button {
                let updatedFocus = interactionState.clusterClicked(cluster.kind)
                hoverCluster(updatedFocus)
            } label: {
                VStack(spacing: 6) {
                    Text(cluster.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("\(cluster.itemCount) stars")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .textCase(.uppercase)
                }
                .foregroundStyle(MemoryConstellationTheme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(MemoryConstellationTheme.clusterColor(for: cluster.kind).opacity(focused ? 0.72 : 0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .position(x: anchor.x, y: anchor.y)
            .onHover { isHovering in
                let updatedFocus = interactionState.hoverChanged(to: isHovering ? cluster.kind : nil)
                hoverCluster(updatedFocus)
            }
            .opacity(opacity)
            .accessibilityLabel(Text("\(cluster.title) cluster"))
            .accessibilityValue(Text("\(cluster.itemCount) memories\(focused ? ", focused" : "")"))
            .accessibilityHint(Text("Select to focus this cluster in the constellation."))
        }
        .opacity(opacity)
    }

    private func guidanceCard(_ card: MemoryConstellationGuidanceCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(MemoryConstellationTheme.primaryText)
            Text(card.body)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MemoryConstellationTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func point(for kind: MemoryConstellationClusterKind, size: CGSize) -> CGPoint {
        let anchor = clusterAnchors[kind] ?? .center
        return CGPoint(x: size.width * anchor.x, y: size.height * anchor.y)
    }

    private func starPosition(index: Int, around center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(index) * 1.22 + 0.45
        let distance = radius * (0.42 + CGFloat(index % 4) * 0.12)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * distance,
            y: center.y + CGFloat(sin(angle)) * distance
        )
    }

    private func starDiameter(_ star: MemoryConstellationStar) -> CGFloat {
        CGFloat(4 + (star.strength * 8))
    }

    private func starColor(for kind: MemoryConstellationClusterKind, focused: Bool) -> Color {
        focused ? MemoryConstellationTheme.focusGold : MemoryConstellationTheme.clusterColor(for: kind).opacity(0.88)
    }

    private func isClusterFocused(_ kind: MemoryConstellationClusterKind) -> Bool {
        switch focus {
        case .overview:
            return false
        case .cluster(let activeKind):
            return activeKind == kind
        case .bridge:
            return false
        case .star:
            return false
        }
    }

    private func ambientX(for index: Int) -> CGFloat {
        let values: [CGFloat] = [0.07, 0.14, 0.21, 0.30, 0.38, 0.46, 0.57, 0.63, 0.72, 0.81, 0.88, 0.94]
        return values[index % values.count]
    }

    private func ambientY(for index: Int) -> CGFloat {
        let values: [CGFloat] = [0.10, 0.18, 0.24, 0.31, 0.40, 0.47, 0.56, 0.62, 0.70, 0.78]
        return values[(index * 3) % values.count]
    }

    private var focusAccessibilityKey: String {
        switch focus {
        case .overview:
            return "overview"
        case .cluster(let cluster):
            return "cluster:\(cluster.rawValue)"
        case .bridge(let id):
            return "bridge:\(id.uuidString)"
        case .star(let id):
            return "star:\(id.uuidString)"
        }
    }

    private func bridgeNarrative(for bridge: MemoryConstellationBridge) -> String {
        switch selectedViewMode {
        case .clusterMap:
            return "Today’s bridge"
        case .bridgeStories:
            return "Story focus"
        case .timelineReplay:
            return "Replay thread"
        }
    }

    private func bridgeAccessibilityLabel(for bridge: MemoryConstellationBridge, focused: Bool) -> String {
        let orderedTitles = orderedClusterTitles(for: bridge)
        let focusState = focused ? "Focused. " : ""
        return "\(focusState)\(bridge.label). \(bridgeNarrative(for: bridge)). Connects \(orderedTitles.0) and \(orderedTitles.1)."
    }

    private func orderedClusterTitles(for bridge: MemoryConstellationBridge) -> (String, String) {
        let orderedKinds = MemoryConstellationClusterKind.allCases
        let fromIndex = orderedKinds.firstIndex(of: bridge.from) ?? .max
        let toIndex = orderedKinds.firstIndex(of: bridge.to) ?? .max
        if fromIndex <= toIndex {
            return (bridge.from.title, bridge.to.title)
        }
        return (bridge.to.title, bridge.from.title)
    }
}

struct MemoryConstellationClusterInteractionState {
    private var hoveredCluster: MemoryConstellationClusterKind?
    private var committedCluster: MemoryConstellationClusterKind?

    mutating func sync(with focus: MemoryConstellationFocus) {
        switch focus {
        case .cluster(let cluster):
            if committedCluster == nil {
                hoveredCluster = cluster
            }
        default:
            hoveredCluster = nil
            committedCluster = nil
        }
    }

    mutating func hoverChanged(to cluster: MemoryConstellationClusterKind?) -> MemoryConstellationClusterKind? {
        hoveredCluster = cluster
        return effectiveClusterFocus
    }

    mutating func clusterClicked(_ cluster: MemoryConstellationClusterKind) -> MemoryConstellationClusterKind? {
        committedCluster = cluster
        hoveredCluster = cluster
        return effectiveClusterFocus
    }

    private var effectiveClusterFocus: MemoryConstellationClusterKind? {
        committedCluster ?? hoveredCluster
    }
}
