import Combine
import Foundation

@MainActor
final class MemoryFeatureFlagStore: ObservableObject {
    @Published var captureEnabled: Bool
    @Published var recallEnabled: Bool

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.captureEnabled = defaults.object(forKey: Keys.captureEnabled) as? Bool ?? true
        self.recallEnabled = defaults.object(forKey: Keys.recallEnabled) as? Bool ?? false
        bindPersistence()
    }

    private func bindPersistence() {
        $captureEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.captureEnabled)
            }
            .store(in: &cancellables)

        $recallEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.recallEnabled)
            }
            .store(in: &cancellables)
    }
}

private enum Keys {
    static let captureEnabled = "memory.captureEnabled"
    static let recallEnabled = "memory.recallEnabled"
}
