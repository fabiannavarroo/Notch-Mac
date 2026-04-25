import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchApp", systemImage: "capsule.tophalf.filled") {
            MenuBarView(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
