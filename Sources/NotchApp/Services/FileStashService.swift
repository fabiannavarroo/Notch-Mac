import AppKit
import Foundation
import QuickLookThumbnailing

@MainActor
final class FileStashService {
    private let appState: NotchAppState
    private let stashDir: URL

    init(appState: NotchAppState) {
        self.appState = appState
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        stashDir = support.appendingPathComponent("NotchApp/Stash", isDirectory: true)
        try? FileManager.default.createDirectory(at: stashDir, withIntermediateDirectories: true)

        appState.ingestURLsHandler = { [weak self] urls in
            self?.ingest(urls)
        }
        appState.removeStashHandler = { [weak self] file in
            self?.remove(file)
        }

        purgeStashOnLaunch()
    }

    private func purgeStashOnLaunch() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: stashDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in items {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func ingest(_ urls: [URL]) {
        for source in urls {
            let id = UUID()
            let dest = stashDir.appendingPathComponent("\(id.uuidString)__\(source.lastPathComponent)")

            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                continue
            }

            generateThumbnail(for: dest, name: source.lastPathComponent, id: id)
        }
    }

    func remove(_ file: StashedFile) {
        appState.stashedFiles.removeAll { $0.id == file.id }
        appState.selectedStashIDs.remove(file.id)
        // Retrasa el borrado para que destinos lentos (WhatsApp, Mail o subidas)
        // puedan seguir leyendo el archivo aunque desaparezca de la interfaz.
        scheduleDiskCleanup(at: file.url, after: 30)
    }

    private func scheduleDiskCleanup(at url: URL, after seconds: TimeInterval) {
        Task.detached {
            try? await Task.sleep(for: .seconds(seconds))
            try? FileManager.default.removeItem(at: url)
        }
    }

    func clearAll() {
        for file in appState.stashedFiles {
            try? FileManager.default.removeItem(at: file.url)
        }
        appState.stashedFiles.removeAll()
    }

    private func loadExisting() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: stashDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let sorted = items.sorted { (lhs, rhs) in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        for url in sorted {
            let id = UUID()
            let parts = url.lastPathComponent.components(separatedBy: "__")
            let name = parts.count > 1 ? parts.dropFirst().joined(separator: "__") : url.lastPathComponent
            generateThumbnail(for: url, name: name, id: id)
        }
    }

    private func generateThumbnail(for url: URL, name: String, id: UUID) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image: NSImage?
            if let cgImage = representation?.cgImage {
                image = NSImage(cgImage: cgImage, size: CGSize(width: 48, height: 48))
            } else {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }

            Task { @MainActor in
                guard let self else { return }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date()
                let file = StashedFile(
                    id: id,
                    url: url,
                    name: name,
                    thumbnail: image,
                    dateAdded: modified
                )
                self.appState.stashedFiles.append(file)
            }
        }
    }
}
