import AppKit
import FlowHUD
import SwiftUI

/// The floating HUD window: a non-activating panel that stays above other apps on every
/// Space (including full-screen apps), never becomes key or main, and never activates Flow.
/// Keyboard focus and Accessibility control stay with the app the user is working in.
final class FlowHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDPanelController {
    static let originKey = "FlowHUD.origin"

    let model: HUDModel
    private var panel: FlowHUDPanel?
    private var hosting: NSHostingView<HUDView>?
    private var observers: [NSObjectProtocol] = []
    private var applyingFrame = false

    init(model: HUDModel) {
        self.model = model
        model.layoutChanged = { [weak self] in self?.scheduleLayout() }
        model.visibilityChanged = { [weak self] visible in self?.setVisible(visible) }
    }

    /// Creates and shows the panel once.
    func install() {
        guard panel == nil else { return }
        let panel = FlowHUDPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
                                 styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // HUDView draws its own soft shadow inside FlowTheme.shadowRoom
        panel.title = "Flow HUD"
        panel.setAccessibilityLabel("Flow status")
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveOrigin() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            })
        layout()
        if !model.state.hidden { panel.orderFrontRegardless() }  // shown without activating Flow
    }

    func setVisible(_ visible: Bool) {
        guard let panel else { return }
        if visible { layout(); panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect? { panel?.frame }

    private func scheduleLayout() {
        // SwiftUI updates the hosting view's fitting size on the next pass.
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    private func layout() {
        guard let panel, let hosting else { return }
        let size = hosting.fittingSize
        let screens = NSScreen.screens.map(\.visibleFrame)
        let target: NSRect
        if panel.frame.width > 1, panel.isVisible {
            target = HUDPlacement.resized(panel.frame, to: size, screens: screens)
        } else {
            target = HUDPlacement.frame(size: size, screens: screens, saved: savedOrigin())
        }
        guard target != panel.frame else { return }
        applyingFrame = true
        panel.setFrame(target, display: true)
        applyingFrame = false
    }

    private func saveOrigin() {
        guard let panel, !applyingFrame else { return }
        // Remember where the user dragged it (re-clamped to the current displays).
        let clamped = HUDPlacement.frame(size: panel.frame.size, screens: NSScreen.screens.map(\.visibleFrame), saved: panel.frame.origin)
        UserDefaults.standard.set([clamped.minX, clamped.minY], forKey: Self.originKey)
        if clamped != panel.frame {
            applyingFrame = true
            panel.setFrame(clamped, display: true)
            applyingFrame = false
        }
    }

    private func savedOrigin() -> CGPoint? {
        guard let a = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], a.count == 2 else { return nil }
        return CGPoint(x: a[0], y: a[1])
    }
}
