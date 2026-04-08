import CoreAudio
import Foundation

public struct AudioInputDeviceDescriptor: Sendable, Equatable, Identifiable {
    public let uid: String
    public let name: String

    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

public enum AudioInputDeviceCatalog {
    public static func availableInputDevices() -> [AudioInputDeviceDescriptor] {
        let defaultUID = defaultInputDevice()?.uid

        return allAudioDeviceIDs()
            .filter(hasInputChannels(_:))
            .compactMap { deviceID in
                guard
                    let uid = deviceUID(for: deviceID),
                    let name = deviceName(for: deviceID)
                else {
                    return nil
                }
                return AudioInputDeviceDescriptor(uid: uid, name: name)
            }
            .sorted { lhs, rhs in
                if lhs.uid == defaultUID { return true }
                if rhs.uid == defaultUID { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public static func fallbackInputDevice(avoidingUID avoidedUID: String?) -> AudioInputDeviceDescriptor? {
        let normalizedAvoidedUID = avoidedUID?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let defaultDevice = defaultInputDevice(), defaultDevice.uid != normalizedAvoidedUID {
            return defaultDevice
        }

        if let builtInDevice = builtInInputDevice(), builtInDevice.uid != normalizedAvoidedUID {
            return builtInDevice
        }

        return availableInputDevices().first { $0.uid != normalizedAvoidedUID }
    }

    public static func defaultInputDevice() -> AudioInputDeviceDescriptor? {
        guard
            let deviceID = defaultInputDeviceID(),
            let uid = deviceUID(for: deviceID),
            let name = deviceName(for: deviceID)
        else {
            return nil
        }

        return AudioInputDeviceDescriptor(uid: uid, name: name)
    }

    public static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allAudioDeviceIDs().first { deviceUID(for: $0) == uid }
    }

    public static func builtInInputDevice() -> AudioInputDeviceDescriptor? {
        allAudioDeviceIDs().compactMap { deviceID -> AudioInputDeviceDescriptor? in
            guard
                hasInputChannels(deviceID),
                deviceTransportType(for: deviceID) == kAudioDeviceTransportTypeBuiltIn,
                let uid = deviceUID(for: deviceID),
                let name = deviceName(for: deviceID)
            else {
                return nil
            }
            return AudioInputDeviceDescriptor(uid: uid, name: name)
        }.first
    }

    private static func allAudioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        guard sizeStatus == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard dataStatus == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            buffer
        )

        guard status == noErr else {
            return false
        }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )

        let channelCount = audioBufferList.reduce(into: 0) { result, audioBuffer in
            result += Int(audioBuffer.mNumberChannels)
        }

        return channelCount > 0
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        readStringProperty(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        readStringProperty(
            objectID: deviceID,
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func deviceTransportType(for deviceID: AudioDeviceID) -> UInt32? {
        readUInt32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private static func readStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )

        guard status == noErr, let value else {
            return nil
        }

        return value as String
    }

    private static func readUInt32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )

        guard status == noErr else {
            return nil
        }

        return value
    }
}
