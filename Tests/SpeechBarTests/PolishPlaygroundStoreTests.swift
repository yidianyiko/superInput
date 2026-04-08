import Testing
@testable import SpeechBarApp

@Suite("PolishPlaygroundStore")
struct PolishPlaygroundStoreTests {
    @Test
    @MainActor
    func successfulRunStoresPolishedOutput() async {
        let store = PolishPlaygroundStore { input in
            "polished::\(input)"
        }
        store.inputText = "  hello world  "

        await store.runCurrentInput()

        #expect(store.outputText == "polished::hello world")
        #expect(store.statusMessage == "润色测试完成。")
        #expect(!store.isRunning)
    }

    @Test
    @MainActor
    func emptyInputSkipsRequestAndShowsHint() async {
        let store = PolishPlaygroundStore { _ in
            Issue.record("runner should not be called")
            return ""
        }

        await store.runCurrentInput()

        #expect(store.outputText.isEmpty)
        #expect(store.statusMessage == "先输入要测试的文本。")
        #expect(!store.isRunning)
    }
}
