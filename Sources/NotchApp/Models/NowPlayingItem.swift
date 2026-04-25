import AppKit
import Foundation

struct NowPlayingItem: Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let baseElapsed: TimeInterval
    let baseDate: Date
    let isPlaying: Bool
    let artwork: NSImage?
    let accentColor: NSColor?
    let sourceName: String

    var elapsed: TimeInterval {
        let raw: TimeInterval
        if isPlaying {
            raw = baseElapsed + Date().timeIntervalSince(baseDate)
        } else {
            raw = baseElapsed
        }
        if duration > 0 {
            return max(0, min(raw, duration))
        }
        return max(0, raw)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    static func placeholder() -> NowPlayingItem {
        NowPlayingItem(
            id: "placeholder",
            title: "Nada sonando",
            artist: "Listo para detectar audio",
            album: "",
            duration: 1,
            baseElapsed: 0,
            baseDate: Date(),
            isPlaying: false,
            artwork: nil,
            accentColor: nil,
            sourceName: "NotchApp"
        )
    }
}

extension NowPlayingItem: Equatable {
    static func == (lhs: NowPlayingItem, rhs: NowPlayingItem) -> Bool {
        lhs.id == rhs.id
            && lhs.isPlaying == rhs.isPlaying
            && abs(lhs.duration - rhs.duration) < 0.5
            && abs(lhs.baseElapsed - rhs.baseElapsed) < 0.5
            && lhs.baseDate == rhs.baseDate
    }
}

extension NowPlayingItem {
    static func stableID(title: String, artist: String, contentItemID: String?) -> String {
        if let contentItemID, !contentItemID.isEmpty {
            return contentItemID
        }
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedTitle)|\(normalizedArtist)"
    }

    init?(mediaRemoteInfo info: CFDictionary?) {
        guard let dictionary = info as? [String: Any] else {
            return nil
        }

        let title = dictionary["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let artist = dictionary["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = dictionary["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = dictionary["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? 0
        let elapsed = dictionary["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval ?? 0
        let rate = dictionary["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        let timestamp = dictionary["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date()
        let artworkData = dictionary["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        let artwork = artworkData.flatMap(NSImage.init(data:))
        let contentItemID = dictionary["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String

        self.init(
            id: NowPlayingItem.stableID(title: title, artist: artist, contentItemID: contentItemID),
            title: title,
            artist: artist.isEmpty ? "Reproduciendo" : artist,
            album: album,
            duration: duration,
            baseElapsed: elapsed,
            baseDate: timestamp,
            isPlaying: rate > 0,
            artwork: artwork,
            accentColor: artwork?.dominantAccentColor(),
            sourceName: "Sistema"
        )
    }
}

extension NSImage {
    func dominantAccentColor() -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = 48
        let height = 48
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct Bucket {
            var rSum = 0.0
            var gSum = 0.0
            var bSum = 0.0
            var sSum = 0.0
            var count = 0
        }

        let hueBuckets = 18
        var buckets = [Bucket](repeating: Bucket(), count: hueBuckets)

        var fallbackR = 0.0, fallbackG = 0.0, fallbackB = 0.0
        var fallbackCount = 0

        for i in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let delta = maxC - minC
            let saturation = maxC == 0 ? 0 : delta / maxC
            let brightness = maxC

            fallbackR += r
            fallbackG += g
            fallbackB += b
            fallbackCount += 1

            if brightness < 0.22 || brightness > 0.96 || saturation < 0.32 { continue }

            var hue: Double = 0
            if delta > 0 {
                if maxC == r {
                    hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                } else if maxC == g {
                    hue = (b - r) / delta + 2
                } else {
                    hue = (r - g) / delta + 4
                }
                hue *= 60
                if hue < 0 { hue += 360 }
            }

            let bucketIndex = min(hueBuckets - 1, Int(hue / (360.0 / Double(hueBuckets))))
            buckets[bucketIndex].rSum += r
            buckets[bucketIndex].gSum += g
            buckets[bucketIndex].bSum += b
            buckets[bucketIndex].sSum += saturation
            buckets[bucketIndex].count += 1
        }

        let topBucket = buckets.enumerated().max { lhs, rhs in
            let lhsScore = Double(lhs.element.count) * (1 + (lhs.element.count > 0 ? lhs.element.sSum / Double(lhs.element.count) : 0))
            let rhsScore = Double(rhs.element.count) * (1 + (rhs.element.count > 0 ? rhs.element.sSum / Double(rhs.element.count) : 0))
            return lhsScore < rhsScore
        }

        if let chosen = topBucket?.element, chosen.count > 0 {
            let n = Double(chosen.count)
            return Self.boost(red: chosen.rSum / n, green: chosen.gSum / n, blue: chosen.bSum / n)
        }

        guard fallbackCount > 0 else { return nil }
        let n = Double(fallbackCount)
        return Self.boost(red: fallbackR / n, green: fallbackG / n, blue: fallbackB / n)
    }

    private static func boost(red: Double, green: Double, blue: Double) -> NSColor {
        let base = NSColor(red: red, green: green, blue: blue, alpha: 1)
            .usingColorSpace(.sRGB) ?? NSColor(red: red, green: green, blue: blue, alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, brightness: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &brightness, alpha: &a)

        let boostedSaturation = min(0.85, max(s, 0.45))
        let boostedBrightness = min(0.88, max(brightness, 0.6))
        return NSColor(hue: h, saturation: boostedSaturation, brightness: boostedBrightness, alpha: 1)
    }
}
