import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController {
    private let appState: NotchAppState
    private let panel: NotchPanel
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?

    init(appState: NotchAppState) {
        self.appState = appState

        let initialGeometry = NotchGeometry(screen: Self.targetScreen() ?? NSScreen.main ?? NSScreen.screens.first!)
        appState.updateNotchSize(initialGeometry.notchSize)

        let contentView = NotchIslandView(appState: appState)
        let hostingController = FirstMouseHostingController(rootView: contentView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.canDrawSubviewsIntoLayer = true

        let panelSize = appState.targetSize
        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.firstMouseDownHandler = { [weak appState] in
            guard let appState, !appState.isPinnedExpanded else {
                return false
            }

            appState.togglePinnedExpanded()
            return true
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
    }

    private func startHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateHover()
            }
        }
    }

    private func evaluateHover() {
        guard let screen = Self.targetScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        let mouse = NSEvent.mouseLocation

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

        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.reposition(animated: true)
                }
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
        guard let screen = Self.targetScreen() else {
            return
        }

        let geometry = NotchGeometry(screen: screen)
        appState.updateNotchSize(geometry.notchSize)
        let size = appState.targetSize
        let topPadding: CGFloat = geometry.hasNotch ? 0 : 6
        let origin = NSPoint(
            x: geometry.centerX - (size.width / 2),
            y: geometry.topY - size.height - topPadding + appState.verticalOffset
        )
        let frame = NSRect(origin: origin, size: size)

        if panel.frame == frame { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.2, 1)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { NotchGeometry(screen: $0).hasNotch }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

private struct NotchGeometry {
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
    var firstMouseDownHandler: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
            if firstMouseDownHandler?() == true {
                return
            }
        }

        super.sendEvent(event)
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
