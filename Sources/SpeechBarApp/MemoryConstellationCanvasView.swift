import Foundation
import SwiftUI

struct MemoryConstellationCanvasView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let snapshot: MemoryConstellationSnapshot
    let focus: MemoryConstellationFocus
    let selectedViewMode: MemoryConstellationViewMode
    let capturePulseToken: Int
    let pointerVector: CGPoint
    let activationProgress: CGFloat
    let hoverCluster: (MemoryConstellationClusterKind?) -> Void
    let focusBridge: (UUID?) -> Void
    let focusStar: (UUID?) -> Void

    @State private var interactionState = MemoryConstellationClusterInteractionState()
    @State private var capturePulseProgress: CGFloat = 0

    private let clusterAnchors: [MemoryConstellationClusterKind: UnitPoint] = [
        .vocabulary: UnitPoint(x: 0.24, y: 0.34),
        .style: UnitPoint(x: 0.74, y: 0.30),
        .scenes: UnitPoint(x: 0.54, y: 0.73)
    ]

    var body: some View {
        MemoryConstellationPanel(padding: 16) {
            GeometryReader { proxy in
                let size = proxy.size
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                    let fieldOffset = reduceMotion ? CGSize.zero : MemoryConstellationMotion.parallaxOffset(pointerVector: pointerVector, maxX: 26, maxY: 18)
                    let constellationOffset = reduceMotion ? CGSize.zero : MemoryConstellationMotion.parallaxOffset(pointerVector: pointerVector, maxX: 14, maxY: 10)
                    let cardOffset = reduceMotion ? CGSize.zero : MemoryConstellationMotion.parallaxOffset(pointerVector: pointerVector, maxX: 9, maxY: 6)

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(constellationTheme.canvasBackground)

                        energyField(size: size, phase: phase)
                            .offset(fieldOffset)

                        ambientGrid(size: size, phase: phase)
                            .offset(fieldOffset)

                        captureWave(size: size)

                        Group {
                            ForEach(Array(snapshot.highlightedBridges.enumerated()), id: \.element.id) { index, bridge in
                                bridgeLayer(bridge, bridgeIndex: index, size: size, phase: phase)
                            }

                            ForEach(snapshot.clusters) { cluster in
                                clusterLayer(cluster, size: size, phase: phase)
                            }
                        }
                        .offset(constellationOffset)

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
                        .offset(cardOffset)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(constellationTheme.surfaceStroke, lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                constellationTheme.focusAccent.opacity(0.32 * capturePulseProgress),
                                lineWidth: 1 + (capturePulseProgress * 3)
                            )
                            .blur(radius: capturePulseProgress * 1.2)
                    )
                }
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
        .task(id: capturePulseToken) {
            await playCapturePulseIfNeeded()
        }
        .onChange(of: focus) { newFocus in
            interactionState.sync(with: newFocus)
        }
    }

    private func ambientGrid(size: CGSize, phase: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<36, id: \.self) { index in
                Circle()
                    .fill(ambientParticleColor(index: index).opacity(MemoryConstellationMotion.ambientOpacity(index: index, phase: phase)))
                    .frame(width: index.isMultiple(of: 4) ? 5 : 2.4, height: index.isMultiple(of: 4) ? 5 : 2.4)
                    .position(
                        x: size.width * ambientX(for: index),
                        y: size.height * ambientY(for: index)
                    )
                    .blur(radius: index.isMultiple(of: 6) ? 1.2 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func bridgeLayer(
        _ bridge: MemoryConstellationBridge,
        bridgeIndex: Int,
        size: CGSize,
        phase: TimeInterval
    ) -> some View {
        let from = point(for: bridge.from, size: size)
        let to = point(for: bridge.to, size: size)
        let midpoint = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let focused = bridge.isFocused || focus == .bridge(bridge.id)
        let lift = reduceMotion ? 0 : MemoryConstellationMotion.bridgeLift(bridgeIndex: bridgeIndex, phase: phase)
        let pulseBoost = capturePulseProgress * 1.2
        let activation = max(0.28, min(1, Double(activationProgress) * 1.25 - Double(bridgeIndex) * 0.12))

        return ZStack {
            Path { path in
                path.move(to: from)
                path.addQuadCurve(
                    to: to,
                    control: CGPoint(
                        x: midpoint.x,
                        y: min(from.y, to.y) - (focused ? 84 : 54) - (lift * 0.5)
                    )
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        constellationTheme.accent.opacity((focused ? 0.95 : 0.45) * activation),
                        constellationTheme.focusAccent.opacity((focused ? 0.88 : 0.38) * activation)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: (focused ? 4 : 2) + (lift * 0.05) + pulseBoost, lineCap: .round, dash: focused ? [] : [8, 8])
            )
            .shadow(color: constellationTheme.accent.opacity((focused ? 0.42 : 0.18) + (capturePulseProgress * 0.16)), radius: (focused ? 10 : 4) + (lift * 0.18) + (capturePulseProgress * 5))
            .accessibilityHidden(true)

            Path { path in
                path.move(to: from)
                path.addQuadCurve(
                    to: to,
                    control: CGPoint(
                        x: midpoint.x,
                        y: min(from.y, to.y) - (focused ? 84 : 54) - (lift * 0.5)
                    )
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color.clear,
                        constellationTheme.focusAccent.opacity(0.85 * activation),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(
                    lineWidth: (focused ? 2.8 : 1.8) + (capturePulseProgress * 1.6),
                    lineCap: .round,
                    dash: [18, 44],
                    dashPhase: -MemoryConstellationMotion.bridgeEnergyPhase(bridgeIndex: bridgeIndex, phase: phase)
                )
            )
            .blendMode(.screen)
            .opacity(0.92)
            .accessibilityHidden(true)

            Button {
                focusBridge(focused ? nil : bridge.id)
            } label: {
                VStack(spacing: 4) {
                    Text(bridge.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text(bridgeNarrative(for: bridge))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(constellationTheme.secondaryText)
                }
                .foregroundStyle(constellationTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(constellationTheme.secondarySurfaceFill.opacity(0.94))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(constellationTheme.focusStroke.opacity(focused ? 0.75 : 0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .position(x: midpoint.x, y: midpoint.y - (focused ? 28 : 10) - lift)
            .accessibilityLabel(Text(bridgeAccessibilityLabel(for: bridge, focused: focused)))
            .accessibilityHint(Text(focused ? "点按可返回星图总览。" : "点按可在画布中聚焦这条连接。"))
        }
    }

    private func clusterLayer(
        _ cluster: MemoryConstellationCluster,
        size: CGSize,
        phase: TimeInterval
    ) -> some View {
        let anchor = point(for: cluster.kind, size: size)
        let focused = isClusterFocused(cluster)
        let radius: CGFloat = focused ? 172 : 150
        let opacity = cluster.isDimmed ? 0.34 : 1.0
        let breath = reduceMotion ? 0 : MemoryConstellationMotion.clusterBreath(cluster: cluster.kind, phase: phase)
        let pulseScale = 1 + (capturePulseProgress * (focused ? 0.08 : 0.05))
        let activationScale = 0.84 + (activationProgress * 0.16)

        return ZStack {
            Circle()
                .fill(constellationTheme.clusterGlow(for: cluster.kind, emphasis: cluster.emphasis))
                .frame(width: radius * 2, height: radius * 2)
                .scaleEffect((1 + breath) * pulseScale * activationScale)
                .blur(radius: focused ? 10 : 18)
                .accessibilityHidden(true)

            Circle()
                .stroke(constellationTheme.clusterColor(for: cluster.kind).opacity(focused ? 0.68 : 0.28), lineWidth: focused ? 1.6 : 1)
                .frame(width: radius * 1.18, height: radius * 1.18)
                .accessibilityHidden(true)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.clear,
                            constellationTheme.clusterColor(for: cluster.kind).opacity(0.18),
                            constellationTheme.focusAccent.opacity(focused ? 0.82 : 0.54),
                            Color.clear
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: focused ? 3.4 : 2.2, lineCap: .round, dash: [18, 24])
                )
                .frame(width: radius * 1.50, height: radius * 1.50)
                .scaleEffect(MemoryConstellationMotion.energyRingScale(
                    cluster: cluster.kind,
                    phase: phase,
                    activationProgress: activationProgress
                ) + (capturePulseProgress * 0.12))
                .rotationEffect(.degrees(MemoryConstellationMotion.energyRingRotation(cluster: cluster.kind, phase: phase)))
                .blur(radius: focused ? 0.8 : 1.4)
                .opacity((focused ? 0.95 : 0.68) * activationProgress)
                .accessibilityHidden(true)

            ForEach(Array(cluster.stars.enumerated()), id: \.element.id) { index, star in
                let starOffset = reduceMotion
                    ? .zero
                    : MemoryConstellationMotion.starOffset(cluster: cluster.kind, starIndex: index, phase: phase)
                let trailOffset = CGSize(width: starOffset.width * -0.32, height: starOffset.height * -0.32)
                let isSelected = selectedStarID == star.id
                Button {
                    focusStar(isSelected ? nil : star.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(
                                width: max(24, starDiameter(star, selected: isSelected) + 12),
                                height: max(24, starDiameter(star, selected: isSelected) + 12)
                            )

                        Circle()
                            .fill(starColor(for: cluster.kind, focused: focused, selected: isSelected).opacity(isSelected ? 0.34 : 0.18))
                            .frame(
                                width: starDiameter(star, selected: isSelected) + 10,
                                height: starDiameter(star, selected: isSelected) + 10
                            )
                            .blur(radius: 7)
                            .offset(trailOffset)
                            .scaleEffect(1 + (capturePulseProgress * 0.16))

                        Circle()
                            .fill(starColor(for: cluster.kind, focused: focused, selected: isSelected))
                            .frame(width: starDiameter(star, selected: isSelected), height: starDiameter(star, selected: isSelected))
                            .overlay(
                                Circle()
                                    .stroke(constellationTheme.focusAccent.opacity(isSelected ? 0.95 : 0), lineWidth: 1.5)
                            )
                            .overlay(
                                Circle()
                                    .stroke(constellationTheme.focusAccent.opacity(star.isRecentlyAdded ? 0.92 : 0), lineWidth: 1.4)
                                    .frame(
                                        width: starDiameter(star, selected: isSelected) + 8,
                                        height: starDiameter(star, selected: isSelected) + 8
                                    )
                            )
                            .shadow(color: Color.white.opacity(isSelected ? 0.40 : (focused ? 0.32 : 0.18)), radius: isSelected ? 10 : (focused ? 7 : 3))
                            .scaleEffect(
                                reduceMotion
                                    ? 1
                                    : MemoryConstellationMotion.starScale(cluster: cluster.kind, starIndex: index, phase: phase)
                            )
                            .scaleEffect(1 + (capturePulseProgress * 0.16))
                            .scaleEffect(activationScale)
                            .opacity(
                                reduceMotion
                                    ? (isSelected ? 1 : 0.88)
                                    : MemoryConstellationMotion.starOpacity(cluster: cluster.kind, starIndex: index, phase: phase)
                            )

                        if star.isRecentlyAdded {
                            Text("新")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.82))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(constellationTheme.focusAccent)
                                )
                                .offset(y: -(starDiameter(star, selected: isSelected) + 10))
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .position(
                    x: starPosition(index: index, around: anchor, radius: radius * 0.50).x + starOffset.width,
                    y: starPosition(index: index, around: anchor, radius: radius * 0.50).y + starOffset.height
                )
                .accessibilityLabel(Text(accessibilityLabel(for: star, selected: isSelected)))
                .accessibilityHint(Text("点按可查看这条真实记忆的详情。"))
            }

            Button {
                let updatedFocus = interactionState.clusterClicked(cluster.kind)
                hoverCluster(updatedFocus)
            } label: {
                VStack(spacing: 6) {
                    Text(cluster.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("\(cluster.itemCount) 个星点")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .textCase(.uppercase)
                }
                .foregroundStyle(constellationTheme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(constellationTheme.secondarySurfaceFill.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(constellationTheme.clusterColor(for: cluster.kind).opacity(focused ? 0.72 : 0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .position(x: anchor.x, y: anchor.y)
            .onHover { isHovering in
                let updatedFocus = interactionState.hoverChanged(to: isHovering ? cluster.kind : nil)
                hoverCluster(updatedFocus)
            }
            .opacity(opacity)
            .accessibilityLabel(Text("\(cluster.title)星团"))
            .accessibilityValue(Text("\(cluster.itemCount) 条记忆\(focused ? "，已聚焦" : "")"))
            .accessibilityHint(Text("点按可聚焦这个星团。"))
        }
        .opacity(opacity)
    }

    private func energyField(size: CGSize, phase: TimeInterval) -> some View {
        ZStack {
            Ellipse()
                .fill(constellationTheme.focusAccent.opacity(0.12))
                .frame(width: size.width * 0.68, height: size.height * 0.42)
                .blur(radius: 42)
                .offset(
                    x: cos(phase * 0.18) * 24,
                    y: sin(phase * 0.24) * 18
                )

            Ellipse()
                .fill(constellationTheme.accent.opacity(0.10))
                .frame(width: size.width * 0.52, height: size.height * 0.30)
                .blur(radius: 30)
                .offset(
                    x: sin(phase * 0.22) * -28,
                    y: cos(phase * 0.20) * 16
                )
        }
        .opacity(0.66 + ((1 - activationProgress) * 0.22))
        .accessibilityHidden(true)
    }

    private func captureWave(size: CGSize) -> some View {
        let primaryDiameter = min(size.width, size.height) * (0.26 + (capturePulseProgress * 0.72))
        let secondaryDiameter = min(size.width, size.height) * (0.18 + (capturePulseProgress * 0.48))

        return ZStack {
            Circle()
                .stroke(constellationTheme.focusAccent.opacity(0.46 * capturePulseProgress), lineWidth: 2.8)
                .frame(width: primaryDiameter, height: primaryDiameter)
                .blur(radius: capturePulseProgress * 2.8)

            Circle()
                .stroke(constellationTheme.accent.opacity(0.38 * capturePulseProgress), lineWidth: 1.6)
                .frame(width: secondaryDiameter, height: secondaryDiameter)
        }
        .blendMode(.screen)
        .accessibilityHidden(true)
    }

    private func guidanceCard(_ card: MemoryConstellationGuidanceCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(constellationTheme.primaryText)
            Text(card.body)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(constellationTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(constellationTheme.secondarySurfaceFill.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(constellationTheme.secondarySurfaceStroke, lineWidth: 1)
        )
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func point(for kind: MemoryConstellationClusterKind, size: CGSize) -> CGPoint {
        let anchor = clusterAnchors[kind] ?? .center
        let constellationFrame = constellationFrame(in: size)
        return CGPoint(
            x: constellationFrame.minX + constellationFrame.width * anchor.x,
            y: constellationFrame.minY + constellationFrame.height * anchor.y
        )
    }

    private func constellationFrame(in size: CGSize) -> CGRect {
        let leadingInset = min(max(size.width * 0.28, 220), 300)
        let trailingInset = max(56, size.width * 0.08)
        let topInset: CGFloat = 44
        let bottomInset: CGFloat = 54

        return CGRect(
            x: leadingInset,
            y: topInset,
            width: max(size.width - leadingInset - trailingInset, 220),
            height: max(size.height - topInset - bottomInset, 220)
        )
    }

    private func starPosition(index: Int, around center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(index) * 1.22 + 0.45
        let distance = radius * (0.42 + CGFloat(index % 4) * 0.12)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * distance,
            y: center.y + CGFloat(sin(angle)) * distance
        )
    }

    private func starDiameter(_ star: MemoryConstellationStar, selected: Bool) -> CGFloat {
        CGFloat(4 + (star.strength * 8) + (selected ? 4 : 0))
    }

    private func starColor(for kind: MemoryConstellationClusterKind, focused: Bool, selected: Bool) -> Color {
        if selected || focused {
            return constellationTheme.focusAccent
        }
        return constellationTheme.clusterColor(for: kind).opacity(0.88)
    }

    private func isClusterFocused(_ cluster: MemoryConstellationCluster) -> Bool {
        switch focus {
        case .overview:
            return false
        case .cluster(let activeKind):
            return activeKind == cluster.kind
        case .bridge:
            return false
        case .star(let selectedID):
            return cluster.stars.contains(where: { $0.id == selectedID })
        }
    }

    private var selectedStarID: UUID? {
        guard case .star(let id) = focus else {
            return nil
        }
        return id
    }

    private func accessibilityLabel(for star: MemoryConstellationStar, selected: Bool) -> String {
        let selection = selected ? "，已选中" : ""
        let recent = star.isRecentlyAdded ? "，刚新增" : ""
        return "\(star.label)\(recent)\(selection)"
    }

    private func ambientX(for index: Int) -> CGFloat {
        let values: [CGFloat] = [0.05, 0.12, 0.18, 0.24, 0.31, 0.38, 0.46, 0.53, 0.61, 0.69, 0.76, 0.84, 0.91, 0.96]
        return values[index % values.count]
    }

    private func ambientY(for index: Int) -> CGFloat {
        let values: [CGFloat] = [0.08, 0.14, 0.20, 0.27, 0.35, 0.42, 0.50, 0.58, 0.66, 0.73, 0.81]
        return values[(index * 3) % values.count]
    }

    private func ambientParticleColor(index: Int) -> Color {
        if index.isMultiple(of: 6) {
            return constellationTheme.focusAccent
        }
        if index.isMultiple(of: 4) {
            return constellationTheme.accent
        }
        return Color.white
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

    @MainActor
    private func playCapturePulseIfNeeded() async {
        guard capturePulseToken > 0, !reduceMotion else {
            return
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.60)) {
            capturePulseProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(420))

        withAnimation(.easeOut(duration: 0.56)) {
            capturePulseProgress = 0
        }
    }

    private func bridgeNarrative(for bridge: MemoryConstellationBridge) -> String {
        switch selectedViewMode {
        case .clusterMap:
            return "今日连接"
        case .bridgeStories:
            return "关系焦点"
        case .timelineReplay:
            return "回放线索"
        }
    }

    private func bridgeAccessibilityLabel(for bridge: MemoryConstellationBridge, focused: Bool) -> String {
        let orderedTitles = orderedClusterTitles(for: bridge)
        let focusState = focused ? "已聚焦。" : ""
        return "\(focusState)\(bridge.label)。\(bridgeNarrative(for: bridge))。连接\(orderedTitles.0)与\(orderedTitles.1)。"
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
