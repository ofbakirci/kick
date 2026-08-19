import AppKit
import Foundation

final class KickHoldAppDelegate: NSObject, NSApplicationDelegate {
    private var heldFile: FileHandle?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count == 2 else {
            NSApp.terminate(nil)
            return
        }

        let fileURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let created = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data("Kick GUI eject test\n".utf8)
        )
        guard created, let handle = FileHandle(forReadingAtPath: fileURL.path) else {
            NSApp.terminate(nil)
            return
        }

        heldFile = handle
        try? FileManager.default.removeItem(at: fileURL)
        showWindow(for: fileURL.deletingLastPathComponent().lastPathComponent)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showWindow(for volumeName: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kick Test Blocker"
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Holding \(volumeName) for a safe test")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.alignment = .center

        let detail = NSTextField(labelWithString: "Kick can ask this app to quit. No user file is changed.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = KickHoldAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
