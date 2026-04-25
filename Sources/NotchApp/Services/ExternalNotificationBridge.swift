import Foundation

@MainActor
final class ExternalNotificationBridge {
    private let appState: NotchAppState

    init(appState: NotchAppState) {
        self.appState = appState
    }

    func start() {
        // This bridge is intentionally quiet on launch; test events live in the menu bar.
    }
}
