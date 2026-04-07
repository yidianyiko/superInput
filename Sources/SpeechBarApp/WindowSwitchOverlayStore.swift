import Combine
import SpeechBarDomain

@MainActor
final class WindowSwitchOverlayStore: ObservableObject, WindowSwitchPreviewPublishing, @unchecked Sendable {
    @Published private(set) var isVisible = false
    @Published private(set) var items: [WindowSwitchPreviewItem] = []
    @Published private(set) var selectedIndex = 0

    func showWindowSwitchPreview(items: [WindowSwitchPreviewItem], selectedIndex: Int) async {
        self.items = items
        self.selectedIndex = min(max(selectedIndex, 0), max(items.count - 1, 0))
        isVisible = !items.isEmpty
    }

    func hideWindowSwitchPreview() async {
        isVisible = false
    }
}
