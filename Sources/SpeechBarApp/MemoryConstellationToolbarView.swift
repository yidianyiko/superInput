import SwiftUI

enum MemoryConstellationToolbarLayout {
    private static let preferredButtonWidth: CGFloat = 132
    private static let compactBreakpoint: CGFloat = 420
    private static let gridSpacing: CGFloat = 10

    static func columnCount(for availableWidth: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0 else {
            return 1
        }

        let fullRowWidth = (preferredButtonWidth * CGFloat(itemCount)) + (gridSpacing * CGFloat(max(0, itemCount - 1)))
        if availableWidth >= fullRowWidth {
            return itemCount
        }
        if availableWidth >= compactBreakpoint {
            return min(itemCount, 2)
        }
        return 1
    }
}

struct MemoryConstellationToolbarView: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let selectedFilter: MemoryConstellationClusterFilter
    let selectedViewMode: MemoryConstellationViewMode
    let selectFilter: (MemoryConstellationClusterFilter) -> Void
    let selectViewMode: (MemoryConstellationViewMode) -> Void

    @State private var availableWidth: CGFloat = 920

    var body: some View {
        MemoryConstellationPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                toolbarGroup(
                    title: "星团筛选",
                    subtitle: "先按区域读图，再看细节。",
                    itemCount: MemoryConstellationClusterFilter.allCases.count
                ) {
                    ForEach(MemoryConstellationClusterFilter.allCases) { filter in
                        toolbarButton(
                            title: filterTitle(filter),
                            isSelected: selectedFilter == filter
                        ) {
                            selectFilter(filter)
                        }
                    }
                }

                toolbarGroup(
                    title: "视图模式",
                    subtitle: "可在空间总览、关系解读和时间回放之间切换。",
                    itemCount: MemoryConstellationViewMode.allCases.count
                ) {
                    ForEach(MemoryConstellationViewMode.allCases) { mode in
                        toolbarButton(
                            title: mode.rawValue,
                            isSelected: selectedViewMode == mode
                        ) {
                            selectViewMode(mode)
                        }
                    }
                }
            }
            .background(toolbarWidthReader)
        }
    }

    private func toolbarGroup<Content: View>(
        title: String,
        subtitle: String,
        itemCount: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .leading),
            count: MemoryConstellationToolbarLayout.columnCount(for: availableWidth, itemCount: itemCount)
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(constellationTheme.secondaryText)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(constellationTheme.secondaryText.opacity(0.88))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func toolbarButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? constellationTheme.chipSelectedText : constellationTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            constellationTheme.focusAccent,
                                            constellationTheme.accent
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(constellationTheme.secondarySurfaceFill)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isSelected
                                ? constellationTheme.focusStroke.opacity(0.92)
                                : constellationTheme.secondarySurfaceStroke,
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isSelected
                        ? constellationTheme.focusAccent.opacity(0.18)
                        : Color.black.opacity(0),
                    radius: isSelected ? 10 : 0,
                    x: 0,
                    y: isSelected ? 6 : 0
                )
        }
        .buttonStyle(.plain)
    }

    private var toolbarWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    availableWidth = proxy.size.width
                }
                .onChange(of: proxy.size.width) { newWidth in
                    availableWidth = newWidth
                }
        }
    }

    private func filterTitle(_ filter: MemoryConstellationClusterFilter) -> String {
        switch filter {
        case .all:
            return "全部"
        case .vocabulary:
            return "词汇"
        case .style:
            return "风格"
        case .scenes:
            return "场景"
        }
    }
}
