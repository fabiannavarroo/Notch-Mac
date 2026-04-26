import SwiftUI
import UniformTypeIdentifiers

struct NotchIslandView: View {
    @ObservedObject var appState: NotchAppState

    var body: some View {
        let isExpanded = appState.presentation == .expanded
        let isPreview = appState.presentation == .trackPreview
        let bottomRadius: CGFloat = isExpanded ? 20 : (isPreview ? 16 : 12)
        let target = appState.targetSize

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                NotchChromeShape(bottomCornerRadius: bottomRadius)
                    .fill(Color.black)
                    .overlay(
                        NotchChromeShape(bottomCornerRadius: bottomRadius)
                            .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                    )

                content(isExpanded: isExpanded)
            }
            .frame(width: target.width, height: target.height)
            .clipShape(NotchChromeShape(bottomCornerRadius: bottomRadius))
            .shadow(color: .black.opacity(isExpanded || isPreview ? 0.4 : 0), radius: isExpanded || isPreview ? 18 : 0, x: 0, y: 10)
            .contentShape(NotchChromeShape(bottomCornerRadius: bottomRadius))
            .onTapGesture {
                appState.togglePinnedExpanded()
            }
            .onDrop(of: [.fileURL], delegate: StashDropDelegate(appState: appState))
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: target)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: appState.presentation)
            .animation(.easeInOut(duration: 0.22), value: appState.currentMedia.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(isExpanded: Bool) -> some View {
        if isExpanded {
            ExpandedIslandView(appState: appState)
                .padding(.top, appState.notchSize.height + 2)
                .transition(.opacity)
        } else if appState.presentation == .trackPreview {
            TrackPreviewBar(
                item: appState.currentMedia,
                notchSize: appState.notchSize
            )
            .transition(.opacity)
        } else if appState.presentation == .media {
            MediaIslandView(item: appState.currentMedia, notchWidth: appState.notchSize.width)
                .transition(.opacity)
        } else {
            Color.clear
        }
    }
}

private struct NotchChromeShape: Shape {
    var bottomCornerRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(bottomCornerRadius, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct MediaIslandView: View {
    let item: NowPlayingItem
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(item: item, size: 22)
                .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            EqualizerGlyph(
                isPlaying: item.isPlaying,
                palette: item.palette,
                accent: SwiftUI.Color(item.accentColor ?? NSColor(calibratedWhite: 0.85, alpha: 1))
            )
            .frame(width: 22, height: 18)
            .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ExpandedIslandView: View {
    @ObservedObject var appState: NotchAppState

    var body: some View {
        let item = appState.currentMedia
        let accent = SwiftUI.Color(item.accentColor ?? NSColor(calibratedWhite: 0.82, alpha: 1))

        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ArtworkView(item: item, size: 38)

                VStack(alignment: .leading, spacing: 1) {
                    if let event = appState.latestEvent {
                        EventStrip(event: event)
                    }

                    Text(item.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(item.artist)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    PlaybackProgress(item: item, accent: accent) { target in
                        appState.send(.seek(to: target))
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                EqualizerGlyph(isPlaying: item.isPlaying, palette: item.palette, accent: accent)
                    .frame(width: 18, height: 14)
            }

            HStack(spacing: 0) {
                MediaButton(systemName: "shuffle", tone: .secondary) {}
                Spacer()
                MediaButton(systemName: "backward.fill", tone: .primary) {
                    appState.send(.previousTrack)
                }
                Spacer()
                MediaButton(systemName: item.isPlaying ? "pause.fill" : "play.fill", tone: .hero) {
                    appState.send(.togglePlayPause)
                }
                Spacer()
                MediaButton(systemName: "forward.fill", tone: .primary) {
                    appState.send(.nextTrack)
                }
                Spacer()
                MediaButton(systemName: "airpodspro", tone: .secondary) {}
            }
            .padding(.horizontal, 4)
            .frame(height: 28)

            if !appState.stashedFiles.isEmpty {
                StashTrayView(
                    files: appState.stashedFiles,
                    onRemove: { appState.removeStashed($0) }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

private struct StashTrayView: View {
    let files: [StashedFile]
    let onRemove: (StashedFile) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files) { file in
                    StashThumbnail(file: file, onRemove: onRemove)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 44)
    }
}

private struct StashThumbnail: View {
    let file: StashedFile
    let onRemove: (StashedFile) -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = file.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .scaleEffect(isHovering ? 1.06 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.4 : 0), radius: 6, y: 3)

            if isHovering {
                Button(action: { onRemove(file) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.black.opacity(0.85)))
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(file.url)
        }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(file.url) }
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Divider()
            Button("Quitar", role: .destructive) { onRemove(file) }
        }
        .help(file.name)
        .onDrag {
            NSItemProvider(object: file.url as NSURL)
        }
    }
}

private struct StashDropDelegate: DropDelegate {
    let appState: NotchAppState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        Task { @MainActor in
            appState.setDropTargeted(true)
        }
    }

    func dropExited(info: DropInfo) {
        Task { @MainActor in
            appState.setDropTargeted(false)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = URLCollector()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    collector.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = collector.snapshot()
            Task { @MainActor in
                appState.setDropTargeted(false)
                appState.ingestURLs(urls)
            }
        }

        return true
    }
}

private final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func append(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        urls.append(url)
    }

    func snapshot() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return urls
    }
}

private struct PlaybackProgress: View {
    let item: NowPlayingItem
    let accent: SwiftUI.Color
    let onScrub: (TimeInterval) -> Void

    @State private var scrubProgress: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let progress = scrubProgress ?? item.progress
            let liveElapsed = item.duration > 0 ? progress * item.duration : item.elapsed
            let remaining = max(item.duration - liveElapsed, 0)

            HStack(spacing: 8) {
                Text(timeString(liveElapsed))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.16))

                        Capsule()
                            .fill(accent)
                            .frame(width: max(3, proxy.size.width * progress))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let raw = value.location.x / proxy.size.width
                                scrubProgress = min(max(raw, 0), 1)
                            }
                            .onEnded { _ in
                                if let p = scrubProgress, item.duration > 0 {
                                    onScrub(p * item.duration)
                                }
                                scrubProgress = nil
                            }
                    )
                }
                .frame(height: 3)

                Text("-" + timeString(remaining))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }
        }
    }

    private func timeString(_ value: TimeInterval) -> String {
        let seconds = max(Int(value.rounded()), 0)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

private struct EventStrip: View {
    let event: NotchEvent

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: event.symbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text(event.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Text(event.detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

private struct ArtworkView: View {
    let item: NowPlayingItem
    let size: CGFloat

    var body: some View {
        ZStack {
            if let artwork = item.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(.white.opacity(0.08))

                Image(systemName: item.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct MediaButton: View {
    enum Tone {
        case primary
        case secondary
        case hero
    }

    let systemName: String
    var tone: Tone = .primary
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.12 : 0))

                Image(systemName: systemName)
                    .font(.system(size: fontSize, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(foreground.opacity(isHovering ? 1 : baseOpacity))
            }
            .frame(width: frameSize, height: frameSize)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.88 : (isHovering ? 1.06 : 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                        isPressed = false
                    }
                }
        )
    }

    private var fontSize: CGFloat {
        switch tone {
        case .primary: return 15
        case .secondary: return 11
        case .hero: return 18
        }
    }

    private var frameSize: CGFloat {
        switch tone {
        case .primary: return 26
        case .secondary: return 22
        case .hero: return 28
        }
    }

    private var foreground: SwiftUI.Color {
        .white
    }

    private var baseOpacity: Double {
        switch tone {
        case .primary, .hero: return 1
        case .secondary: return 0.55
        }
    }
}

private struct EqualizerGlyph: View {
    let isPlaying: Bool
    let palette: [NSColor]
    let accent: SwiftUI.Color

    private struct BarConfig {
        let speed: Double
        let phase: Double
        let driftSpeed: Double
        let driftPhase: Double
        let amplitude: Double
        let baseHeight: CGFloat
    }

    private static let barConfigs: [BarConfig] = [
        .init(speed: 4.7, phase: 0.0,  driftSpeed: 1.31, driftPhase: 0.7,  amplitude: 0.95, baseHeight: 9),
        .init(speed: 6.3, phase: 2.1,  driftSpeed: 0.97, driftPhase: 1.9,  amplitude: 1.10, baseHeight: 14),
        .init(speed: 3.9, phase: 0.9,  driftSpeed: 1.71, driftPhase: 0.3,  amplitude: 0.85, baseHeight: 11),
        .init(speed: 7.2, phase: 3.4,  driftSpeed: 0.83, driftPhase: 2.6,  amplitude: 1.00, baseHeight: 8)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(barColor(index: index))
                        .frame(width: 2.6, height: barHeight(index: index, time: t))
                }
            }
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return 5 }
        let cfg = Self.barConfigs[index]
        let fast = time * cfg.speed + cfg.phase
        let drift = time * cfg.driftSpeed + cfg.driftPhase
        let noise = (sin(fast)
                     + 0.7 * sin(fast * 1.71 + 0.4)
                     + 0.5 * sin(fast * 2.93 + 1.2)
                     + 0.4 * sin(drift * 1.13)) / 2.6
        let normalized = (noise + 1) / 2
        return cfg.baseHeight * (0.25 + 0.75 * cfg.amplitude * CGFloat(normalized))
    }

    private func barColor(index: Int) -> SwiftUI.Color {
        guard isPlaying else { return accent.opacity(0.35) }
        if !palette.isEmpty {
            let nsColor = palette[index % palette.count]
            return SwiftUI.Color(nsColor)
        }
        let opacities: [Double] = [1.0, 0.85, 0.7, 0.55]
        return accent.opacity(opacities[index])
    }
}

private struct TrackPreviewBar: View {
    let item: NowPlayingItem
    let notchSize: CGSize

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ArtworkView(item: item, size: 32)
                    .padding(.leading, 8)

                Spacer(minLength: notchSize.width - 16)

                EqualizerGlyph(
                    isPlaying: item.isPlaying,
                    palette: item.palette,
                    accent: SwiftUI.Color(item.accentColor ?? NSColor(calibratedWhite: 0.85, alpha: 1))
                )
                .frame(width: 28, height: 22)
                .padding(.trailing, 12)
            }
            .padding(.top, 2)

            VStack {
                Spacer().frame(height: notchSize.height + 6)
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))

                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))

                    Text(item.artist)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
