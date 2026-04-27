import AppKit
import Foundation

@MainActor
final class ExternalNotificationBridge {
    private let appState: NotchAppState
    private var screencapWatcher: ScreencapWatcher?

    init(appState: NotchAppState) {
        self.appState = appState
    }

    func start() {
        // Screencap watcher off by default; enable later via prefs.
    }
}

@MainActor
private final class ScreencapWatcher {
    private let onCapture: (URL) -> Void
    private var observers: [NSObjectProtocol] = []
    private let query = NSMetadataQuery()
    private var seen: Set<URL> = []

    init(onCapture: @escaping (URL) -> Void) {
        self.onCapture = onCapture
    }

    func start() {
        let desktop = (NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first ?? "").nilIfEmpty()
        let pictures = (NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true).first ?? "").nilIfEmpty()
        let scopes = [desktop, pictures].compactMap { $0 }.map(URL.init(fileURLWithPath:))

        query.searchScopes = scopes
        query.predicate = NSPredicate(format: "%K == 'public.screencapture'", NSMetadataItemContentTypeKey)

        let center = NotificationCenter.default
        let initialToken = center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.seedExisting() }
        }
        let updateToken = center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] note in
            let paths: [String] = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem])?
                .compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String } ?? []
            Task { @MainActor in self?.handlePaths(paths) }
        }

        observers = [initialToken, updateToken]
        query.start()
    }

    private func seedExisting() {
        let items = (0..<query.resultCount).compactMap { query.result(at: $0) as? NSMetadataItem }
        for item in items {
            if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                seen.insert(URL(fileURLWithPath: path))
            }
        }
    }

    private func handlePaths(_ paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard !seen.contains(url) else { continue }
            seen.insert(url)
            onCapture(url)
        }
    }
}

private extension String {
    func nilIfEmpty() -> String? { isEmpty ? nil : self }
}
