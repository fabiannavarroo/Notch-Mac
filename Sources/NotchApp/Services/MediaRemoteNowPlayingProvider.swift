import AppKit
import Darwin
import Foundation

@MainActor
final class MediaRemoteNowPlayingProvider {
    private struct ProbeItem: Decodable {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let elapsed: Double
        let isPlaying: Bool
        let artworkPath: String?
    }

    private typealias GetNowPlayingInfoFunction = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void

    private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Void
    private typealias RegisterNotificationsFunction = @convention(c) (DispatchQueue) -> Void

    private let appState: NotchAppState
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetNowPlayingInfoFunction?
    private var sendCommand: SendCommandFunction?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(appState: NotchAppState) {
        self.appState = appState
        loadMediaRemote()

        appState.mediaCommandHandler = { [weak self] command in
            self?.send(command)
        }
    }

    func start() {
        registerForNotifications()
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            return
        }

        mediaRemoteHandle = handle

        if let getSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(getSymbol, to: GetNowPlayingInfoFunction.self)
        }

        if let commandSymbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(commandSymbol, to: SendCommandFunction.self)
        }
    }

    private func registerForNotifications() {
        if let handle = mediaRemoteHandle,
           let registerSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let register = unsafeBitCast(registerSym, to: RegisterNotificationsFunction.self)
            register(.main)
        }

        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]

        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.poll()
                }
            }
            observers.append(observer)
        }
    }

    private func poll() {
        if let getNowPlayingInfo {
            getNowPlayingInfo(.global(qos: .userInitiated)) { [weak self] info in
                let item = NowPlayingItem(mediaRemoteInfo: info)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let item {
                        let enriched = self.enrichWithAppleScript(item)
                        self.appState.updateNowPlaying(enriched)
                    } else if let fallback = self.pollUsingHelper() {
                        let enriched = self.enrichWithAppleScript(fallback)
                        self.appState.updateNowPlaying(enriched)
                    } else {
                        self.appState.updateNowPlaying(nil)
                    }
                }
            }
            return
        }

        if let helperItem = pollUsingHelper() {
            let enriched = enrichWithAppleScript(helperItem)
            appState.updateNowPlaying(enriched)
        } else {
            appState.updateNowPlaying(nil)
        }
    }

    private func enrichWithAppleScript(_ item: NowPlayingItem) -> NowPlayingItem {
        let snapshots = ["Spotify", "Music"].compactMap { appleScriptSnapshot(app: $0) }
        guard let snapshot = snapshots.first(where: \.isPlaying) ?? snapshots.first else {
            return item
        }

        let snapshotID = NowPlayingItem.stableID(
            title: snapshot.title,
            artist: snapshot.artist,
            contentItemID: nil
        )
        let itemID = NowPlayingItem.stableID(
            title: item.title,
            artist: item.artist,
            contentItemID: nil
        )
        let shouldPreferSnapshot = snapshot.isPlaying || item.baseElapsed < 0.5 || item.duration < 0.5
        guard shouldPreferSnapshot else { return item }

        let keepsSameTrack = snapshotID == itemID
        return NowPlayingItem(
            id: snapshotID,
            title: snapshot.title.isEmpty ? item.title : snapshot.title,
            artist: snapshot.artist.isEmpty ? item.artist : snapshot.artist,
            album: snapshot.album.isEmpty ? item.album : snapshot.album,
            duration: snapshot.duration > 0 ? snapshot.duration : item.duration,
            baseElapsed: snapshot.elapsed > 0 ? snapshot.elapsed : item.baseElapsed,
            baseDate: Date(),
            isPlaying: snapshot.isPlaying,
            artwork: keepsSameTrack ? item.artwork : nil,
            accentColor: keepsSameTrack ? item.accentColor : nil,
            sourceName: snapshot.sourceName
        )
    }

    private struct PlayerSnapshot {
        let sourceName: String
        let title: String
        let artist: String
        let album: String
        let elapsed: Double
        let duration: Double
        let isPlaying: Bool
    }

    private func appleScriptSnapshot(app: String) -> PlayerSnapshot? {
        let source = """
        if application "\(app)" is running then
            tell application "\(app)"
                try
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set ps to player state as text
                    set pp to player position
                    set dur to 0
                    try
                        set dur to duration of current track
                    end try
                    return trackName & "|" & trackArtist & "|" & trackAlbum & "|" & (pp as text) & "|" & (dur as text) & "|" & ps
                on error
                    return ""
                end try
            end tell
        else
            return ""
        end if
        """

        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)

        guard let stringValue = result?.stringValue, !stringValue.isEmpty else {
            return nil
        }

        let parts = stringValue.components(separatedBy: "|")
        guard parts.count >= 6 else { return nil }

        let title = parts[0]
        let artist = parts[1]
        let album = parts[2]
        let elapsed = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let rawDuration = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let duration = app == "Spotify" ? rawDuration / 1000 : rawDuration
        let stateText = parts[5].lowercased()
        let isPlaying = stateText.contains("playing")

        guard elapsed > 0 || duration > 0 else { return nil }

        return PlayerSnapshot(
            sourceName: app,
            title: title,
            artist: artist,
            album: album,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func send(_ command: MediaCommand) {
        guard let sendCommand else {
            return
        }

        let mediaRemoteCommand: Int32
        switch command {
        case .previousTrack:
            mediaRemoteCommand = 5
        case .togglePlayPause:
            mediaRemoteCommand = 2
        case .nextTrack:
            mediaRemoteCommand = 4
        }

        sendCommand(mediaRemoteCommand, nil)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.poll()
        }
    }

    private func pollUsingHelper() -> NowPlayingItem? {
        guard let helperScriptURL else {
            return nil
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [helperScriptURL.path]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let probeItem = try? JSONDecoder().decode(ProbeItem.self, from: data) else {
            return nil
        }

        let artwork = probeItem.artworkPath
            .map(URL.init(fileURLWithPath:))
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(NSImage.init(data:))

        return NowPlayingItem(
            id: NowPlayingItem.stableID(
                title: probeItem.title,
                artist: probeItem.artist,
                contentItemID: nil
            ),
            title: probeItem.title,
            artist: probeItem.artist.isEmpty ? "Reproduciendo" : probeItem.artist,
            album: probeItem.album,
            duration: probeItem.duration,
            baseElapsed: probeItem.elapsed,
            baseDate: Date(),
            isPlaying: probeItem.isPlaying,
            artwork: artwork,
            accentColor: artwork?.dominantAccentColor(),
            sourceName: "Sistema"
        )
    }

    private var helperScriptURL: URL? {
        if let bundledURL = Bundle.main.url(forResource: "media_remote_probe", withExtension: "swift") {
            return bundledURL
        }

        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/media_remote_probe.swift")
        return FileManager.default.fileExists(atPath: localURL.path) ? localURL : nil
    }
}
