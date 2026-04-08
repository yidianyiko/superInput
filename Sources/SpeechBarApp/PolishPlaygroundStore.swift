import Foundation

enum PolishPlaygroundError: LocalizedError {
    case polishDisabled

    var errorDescription: String? {
        switch self {
        case .polishDisabled:
            return "请先开启 AI 后处理润色，再测试。"
        }
    }
}

@MainActor
final class PolishPlaygroundStore: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var outputText = ""
    @Published private(set) var statusMessage = "粘贴一段文本后，可直接测试当前 OpenAI 润色链路。"
    @Published private(set) var isRunning = false

    private let runner: (String) async throws -> String

    init(runner: @escaping (String) async throws -> String) {
        self.runner = runner
    }

    func runCurrentInput() async {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            statusMessage = "先输入要测试的文本。"
            return
        }
        guard !isRunning else { return }

        isRunning = true
        outputText = ""
        statusMessage = "正在请求润色..."
        defer { isRunning = false }

        do {
            let polished = try await runner(trimmedInput).trimmingCharacters(in: .whitespacesAndNewlines)
            outputText = polished
            statusMessage = "润色测试完成。"
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            statusMessage = message.isEmpty ? "润色测试失败。" : message
        }
    }
}
