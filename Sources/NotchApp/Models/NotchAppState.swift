import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class NotchAppState: ObservableObject {
    private enum DefaultsKey {
        static let verticalOffset = "notch.verticalOffset"
        static let preferredScreenID = "notch.preferredScreenID"
    }

    enum Presentation: Equatable {
        case idle
        case media
        case trackPreview
        case fileTray
        case expanded
    }

    @Published var isIslandEnabled = true
    @Published var isHoverExpanded = false {
        didSet { resetAudioPanelIfCollapsed() }
    }
    @Published var isHoverHovering = false
    @Published var isPinnedExpanded = false {
        didSet { resetAudioPanelIfCollapsed() }
    }
    @Published var isPeeking = false
    @Published var nowPlaying: NowPlayingItem?
    @Published var latestEvent: NotchEvent?
    @Published var verticalOffset: CGFloat
    @Published var notchSize: CGSize = CGSize(width: 200, height: 32)
    @Published var stashedFiles: [StashedFile] = []
    @Published var isDropTargeted: Bool = false
    @Published var selectedStashIDs: Set<UUID> = []

    @Published var isTrackPreviewActive: Bool = false
    @Published var previousTrack: NowPlayingItem?
    @Published var isAudioPanelOpen: Bool = false

    @Published var launchAtLogin: Bool = LoginItemService.isEnabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            LoginItemService.setEnabled(launchAtLogin)
        }
    }

    @Published var preferredScreenID: UInt32? {
        didSet {
            guard preferredScreenID != oldValue else { return }
            if let id = preferredScreenID {
                UserDefaults.standard.set(Int(id), forKey: DefaultsKey.preferredScreenID)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredScreenID)
            }
        }
    }

    var mediaCommandHandler: ((MediaCommand) -> Void)?
    var ingestURLsHandler: (([URL]) -> Void)?
    var removeStashHandler: ((StashedFile) -> Void)?
    private var hoverTask: Task<Void, Never>?
    private var trackPreviewTask: Task<Void, Never>?
    private var idleHideTask: Task<Void, Never>?
    private var pendingPreviewTrackID: String?
    private var pendingPreviewTimeout: Task<Void, Never>?
    init() {
        if UserDefaults.standard.object(forKey: DefaultsKey.verticalOffset) != nil {
            verticalOffset = CGFloat(UserDefaults.standard.double(forKey: DefaultsKey.verticalOffset))
        } else {
            verticalOffset = 0
        }

        if let stored = UserDefaults.standard.object(forKey: DefaultsKey.preferredScreenID) as? Int {
            preferredScreenID = UInt32(stored)
        }
    }

    var presentation: Presentation {
        if isDropTargeted {
            return .fileTray
        }

        if !stashedFiles.isEmpty {
            return .fileTray
        }

        let userExpanding = isPinnedExpanded || isHoverExpanded

        if userExpanding || latestEvent != nil {
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

    var fileTrayExpanded: Bool {
        isDropTargeted
            || isPinnedExpanded
            || isHoverExpanded
            || isHoverHovering
            || !selectedStashIDs.isEmpty
    }

    var currentMedia: NowPlayingItem {
        nowPlaying ?? .placeholder()
    }

    var targetSize: CGSize {
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
        case .fileTray:
            if fileTrayExpanded {
                return CGSize(
                    width: max(notchSize.width + 220, 420),
                    height: notchSize.height + 90
                )
            }
            return CGSize(width: notchSize.width + 90, height: notchSize.height + 0)
        case .expanded:
            let extra: CGFloat = isAudioPanelOpen ? 36 : 0
            return CGSize(
                width: max(notchSize.width + 200, 380),
                height: notchSize.height + 80 + extra
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
        isAudioPanelOpen = false
    }

    private func resetAudioPanelIfCollapsed() {
        if !isPinnedExpanded && !isHoverExpanded {
            isAudioPanelOpen = false
        }
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
            previousTrack = nowPlaying
            nowPlaying = incoming
            if incoming.isPlaying {
                if incoming.artwork != nil {
                    triggerTrackPreview()
                } else {
                    pendingPreviewTrackID = incoming.id
                    pendingPreviewTimeout?.cancel()
                    pendingPreviewTimeout = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(1500))
                        guard !Task.isCancelled else { return }
                        guard let self, self.pendingPreviewTrackID == incoming.id else { return }
                        self.pendingPreviewTrackID = nil
                        self.triggerTrackPreview()
                    }
                }
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

        let mergedArtwork = incoming.artwork ?? current.artwork
        let artworkJustArrived = current.artwork == nil && mergedArtwork != nil

        nowPlaying = NowPlayingItem(
            id: incoming.id,
            title: incoming.title.isEmpty ? current.title : incoming.title,
            artist: incoming.artist.isEmpty ? current.artist : incoming.artist,
            album: incoming.album.isEmpty ? current.album : incoming.album,
            duration: incoming.duration > 0 ? incoming.duration : current.duration,
            baseElapsed: nextBaseElapsed,
            baseDate: nextBaseDate,
            isPlaying: nextIsPlaying,
            artwork: mergedArtwork,
            accentColor: incoming.accentColor ?? current.accentColor,
            palette: incoming.palette.isEmpty ? current.palette : incoming.palette,
            sourceName: incoming.sourceName
        )

        if artworkJustArrived,
           pendingPreviewTrackID == incoming.id {
            pendingPreviewTrackID = nil
            pendingPreviewTimeout?.cancel()
            triggerTrackPreview()
        }

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
        selectedStashIDs.remove(file.id)
        removeStashHandler?(file)
    }

    func toggleStashSelection(_ file: StashedFile, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedStashIDs.contains(file.id) {
                selectedStashIDs.remove(file.id)
            } else {
                selectedStashIDs.insert(file.id)
            }
        } else {
            if selectedStashIDs == [file.id] {
                selectedStashIDs.removeAll()
            } else {
                selectedStashIDs = [file.id]
            }
        }
    }

    func clearStashSelection() {
        selectedStashIDs.removeAll()
    }

    func filesForDrag(starting: StashedFile) -> [StashedFile] {
        if selectedStashIDs.contains(starting.id) {
            return stashedFiles.filter { selectedStashIDs.contains($0.id) }
        }
        return [starting]
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
            self?.previousTrack = nil
        }
    }

    func send(_ command: MediaCommand) {
        applyLocalMediaCommand(command)
        mediaCommandHandler?(command)
    }

    private func applyLocalMediaCommand(_ command: MediaCommand) {
        guard let current = nowPlaying else { return }

        switch command {
        case .previousTrack:
            nowPlaying = withElapsed(0, on: current)
        case .seek(let target):
            nowPlaying = withElapsed(max(0, target), on: current)
        case .togglePlayPause, .nextTrack:
            return
        }
    }

    private func withElapsed(_ elapsed: TimeInterval, on item: NowPlayingItem) -> NowPlayingItem {
        NowPlayingItem(
            id: item.id,
            title: item.title,
            artist: item.artist,
            album: item.album,
            duration: item.duration,
            baseElapsed: elapsed,
            baseDate: Date(),
            isPlaying: item.isPlaying,
            artwork: item.artwork,
            accentColor: item.accentColor,
            palette: item.palette,
            sourceName: item.sourceName
        )
    }

}
