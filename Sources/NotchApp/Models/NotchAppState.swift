import Combine
import CoreGraphics
import Foundation

@MainActor
final class NotchAppState: ObservableObject {
    private enum DefaultsKey {
        static let verticalOffset = "notch.verticalOffset"
    }

    enum Presentation: Equatable {
        case idle
        case media
        case trackPreview
        case expanded
    }

    @Published var isIslandEnabled = true
    @Published var isHoverExpanded = false
    @Published var isHoverHovering = false
    @Published var isPinnedExpanded = false
    @Published var isPeeking = false
    @Published var nowPlaying: NowPlayingItem?
    @Published var latestEvent: NotchEvent?
    @Published var verticalOffset: CGFloat
    @Published var notchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var stashedFiles: [StashedFile] = []
    @Published var isDropTargeted: Bool = false

    @Published var isTrackPreviewActive: Bool = false

    var mediaCommandHandler: ((MediaCommand) -> Void)?
    var ingestURLsHandler: (([URL]) -> Void)?
    var removeStashHandler: ((StashedFile) -> Void)?
    private var hoverTask: Task<Void, Never>?
    private var trackPreviewTask: Task<Void, Never>?
    private var idleHideTask: Task<Void, Never>?
    init() {
        if UserDefaults.standard.object(forKey: DefaultsKey.verticalOffset) != nil {
            verticalOffset = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.verticalOffset))
        } else {
            verticalOffset = 0
        }
    }

    var presentation: Presentation {
        if isPinnedExpanded || isHoverExpanded || latestEvent != nil || isDropTargeted {
            return .expanded
        }

        if isTrackPreviewActive, nowPlaying != nil {
            return .trackPreview
        }

        if nowPlaying != nil {
            return .media
        }

        return .idle
    }

    var currentMedia: NowPlayingItem {
        nowPlaying ?? .placeholder()
    }

    var targetSize: CGSize {
        let stashHeight: CGFloat = stashedFiles.isEmpty ? 0 : 56
        let peeking = isPeeking && !isPinnedExpanded && !isHoverExpanded && latestEvent == nil

        switch presentation {
        case .idle:
            if peeking {
                return CGSize(width: notchSize.width + 100, height: notchSize.height + 8)
            }
            return CGSize(width: notchSize.width + 90, height: notchSize.height + 0)
        case .media:
            if peeking {
                return CGSize(width: notchSize.width + 100, height: notchSize.height + 8)
            }
            return CGSize(width: notchSize.width + 90, height: notchSize.height + 0)
        case .trackPreview:
            return CGSize(
                width: max(notchSize.width + 120, 380),
                height: notchSize.height + 40
            )
        case .expanded:
            return CGSize(
                width: max(notchSize.width + 200, 380),
                height: notchSize.height + 80 + stashHeight
            )
        }
    }

    var maxIslandSize: CGSize {
        CGSize(width: max(notchSize.width + 240, 480), height: notchSize.height + 160)
    }

    func setHoveringRaw(_ hovering: Bool) {
        guard isHoverHovering != hovering else { return }
        isHoverHovering = hovering
        hoverTask?.cancel()

        if hovering {
            isPeeking = true
        } else {
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.isPeeking = false
                if self.isPinnedExpanded {
                    self.isPinnedExpanded = false
                }
            }
        }
    }

    func setHovering(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            guard nowPlaying != nil || latestEvent != nil else {
                return
            }

            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                self?.isHoverExpanded = true
            }
        } else {
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                self?.isHoverExpanded = false
            }
        }
    }

    func togglePinnedExpanded() {
        isPinnedExpanded.toggle()
    }

    func collapse() {
        isPinnedExpanded = false
        isHoverExpanded = false
        latestEvent = nil
    }

    func adjustVerticalOffset(by delta: CGFloat) {
        verticalOffset += delta
        UserDefaults.standard.set(verticalOffset, forKey: DefaultsKey.verticalOffset)
    }

    func resetVerticalOffset() {
        verticalOffset = 0
        UserDefaults.standard.removeObject(forKey: DefaultsKey.verticalOffset)
    }

    func updateNowPlaying(_ item: NowPlayingItem?) {
        guard let incoming = item else {
            nowPlaying = nil
            isHoverExpanded = false
            return
        }

        guard let current = nowPlaying, current.id == incoming.id else {
            let hadPrevious = nowPlaying != nil
            nowPlaying = incoming
            if hadPrevious {
                triggerTrackPreview()
            }
            scheduleIdleHide(isPlaying: incoming.isPlaying)
            return
        }

        let localElapsedNow = current.elapsed
        let incomingElapsedNow = incoming.elapsed
        let drift = abs(localElapsedNow - incomingElapsedNow)
        let isStateChange = current.isPlaying != incoming.isPlaying
        let incomingHasReliableElapsed = incoming.baseElapsed > 0.5 || incomingElapsedNow > 0.5
        let isLargeSeek = incomingHasReliableElapsed && drift > 4

        let nextBaseElapsed: TimeInterval
        let nextBaseDate: Date
        let nextIsPlaying: Bool

        if isStateChange {
            nextBaseElapsed = incomingHasReliableElapsed ? incoming.baseElapsed : localElapsedNow
            nextBaseDate = Date()
            nextIsPlaying = incoming.isPlaying
        } else if isLargeSeek {
            nextBaseElapsed = incoming.baseElapsed
            nextBaseDate = incoming.baseDate
            nextIsPlaying = current.isPlaying
        } else {
            nextBaseElapsed = current.baseElapsed
            nextBaseDate = current.baseDate
            nextIsPlaying = current.isPlaying
        }

        nowPlaying = NowPlayingItem(
            id: incoming.id,
            title: incoming.title.isEmpty ? current.title : incoming.title,
            artist: incoming.artist.isEmpty ? current.artist : incoming.artist,
            album: incoming.album.isEmpty ? current.album : incoming.album,
            duration: incoming.duration > 0 ? incoming.duration : current.duration,
            baseElapsed: nextBaseElapsed,
            baseDate: nextBaseDate,
            isPlaying: nextIsPlaying,
            artwork: incoming.artwork ?? current.artwork,
            accentColor: incoming.accentColor ?? current.accentColor,
            palette: incoming.palette.isEmpty ? current.palette : incoming.palette,
            sourceName: incoming.sourceName
        )

        scheduleIdleHide(isPlaying: nextIsPlaying)
    }

    private func scheduleIdleHide(isPlaying: Bool) {
        idleHideTask?.cancel()
        guard !isPlaying else { return }
        idleHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if let np = self.nowPlaying, !np.isPlaying {
                self.nowPlaying = nil
                self.isHoverExpanded = false
                self.isTrackPreviewActive = false
            }
        }
    }

    func ingestURLs(_ urls: [URL]) {
        ingestURLsHandler?(urls)
    }

    func removeStashed(_ file: StashedFile) {
        removeStashHandler?(file)
    }

    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
    }

    func updateNotchSize(_ size: CGSize) {
        guard size != notchSize else { return }
        notchSize = size
    }

    func pushEvent(title: String, detail: String, symbolName: String) {
        latestEvent = NotchEvent(
            title: title,
            detail: detail,
            symbolName: symbolName,
            date: Date()
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.clearExpiredEvent()
        }
    }

    func clearExpiredEvent() {
        latestEvent = nil
    }

    private func triggerTrackPreview() {
        trackPreviewTask?.cancel()
        isTrackPreviewActive = true
        trackPreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            self?.isTrackPreviewActive = false
        }
    }

    func send(_ command: MediaCommand) {
        applyLocalMediaCommand(command)
        mediaCommandHandler?(command)
    }

    private func applyLocalMediaCommand(_ command: MediaCommand) {
        guard command == .previousTrack, let current = nowPlaying else {
            return
        }

        nowPlaying = NowPlayingItem(
            id: current.id,
            title: current.title,
            artist: current.artist,
            album: current.album,
            duration: current.duration,
            baseElapsed: 0,
            baseDate: Date(),
            isPlaying: current.isPlaying,
            artwork: current.artwork,
            accentColor: current.accentColor,
            palette: current.palette,
            sourceName: current.sourceName
        )
    }

}
