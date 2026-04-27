import CoreAudio
import Foundation

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

@MainActor
final class SystemVolumeService: ObservableObject {
    @Published var volume: Float = 0
    @Published var isMuted: Bool = false
    @Published var outputDevices: [OutputDevice] = []
    @Published var currentDeviceID: AudioDeviceID = 0

    private var listenerToken: AudioObjectPropertyListenerBlock?
    private var observedDeviceID: AudioDeviceID = 0

    init() {
        refresh()
        refreshDevices()
        startObserving()
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        guard let device = defaultOutputDeviceID() else { return }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var newValue = clamped
        let size = UInt32(MemoryLayout<Float>.size)

        if AudioObjectHasProperty(device, &addr) {
            AudioObjectSetPropertyData(device, &addr, 0, nil, size, &newValue)
        } else {
            for channel: UInt32 in [1, 2] {
                var chanAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: channel
                )
                if AudioObjectHasProperty(device, &chanAddr) {
                    AudioObjectSetPropertyData(device, &chanAddr, 0, nil, size, &newValue)
                }
            }
        }

        volume = clamped
    }

    func toggleMute() {
        guard let device = defaultOutputDeviceID() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &addr) else { return }
        var muted: UInt32 = isMuted ? 0 : 1
        AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted)
        isMuted.toggle()
    }

    func refresh() {
        volume = readVolume() ?? 0
        isMuted = readMute() ?? false
        currentDeviceID = defaultOutputDeviceID() ?? 0
    }

    func refreshDevices() {
        outputDevices = listOutputDevices()
    }

    func setOutputDevice(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        if status == noErr {
            currentDeviceID = id
            refresh()
        }
    }

    private func listOutputDevices() -> [OutputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }

        return ids.compactMap { id -> OutputDevice? in
            guard hasOutputChannels(id) else { return nil }
            let name = deviceName(id) ?? "Salida \(id)"
            return OutputDevice(id: id, name: name)
        }
    }

    private func hasOutputChannels(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return false }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, bufferList) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers where buffer.mNumberChannels > 0 {
            return true
        }
        return false
    }

    private func deviceName(_ device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var name: CFString?
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name as String?
    }

    private func readVolume() -> Float? {
        guard let device = defaultOutputDeviceID() else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Float>.size)
        var value: Float = 0

        if AudioObjectHasProperty(device, &addr),
           AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
            return value
        }

        var sum: Float = 0
        var count: Float = 0
        for channel: UInt32 in [1, 2] {
            var chanAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            var chanSize = UInt32(MemoryLayout<Float>.size)
            var chanValue: Float = 0
            if AudioObjectHasProperty(device, &chanAddr),
               AudioObjectGetPropertyData(device, &chanAddr, 0, nil, &chanSize, &chanValue) == noErr {
                sum += chanValue
                count += 1
            }
        }
        return count > 0 ? sum / count : nil
    }

    private func readMute() -> Bool? {
        guard let device = defaultOutputDeviceID() else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID: AudioDeviceID = 0
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr else {
            return nil
        }
        return deviceID
    }

    private func startObserving() {
        guard let device = defaultOutputDeviceID() else { return }
        observedDeviceID = device

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        listenerToken = block
        AudioObjectAddPropertyListenerBlock(device, &addr, .main, block)
    }
}
