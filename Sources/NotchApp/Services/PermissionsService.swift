import AppKit
import ApplicationServices
import Foundation
import UserNotifications

@MainActor
final class PermissionsService {
    private static let firstRunKey = "notch.permissionsRequested"

    func requestIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.firstRunKey) else { return }

        requestNotifications()
        requestAccessibilityPrompt()

        defaults.set(true, forKey: Self.firstRunKey)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func requestAccessibilityPrompt() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
