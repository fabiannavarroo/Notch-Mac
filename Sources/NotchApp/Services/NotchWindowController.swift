import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    private let appState: NotchAppState
    private let volumeService: SystemVolumeService
    private let quickLook: QuickLookController
    private let panel: NotchPanel
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var dragMonitor: Any?
    private var dragInProgress = false

    init(appState: NotchAppState, volumeService: SystemVolumeService, quickLook: QuickLookController) {
        self.appState = appState
        self.volumeService = volumeService
        self.quickLook = quickLook

        let initialGeometry = NotchGeometry(screen: Self.targetScreen(preferredID: appState.preferredScreenID) ?? NSScreen.main ?? NSScreen.screens.first!)
        appState.updateNotchSize(initialGeometry.notchSize)

        let contentView = NotchIslandView(appState: appState, volumeService: volumeService)
        let hostingController = FirstMouseHostingController(rootView: contentView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.canDrawSubviewsIntoLayer = false
        hostingController.view.layerContentsRedrawPolicy = .duringViewResize
        hostingController.view.autoresizingMask = [.width, .height]

        let panelSize = appState.maxIslandSize
        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.firstMouseDownHandler = { [weak appState, weak panel] event in
            guard let appState, let panel else { return false }

            if let contentView = panel.contentView {
                let local = contentView.convert(event.locationInWindow, from: nil)
                if let hit = contentView.hitTest(local), hit is FileItemNSView {
                    return false
                }
            }

            guard !appState.isPinnedExpanded else { return false }
            appState.togglePinnedExpanded()
            return true
        }
        panel.spaceKeyHandler = { [weak appState, weak quickLook] in
            guard let appState, let quickLook else { return }
            let urls = appState.stashedFiles
                .filter { appState.selectedStashIDs.contains($0.id) }
                .map { $0.url }
            guard !urls.isEmpty else { return }
            quickLook.show(urls: urls)
        }
        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.hasShadow = false
        panel.isOpaque = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false

        bindState()
        reposition(animated: false)
        startHoverTracking()
        startDragMonitoring()
    }

    private func startDragMonitoring() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.type == .leftMouseUp {
                    self.dragInProgress = false
                    return
                }
                let pasteboard = NSPasteboard(name: .drag)
                if pasteboard.types?.contains(.fileURL) == true {
                    self.dragInProgress = true
                }
            }
        }
    }

    private func startHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateHover()
            }
        }
    }

    private func evaluateHover() {
        guard let screen = Self.targetScreen(preferredID: appState.preferredScreenID) else { return }
        let geometry = NotchGeometry(screen: screen)
        let mouse = NSEvent.mouseLocation

        panel.ignoresMouseEvents = false

        let target = appState.targetSize
        let zoneWidth = max(target.width + 6, geometry.notchSize.width + 1)
        let zoneHeight = max(target.height + 6, geometry.notchSize.height + 1)
        let zone = NSRect(
            x: geometry.centerX - zoneWidth / 2,
            y: geometry.topY - zoneHeight,
            width: zoneWidth,
            height: zoneHeight
        )

        let inside = zone.contains(mouse)
        if appState.isHoverExpanded != inside || appState.isHoverHovering != inside {
            appState.setHoveringRaw(inside)
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func bindState() {
        appState.$isIslandEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    panel.orderFrontRegardless()
                    reposition(animated: false)
                } else {
                    panel.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        appState.$verticalOffset
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)

        appState.$preferredScreenID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)
    }

    private func reposition(animated: Bool) {
        guard let screen = Self.targetScreen(preferredID: appState.preferredScreenID) else {
            return
        }

        let geometry = NotchGeometry(screen: screen)
        appState.updateNotchSize(geometry.notchSize)
        let size = appState.maxIslandSize
        let topPadding: CGFloat = geometry.hasNotch ? 0 : 6
        let origin = NSPoint(
            x: geometry.centerX - (size.width / 2),
            y: geometry.topY - size.height - topPadding + appState.verticalOffset
        )
        let frame = NSRect(origin: origin, size: size)

        if panel.frame == frame { return }

        panel.setFrame(frame, display: true)
    }

    static func targetScreen(preferredID: UInt32?) -> NSScreen? {
        if let preferredID,
           let preferred = NSScreen.screens.first(where: { NotchGeometry.displayID(for: $0) == preferredID }) {
            return preferred
        }
        return NSScreen.screens.first { NotchGeometry(screen: $0).hasNotch }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

struct NotchGeometry {
    static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    let screen: NSScreen
    let notchRect: NSRect?

    var hasNotch: Bool {
        notchRect != nil
    }

    var centerX: CGFloat {
        notchRect?.midX ?? screen.frame.midX
    }

    var topY: CGFloat {
        notchRect?.maxY ?? screen.frame.maxY
    }

    var notchSize: CGSize {
        if let rect = notchRect {
            return CGSize(width: rect.width, height: rect.height)
        }
        return CGSize(width: 200, height: 32)
    }

    init(screen: NSScreen) {
        self.screen = screen

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           !leftArea.isEmpty,
           !rightArea.isEmpty,
           rightArea.minX > leftArea.maxX {
            notchRect = NSRect(
                x: leftArea.maxX,
                y: min(leftArea.minY, rightArea.minY),
                width: rightArea.minX - leftArea.maxX,
                height: max(leftArea.height, rightArea.height)
            )
        } else {
            notchRect = nil
        }
    }
}

final class NotchPanel: NSPanel {
    var firstMouseDownHandler: ((NSEvent) -> Bool)?
    var spaceKeyHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
            if firstMouseDownHandler?(event) == true {
                return
            }
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // space
            spaceKeyHandler?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
