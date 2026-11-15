import AppKit
import SwiftUI

/// Puts the tiny onigiri in the menu bar: it changes face with Flow's state and gets a soft
/// blush pill while listening. Clicking it toggles listening.
///
/// If FlowApp already owns an NSStatusItem (the HUD menu, ⌥⌘H), don't create a second one:
/// add the same `PassthroughHostingView(rootView: MenuBarMascot(model:))` to that item's button.
@MainActor
final class MenuBarMascotController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: 30)
    private let model: HUDModel

    init(model: HUDModel) {
        self.model = model
        super.init()
        guard let button = item.button else { return }
        let host = PassthroughHostingView(rootView: MenuBarMascot(model: model))
        host.frame = NSRect(x: 2, y: 0, width: 26, height: 22)
        button.addSubview(host)
        button.target = self
        button.action = #selector(toggle)
        button.setAccessibilityLabel("Flow. Click to start or stop listening.")
    }

    @objc private func toggle() { model.toggleListening() }
}
