import Foundation
import IOKit.ps

@MainActor
final class BatteryService {
    private let appState: NotchAppState
    private var lastPercent: Int = -1
    private var lastIsCharging: Bool?
    private var timer: Timer?

    init(appState: NotchAppState) {
        self.appState = appState
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard let snapshot = readBattery() else { return }

        if let last = lastIsCharging, last != snapshot.isCharging {
            if snapshot.isCharging {
                appState.pushEvent(
                    title: "Cargando",
                    detail: "\(snapshot.percent)%",
                    symbolName: "bolt.fill"
                )
            } else {
                appState.pushEvent(
                    title: "Sin cargador",
                    detail: "\(snapshot.percent)%",
                    symbolName: "battery.50"
                )
            }
        }

        if snapshot.percent <= 20 && lastPercent > 20 && !snapshot.isCharging {
            appState.pushEvent(
                title: "Batería baja",
                detail: "\(snapshot.percent)%",
                symbolName: "battery.25"
            )
        }

        if snapshot.percent == 100 && lastPercent != 100 && snapshot.isCharging {
            appState.pushEvent(
                title: "Cargada",
                detail: "100%",
                symbolName: "battery.100.bolt"
            )
        }

        lastPercent = snapshot.percent
        lastIsCharging = snapshot.isCharging
    }

    private struct Snapshot {
        let percent: Int
        let isCharging: Bool
    }

    private func readBattery() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            guard let capacity = info[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = info[kIOPSMaxCapacityKey as String] as? Int,
                  max > 0 else { continue }
            let percent = Int(round(Double(capacity) / Double(max) * 100))
            let powerState = info[kIOPSPowerSourceStateKey as String] as? String
            let isCharging = powerState == kIOPSACPowerValue
            return Snapshot(percent: percent, isCharging: isCharging)
        }
        return nil
    }
}
