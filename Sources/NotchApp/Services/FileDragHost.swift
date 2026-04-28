import AppKit
import SwiftUI

@MainActor
final class FileItemDragCoordinator: NSObject, NSDraggingSource {
    var getDragFiles: () -> [StashedFile]
    var onDragSuccess: ([StashedFile]) -> Void
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onDoubleClick: () -> Void
    var buildContextMenu: () -> NSMenu?

    private var pendingDragFiles: [StashedFile] = []

    func recordPendingDrag(files: [StashedFile]) {
        pendingDragFiles = files
    }

    init(
        getDragFiles: @escaping () -> [StashedFile],
        onDragSuccess: @escaping ([StashedFile]) -> Void,
        onClick: @escaping (NSEvent.ModifierFlags) -> Void,
        onDoubleClick: @escaping () -> Void,
        buildContextMenu: @escaping () -> NSMenu?
    ) {
        self.getDragFiles = getDragFiles
        self.onDragSuccess = onDragSuccess
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick
        self.buildContextMenu = buildContextMenu
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        return [.copy, .move]
    }

    nonisolated func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        Task { @MainActor in
            let files = self.pendingDragFiles
            self.pendingDragFiles = []
            guard !files.isEmpty, operation != [] else { return }
            self.onDragSuccess(files)
        }
    }
}

@MainActor
struct FileItemHost<Content: View>: NSViewRepresentable {
    let file: StashedFile
    let getDragFiles: () -> [StashedFile]
    let onDragSuccess: ([StashedFile]) -> Void
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let buildContextMenu: () -> NSMenu?
    let content: () -> Content

    func makeCoordinator() -> FileItemDragCoordinator {
        FileItemDragCoordinator(
            getDragFiles: getDragFiles,
            onDragSuccess: onDragSuccess,
            onClick: onClick,
            onDoubleClick: onDoubleClick,
            buildContextMenu: buildContextMenu
        )
    }

    func makeNSView(context: Context) -> FileItemNSView {
        let view = FileItemNSView()
        view.coordinator = context.coordinator
        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.hostingView = hosting
        return view
    }

    func updateNSView(_ nsView: FileItemNSView, context: Context) {
        context.coordinator.getDragFiles = getDragFiles
        context.coordinator.onDragSuccess = onDragSuccess
        context.coordinator.onClick = onClick
        context.coordinator.onDoubleClick = onDoubleClick
        context.coordinator.buildContextMenu = buildContextMenu
        nsView.coordinator = context.coordinator
        if let hosting = nsView.hostingView as? NSHostingView<AnyView> {
            hosting.rootView = AnyView(content())
        }
    }
}

@MainActor
final class FileItemNSView: NSView {
    weak var coordinator: FileItemDragCoordinator?
    var hostingView: NSView?

    private var mouseDownLocation: NSPoint?
    private var clickCount: Int = 0

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self.frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        clickCount = event.clickCount
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownLocation, let coordinator else { return }
        let dx = event.locationInWindow.x - down.x
        let dy = event.locationInWindow.y - down.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist >= 4 else { return }

        mouseDownLocation = nil
        startDrag(coordinator: coordinator, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            clickCount = 0
        }
        guard mouseDownLocation != nil, let coordinator else { return }

        if clickCount >= 2 {
            coordinator.onDoubleClick()
        } else {
            coordinator.onClick(event.modifierFlags)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = coordinator?.buildContextMenu() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func startDrag(coordinator: FileItemDragCoordinator, event: NSEvent) {
        let files = coordinator.getDragFiles()
        guard !files.isEmpty else { return }

        coordinator.recordPendingDrag(files: files)

        var draggingItems: [NSDraggingItem] = []
        for (index, file) in files.enumerated() {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(file.url.absoluteString, forType: .fileURL)

            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let frame = NSRect(
                x: bounds.midX - 24 + CGFloat(index) * 6,
                y: bounds.midY - 24 - CGFloat(index) * 6,
                width: 48,
                height: 48
            )
            let preview = file.thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path)
            item.setDraggingFrame(frame, contents: preview)
            draggingItems.append(item)
        }

        beginDraggingSession(with: draggingItems, event: event, source: coordinator)
    }
}
