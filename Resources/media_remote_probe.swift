import Darwin
import Foundation

typealias GetNowPlayingInfoFunction = @convention(c) (
    DispatchQueue,
    @escaping @convention(block) (CFDictionary?) -> Void
) -> Void

struct ProbeItem: Encodable {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let elapsed: Double
    let isPlaying: Bool
    let artworkPath: String?
}

func value<T>(_ key: String, in dictionary: [AnyHashable: Any]) -> T? {
    dictionary.first { String(describing: $0.key) == key }?.value as? T
}

func doubleValue(_ key: String, in dictionary: [AnyHashable: Any]) -> Double {
    if let number: NSNumber = value(key, in: dictionary) {
        return number.doubleValue
    }

    if let double: Double = value(key, in: dictionary) {
        return double
    }

    return 0
}

let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(frameworkPath, RTLD_NOW),
      let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
    exit(2)
}

let getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfoFunction.self)
let semaphore = DispatchSemaphore(value: 0)
var output: ProbeItem?

getNowPlayingInfo(.global(qos: .userInitiated)) { info in
    defer { semaphore.signal() }

    guard let dictionary = info as? [AnyHashable: Any],
          let title: String = value("kMRMediaRemoteNowPlayingInfoTitle", in: dictionary),
          !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }

    let artist: String = value("kMRMediaRemoteNowPlayingInfoArtist", in: dictionary) ?? ""
    let album: String = value("kMRMediaRemoteNowPlayingInfoAlbum", in: dictionary) ?? ""
    let artworkData: Data? = value("kMRMediaRemoteNowPlayingInfoArtworkData", in: dictionary)
    let artworkIdentifier: String = value("kMRMediaRemoteNowPlayingInfoArtworkIdentifier", in: dictionary) ?? title
    let playbackRate = doubleValue("kMRMediaRemoteNowPlayingInfoPlaybackRate", in: dictionary)
    let artworkPath = artworkData.flatMap { data -> String? in
        let safeIdentifier = artworkIdentifier
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: "/tmp/notchapp-artwork-\(safeIdentifier).jpg")
        try? data.write(to: url, options: .atomic)
        return url.path
    }

    output = ProbeItem(
        title: title,
        artist: artist,
        album: album,
        duration: doubleValue("kMRMediaRemoteNowPlayingInfoDuration", in: dictionary),
        elapsed: doubleValue("kMRMediaRemoteNowPlayingInfoElapsedTime", in: dictionary),
        isPlaying: playbackRate > 0,
        artworkPath: artworkPath
    )
}

guard semaphore.wait(timeout: .now() + 2) == .success,
      let output,
      let data = try? JSONEncoder().encode(output) else {
    exit(1)
}

FileHandle.standardOutput.write(data)
