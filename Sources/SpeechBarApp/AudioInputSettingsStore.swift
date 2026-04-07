import Foundation
import SpeechBarInfrastructure

@MainActor
final class AudioInputSettingsStore: ObservableObject, @unchecked Sendable {
    nonisolated static let systemDefaultSelectionID = "__system_default__"
    nonisolated static let selectedDeviceUIDDefaultsKey = "audio.input.selectedDeviceUID"

    @Published private(set) var availableDevices: [AudioInputDeviceDescriptor] = []
    @Published private(set) var defaultInputDeviceName = "系统默认"
    @Published var selectedSelectionID: String {
        didSet {
            defaults.set(selectedSelectionID, forKey: Self.selectedDeviceUIDDefaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSelection = defaults.string(forKey: Self.selectedDeviceUIDDefaultsKey)
        self.selectedSelectionID = storedSelection ?? Self.systemDefaultSelectionID
        refreshAvailableDevices()
    }

    var selectedDeviceUIDForCapture: String? {
        Self.preferredDeviceUID(from: defaults)
    }

    var selectionSummary: String {
        if selectedSelectionID == Self.systemDefaultSelectionID {
            return "系统默认 · \(defaultInputDeviceName)"
        }

        if let selectedDevice = availableDevices.first(where: { $0.uid == selectedSelectionID }) {
            return selectedDevice.name
        }

        return "系统默认 · \(defaultInputDeviceName)"
    }

    var selectionHint: String {
        selectedSelectionID == Self.systemDefaultSelectionID
            ? "跟随 macOS 当前默认输入设备。"
            : "切换后下次录音生效。"
    }

    func refreshAvailableDevices() {
        availableDevices = AudioInputDeviceCatalog.availableInputDevices()
        defaultInputDeviceName = AudioInputDeviceCatalog.defaultInputDevice()?.name ?? "未检测到可用输入设备"

        if selectedSelectionID != Self.systemDefaultSelectionID,
           !availableDevices.contains(where: { $0.uid == selectedSelectionID }) {
            selectedSelectionID = Self.systemDefaultSelectionID
        }
    }

    func selectSystemDefault() {
        selectedSelectionID = Self.systemDefaultSelectionID
    }

    func selectDevice(uid: String) {
        selectedSelectionID = uid
    }

    nonisolated static func preferredDeviceUID(from defaults: UserDefaults = .standard) -> String? {
        let storedValue = defaults.string(forKey: selectedDeviceUIDDefaultsKey)
        guard let storedValue, storedValue != systemDefaultSelectionID else {
            return nil
        }
        return storedValue
    }
}
