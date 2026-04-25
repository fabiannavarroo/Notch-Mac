import AppKit
import Foundation

struct StashedFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let thumbnail: NSImage?
    let dateAdded: Date

    static func == (lhs: StashedFile, rhs: StashedFile) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}
