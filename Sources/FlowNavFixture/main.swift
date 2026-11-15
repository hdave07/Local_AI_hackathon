import AppKit

// A small, deterministic AppKit app used by FlowAX's live integration tests.
// It exposes ordinary AppKit controls through the real Accessibility API:
// unique and duplicate buttons, a checkbox, labelled and placeholder text fields,
// a secure field, a scrollable list, a disabled button, an unlabelled image button,
// and a "Volatile" button that other buttons rename, move or remove (stale-target tests).
// It never touches user data.

@MainActor
final class FixtureController: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let status = NSTextField(labelWithString: "Status: ready")
    var volatile: NSButton?
    let volatileHost = NSView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Flow Nav Fixture"

        status.setAccessibilityIdentifier("status")

        let save = button("Save") { $0.status.stringValue = "Status: Save pressed" }
        let replyA = button("Reply") { $0.status.stringValue = "Status: Reply A pressed" }
        replyA.setAccessibilityIdentifier("replyA")
        let replyB = button("Reply") { $0.status.stringValue = "Status: Reply B pressed" }
        replyB.setAccessibilityIdentifier("replyB")
        let replyAll = button("Reply All") { $0.status.stringValue = "Status: Reply All pressed" }
        let disabled = button("Disabled Action") { _ in }
        disabled.isEnabled = false
        let unlabeled = NSButton(image: NSImage(systemSymbolName: "star", accessibilityDescription: nil)!,
                                 target: nil, action: nil)
        unlabeled.setAccessibilityLabel(nil)
        unlabeled.setAccessibilityIdentifier("unlabeled")

        let notify = NSButton(checkboxWithTitle: "Notify me", target: nil, action: nil)

        let subjectLabel = NSTextField(labelWithString: "Subject:")
        let subject = NSTextField(string: "")
        subject.setAccessibilityTitleUIElement(subjectLabel)
        subject.setAccessibilityIdentifier("subject")
        let search = NSTextField(string: "")
        search.placeholderString = "Search notes"
        search.setAccessibilityIdentifier("search")
        let password = NSSecureTextField(string: "fixture-secret")
        password.placeholderString = "Password"

        let rename = button("Rename Volatile") { c in c.volatile?.title = "Changed" }
        let shift = button("Shift Volatile") { c in
            c.volatile?.setFrameOrigin(NSPoint(x: (c.volatile?.frame.minX ?? 0) == 0 ? 80 : 0, y: 0))
        }
        let remove = button("Remove Volatile") { c in c.volatile?.removeFromSuperview(); c.volatile = nil }
        let restore = button("Restore Volatile") { c in c.makeVolatile() }
        volatileHost.translatesAutoresizingMaskIntoConstraints = false
        volatileHost.widthAnchor.constraint(equalToConstant: 220).isActive = true
        volatileHost.heightAnchor.constraint(equalToConstant: 32).isActive = true
        makeVolatile()

        let rows = NSStackView(views: (1...60).map { NSTextField(labelWithString: "Row \($0)") })
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4),
            document.widthAnchor.constraint(equalToConstant: 480),
        ])
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        scroll.setAccessibilityLabel("Results list")
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 500).isActive = true

        let stack = NSStackView(views: [
            status,
            hstack([save, replyA, replyB, replyAll]),
            hstack([notify, disabled, unlabeled]),
            hstack([subjectLabel, subject]),
            hstack([search, password]),
            hstack([rename, shift, remove, restore]),
            volatileHost,
            scroll,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        subject.widthAnchor.constraint(equalToConstant: 260).isActive = true
        search.widthAnchor.constraint(equalToConstant: 200).isActive = true
        password.widthAnchor.constraint(equalToConstant: 140).isActive = true
        window.contentView = stack
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func makeVolatile() {
        volatile?.removeFromSuperview()
        let b = button("Volatile") { $0.status.stringValue = "Status: Volatile pressed" }
        b.translatesAutoresizingMaskIntoConstraints = true
        b.frame = NSRect(x: 0, y: 0, width: 120, height: 32)
        volatileHost.addSubview(b)
        volatile = b
    }

    private var handlers: [NSButton: (FixtureController) -> Void] = [:]

    private func button(_ title: String, _ handler: @escaping (FixtureController) -> Void) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(pressed(_:)))
        handlers[b] = handler
        return b
    }

    @objc private func pressed(_ sender: NSButton) { handlers[sender]?(self) }

    private func hstack(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        return s
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = FixtureController()
app.delegate = controller
app.run()
