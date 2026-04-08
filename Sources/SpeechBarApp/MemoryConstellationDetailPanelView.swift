import Foundation
import MemoryDomain
import SwiftUI

struct MemoryConstellationDetailPanelView: View {
    @Environment(\.memoryConstellationTheme) private var constellationTheme

    let memory: MemoryItem?
    let displayMode: MemoryConstellationDisplayMode
    let hasVisibleMemories: Bool

    var body: some View {
        MemoryConstellationPanel(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("星点详情")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(constellationTheme.secondaryText)

                if displayMode == .hidden {
                    placeholder(
                        title: "记忆已隐藏",
                        body: "当前处于隐藏模式，先切回完整显示或隐私保护，才能查看真实星点。"
                    )
                } else if let memory {
                    detail(memory)
                } else if hasVisibleMemories {
                    placeholder(
                        title: "等待选中",
                        body: "点击任意星点后，这里会显示该条真实记忆的内容、作用域和更新时间。"
                    )
                } else {
                    placeholder(
                        title: "还没有真实记忆",
                        body: "当前数据库里没有可展示的记忆，完成一次真实采集后这里才会出现星点详情。"
                    )
                }
            }
        }
    }

    private func detail(_ memory: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    MemoryConstellationTag(title: typeLabel(for: memory.type))
                    MemoryConstellationTag(title: confidenceLabel(for: memory.confidence))
                }

                Text(primaryValue(for: memory))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(constellationTheme.primaryText)
                    .textSelection(.enabled)

                Text(secondaryValue(for: memory))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(constellationTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            detailRow(title: "作用域", value: scopeLabel(for: memory.scope))
            detailRow(title: "内部键", value: memory.key)
            detailRow(title: "最近更新", value: Self.timestampFormatter.string(from: memory.updatedAt))
            detailRow(title: "关联事件", value: "\(memory.sourceEventIDs.count) 个")
        }
    }

    private func placeholder(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(constellationTheme.primaryText)

            Text(body)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(constellationTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 148, alignment: .leading)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(constellationTheme.secondaryText)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(constellationTheme.primaryText)
                .textSelection(.enabled)
        }
    }

    private func primaryValue(for memory: MemoryItem) -> String {
        displayMode == .privacySafe ? "受保护记忆" : memory.valueFingerprint
    }

    private func secondaryValue(for memory: MemoryItem) -> String {
        if displayMode == .privacySafe {
            return "当前处于隐私保护模式，具体词条内容已隐藏。"
        }

        let payload = String(data: memory.valuePayload, encoding: .utf8) ?? "无法解码原始内容"
        if payload == memory.valueFingerprint {
            return "真实内容：\(payload)"
        }
        return "摘要：\(memory.valueFingerprint)\n真实内容：\(payload)"
    }

    private func typeLabel(for type: MemoryType) -> String {
        switch type {
        case .vocabulary:
            return "词汇"
        case .correction:
            return "修正"
        case .style:
            return "风格"
        case .scene:
            return "场景"
        }
    }

    private func confidenceLabel(for confidence: Double) -> String {
        "置信度 \(Int((confidence * 100).rounded()))%"
    }

    private func scopeLabel(for scope: MemoryScope) -> String {
        switch scope {
        case .global:
            return "全局"
        case .app(let appIdentifier):
            return "应用 · \(appIdentifier)"
        case .window(let appIdentifier, let windowTitle):
            return "窗口 · \(appIdentifier) / \(windowTitle)"
        case .field(let appIdentifier, let windowTitle, let fieldRole, let fieldLabel):
            let window = windowTitle ?? "未命名窗口"
            let field = fieldLabel ?? fieldRole
            return "字段 · \(appIdentifier) / \(window) / \(field)"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
