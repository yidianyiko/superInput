import SwiftUI

struct MemoryConstellationRelationshipTrayView: View {
    let cards: [MemoryConstellationRelationshipCard]
    let focusBridge: (UUID?) -> Void

    var body: some View {
        MemoryConstellationPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Relationship Tray")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(MemoryConstellationTheme.secondaryText)

                if cards.isEmpty {
                    Text("No bridge story is dominant yet. The sky will stay quiet until a stronger pattern forms.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MemoryConstellationTheme.secondaryText)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(cards.prefix(3)) { card in
                            Button {
                                focusBridge(card.bridgeID)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(card.title)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(MemoryConstellationTheme.primaryText)

                                    Text(card.body)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(MemoryConstellationTheme.secondaryText)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)

                                    Text(card.bridgeID == nil ? "Overview" : "Focus Bridge")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(MemoryConstellationTheme.focusGold)
                                }
                                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
