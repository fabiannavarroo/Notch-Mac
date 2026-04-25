import Foundation

struct NotchEvent: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbolName: String
    let date: Date
}
