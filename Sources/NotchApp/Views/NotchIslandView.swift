import SwiftUI
import UniformTypeIdentifiers

struct NotchIslandView: View {
    @ObservedObject var appState: NotchAppState

    var body: some View {
        let isExpanded = appState.presentation == .expanded
        let bottomRadius: CGFloat = isExpanded ? 20 : 12

        ZStack(alignment: .top) {
            NotchChromeShape(bottomCornerRadius: bottomRadius)
                .fill(Color.black)
                .overlay(
                    NotchChromeShape(bottomCornerRadius: bottomRadius)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(isExpanded ? 0.4 : 0), radius: isExpanded ? 18 : 0, x: 0, y: 10)

            content(isExpanded: isExpanded)
                .clipShape(NotchChromeShape(bottomCornerRadius: bottomRadius))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(NotchChromeShape(bottomCornerRadius: bottomRadius))
        .onTapGesture {
            appState.togglePinnedExpanded()
        }
        .onDrop(of: [.fileURL], delegate: StashDropDelegate(appState: appState))
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: appState.presentation)
        .animation(.easeInOut(duration: 0.2), value: appState.currentMedia.id)
    }

    @ViewBuilder
    private func content(isExpanded: Bool) -> some View {
        if isExpanded {
            ExpandedIslandView(appState: appState)
                .padding(.top, appState.notchSize.height + 2)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .transition(.identity)
        } else if appState.presentation == .media || appState.presentation == .trackPreview {
            MediaIslandView(item: appState.currentMedia, notchWidth: appState.notchSize.width)
                .transition(mediaContentTransition)
        } else {
            Color.clear
        }
    }

    private var mediaContentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.99, anchor: .top))
        )
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

                    PlaybackProgress(item: item, accent: accent)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)

                EqualizerGlyph(isPlaying: item.isPlaying, accent: accent)
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let elapsed = item.elapsed
            let remaining = max(item.duration - elapsed, 0)
            let progress = item.progress

            HStack(spacing: 8) {
                Text(timeString(elapsed))
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
    let accent: SwiftUI.Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(barColor(index: index))
                        .frame(width: 2.6, height: barHeight(index: index, time: t))
                        .animation(.linear(duration: 0.08), value: t)
                }
            }
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        let base: [CGFloat] = [10, 16, 9, 6]
        guard isPlaying else { return 5 }
        let phase = time * 4.5 + Double(index) * 1.3
        let wave = (sin(phase) + 1) / 2
        return base[index] * (0.5 + 0.5 * CGFloat(wave))
    }

    private func barColor(index: Int) -> SwiftUI.Color {
        let opacities: [Double] = [1.0, 0.85, 0.7, 0.55]
        return accent.opacity(isPlaying ? opacities[index] : 0.35)
    }
}
