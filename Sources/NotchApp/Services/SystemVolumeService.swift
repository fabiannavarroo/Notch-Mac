import CoreAudio
import Foundation

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let kind: AudioOutputKind

    var symbolName: String {
        kind.symbolName
    }

    init(id: AudioDeviceID, name: String) {
        self.id = id
        self.name = name
        self.kind = AudioOutputKind(deviceName: name)
    }
}

enum AudioOutputKind: Equatable {
    case airPodsMax
    case airPodsPro
    case airPods
    case beats
    case headphones
    case homePod
    case airPlay
    case display
    case builtInSpeaker
    case speaker

    init(deviceName: String) {
        let normalized = deviceName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if normalized.contains("airpods max") {
            self = .airPodsMax
        } else if normalized.contains("airpods pro") {
            self = .airPodsPro
        } else if normalized.contains("airpods") {
            self = .airPods
        } else if normalized.contains("beats") {
            self = .beats
        } else if normalized.contains("headphone")
            || normalized.contains("auricular")
            || normalized.contains("audifono")
            || normalized.contains("casco")
            || normalized.contains("earbud")
            || normalized.contains("earphone") {
            self = .headphones
        } else if normalized.contains("homepod") {
            self = .homePod
        } else if normalized.contains("airplay")
            || normalized.contains("apple tv")
            || normalized.contains("tv") {
            self = .airPlay
        } else if normalized.contains("display")
            || normalized.contains("monitor")
            || normalized.contains("hdmi")
            || normalized.contains("pantalla") {
            self = .display
        } else if normalized.contains("macbook")
            || normalized.contains("internal speaker")
            || normalized.contains("built-in")
            || normalized.contains("integrated")
            || normalized.contains("altavoz interno")
            || normalized.contains("altavoces internos") {
            self = .builtInSpeaker
        } else {
            self = .speaker
        }
    }

    var symbolName: String {
        switch self {
        case .airPodsMax:
            return "airpodsmax"
        case .airPodsPro:
            return "airpodspro"
        case .airPods:
            return "airpods"
        case .beats:
            return "beats.headphones"
        case .headphones:
            return "headphones"
        case .homePod:
            return "homepod.fill"
        case .airPlay:
            return "airplayaudio"
        case .display:
            return "tv"
        case .builtInSpeaker:
            return "speaker.wave.3.fill"
        case .speaker:
            return "hifispeaker.fill"
        }
    }
}

@MainActor
final class SystemVolumeService: ObservableObject {
    @Published var volume: Float = 0
    @Published var isMuted: Bool = false
    @Published var outputDevices: [OutputDevice] = []
    @Published var currentDeviceID: AudioDeviceID = 0

    var currentOutputDevice: OutputDevice? {
        outputDevices.first { $0.id == currentDeviceID }
    }

    var currentOutputSymbolName: String {
        currentOutputDevice?.symbolName ?? AudioOutputKind(deviceName: "").symbolName
    }

    private var defaultOutputListenerToken: AudioObjectPropertyListenerBlock?
    private var deviceListListenerToken: AudioObjectPropertyListenerBlock?
    private var volumeListenerToken: AudioObjectPropertyListenerBlock?
    private var observedDeviceID: AudioDeviceID = 0

    init() {
        refreshDevices()
        refresh()
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
        if currentOutputDevice == nil {
            refreshDevices()
        }
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
        startObservingDefaultOutput()
        startObservingDeviceList()
        startObservingCurrentDeviceVolume()
    }

    private func startObservingDefaultOutput() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleAudioRouteChanged()
            }
        }
        defaultOutputListenerToken = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    private func startObservingDeviceList() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleAudioRouteChanged()
            }
        }
        deviceListListenerToken = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
    }

    private func handleAudioRouteChanged() {
        refreshDevices()
        refresh()
        startObservingCurrentDeviceVolume()
    }

    private func startObservingCurrentDeviceVolume() {
        guard let device = defaultOutputDeviceID() else { return }
        guard device != observedDeviceID || volumeListenerToken == nil else { return }
        stopObservingCurrentDeviceVolume()
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
        volumeListenerToken = block
        AudioObjectAddPropertyListenerBlock(device, &addr, .main, block)
    }

    private func stopObservingCurrentDeviceVolume() {
        guard let block = volumeListenerToken, observedDeviceID != 0 else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(observedDeviceID, &addr, .main, block)
        volumeListenerToken = nil
        observedDeviceID = 0
    }
}
