import SwiftUI

struct MemoryConstellationRelationshipTrayView: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let cards: [MemoryConstellationRelationshipCard]
    let focusBridge: (UUID?) -> Void

    var body: some View {
        MemoryConstellationPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("关系解读")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(constellationTheme.secondaryText)

                if cards.isEmpty {
                    Text("当前还没有哪条关系特别突出，等更强的模式形成后这里会更清晰。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(constellationTheme.secondaryText)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(cards.prefix(3)) { card in
                            Button {
                                focusBridge(card.bridgeID)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(card.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(constellationTheme.primaryText)

                                    Text(card.body)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(constellationTheme.secondaryText)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)

                                    Text(card.bridgeID == nil ? "返回总览" : "聚焦连接")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(constellationTheme.focusAccent)
                                }
                                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(constellationTheme.secondarySurfaceFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(constellationTheme.secondarySurfaceStroke, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(card.accessibilityLabel))
                            .accessibilityHint(Text(card.accessibilityHint))
                        }
                    }
                }
            }
        }
    }
}
