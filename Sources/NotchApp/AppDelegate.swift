import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = NotchAppState()

    private var notchWindowController: NotchWindowController?
    private var mediaProvider: MediaRemoteNowPlayingProvider?
    private var hotKeyController: HotKeyController?
    private var notificationBridge: ExternalNotificationBridge?
    private var fileStashService: FileStashService?
    private let permissions = PermissionsService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        permissions.requestIfNeeded()

        fileStashService = FileStashService(appState: appState)

        notchWindowController = NotchWindowController(appState: appState)
        notchWindowController?.show()

        mediaProvider = MediaRemoteNowPlayingProvider(appState: appState)
        mediaProvider?.start()

        notificationBridge = ExternalNotificationBridge(appState: appState)
        notificationBridge?.start()

        hotKeyController = HotKeyController { [weak self] in
            Task { @MainActor in
                self?.appState.togglePinnedExpanded()
            }
        }
        hotKeyController?.start()
    }
}
