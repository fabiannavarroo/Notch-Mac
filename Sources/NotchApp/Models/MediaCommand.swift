import Foundation

enum MediaCommand: Equatable {
    case previousTrack
    case togglePlayPause
    case nextTrack
    case seek(to: TimeInterval)
}
