import SwiftUI

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchApp", systemImage: "inset.filled.tophalf.rectangle") {
            MenuBarView(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
