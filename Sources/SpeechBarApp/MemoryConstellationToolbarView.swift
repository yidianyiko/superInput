import SwiftUI

struct MemoryConstellationToolbarView: View {
    let selectedFilter: MemoryConstellationClusterFilter
    let selectedViewMode: MemoryConstellationViewMode
    let selectFilter: (MemoryConstellationClusterFilter) -> Void
    let selectViewMode: (MemoryConstellationViewMode) -> Void

    var body: some View {
        MemoryConstellationPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                toolbarGroup(
                    title: "星团筛选",
                    subtitle: "先按区域读图，再看细节。"
                ) {
                    ForEach(MemoryConstellationClusterFilter.allCases) { filter in
                        MemoryConstellationChip(
                            title: filterTitle(filter),
                            isSelected: selectedFilter == filter
                        ) {
                            selectFilter(filter)
                        }
                    }
                }

                toolbarGroup(
                    title: "视图模式",
                    subtitle: "可在空间总览、关系解读和时间回放之间切换。"
                ) {
                    ForEach(MemoryConstellationViewMode.allCases) { mode in
                        MemoryConstellationChip(
                            title: mode.rawValue,
                            isSelected: selectedViewMode == mode
                        ) {
                            selectViewMode(mode)
                        }
                    }
                }
            }
        }
    }

    private func toolbarGroup<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(MemoryConstellationTheme.secondaryText)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MemoryConstellationTheme.secondaryText.opacity(0.88))

            HStack(spacing: 8) {
                content()
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
