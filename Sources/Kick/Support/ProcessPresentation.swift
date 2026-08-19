import AppKit
import KickCore

enum ProcessPresentation {
    static func name(for process: BlockingProcess) -> String {
        if process.command.localizedCaseInsensitiveContains("Virtualization.VirtualMachine") {
            return "Virtual Machine"
        }
        if ["mds", "mdworker", "mds_stores"].contains(process.command.lowercased()) {
            return "Spotlight"
        }
        if let appURL = applicationBundleURL(for: process),
           let bundle = Bundle(url: appURL),
           let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String),
           !name.isEmpty {
            return name
        }
        return process.command
    }

    static func icon(for process: BlockingProcess) -> NSImage {
        if let appURL = applicationBundleURL(for: process) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSImage(
            systemSymbolName: fallbackSymbol(for: process),
            accessibilityDescription: nil
        ) ?? NSImage()
    }

    static func activity(for process: BlockingProcess) -> String {
        let executable = process.command.lowercased()
        if process.isSystemDissent || process.openFiles.isEmpty {
            return "macOS named this process as the eject blocker."
        }
        if process.hasWritableFiles {
            return "It has an item open for writing."
        }
        if executable.contains("virtualization.virtualmachine") {
            return "A virtual machine has files open on this disk."
        }
        if ["mds", "mdworker", "mds_stores"].contains(executable) {
            return "Spotlight has files open on this disk."
        }
        if process.holdsCurrentFolder {
            let otherCount = process.openFiles.filter { !$0.isDirectoryReference }.count
            if otherCount == 0 {
                return "Its current folder is on this disk."
            }
            return otherCount == 1
                ? "Its current folder is on this disk, and it has one item open."
                : "Its current folder is on this disk, and it has \(otherCount) items open."
        }
        if process.hasUnknownAccess {
            return "Its access to this disk is not clear."
        }
        let count = process.openFiles.count
        return count == 1
            ? "It has one item open on this disk."
            : "It has \(count) items open on this disk."
    }

    /// "Started from Terminal" for a shell or helper that a GUI app owns.
    static func ownerDescription(for process: BlockingProcess) -> String? {
        guard let parent = process.parentApplication, parent.pid != process.pid else { return nil }
        return "Started from \(parent.name)"
    }

    /// The app Kick can bring to the front so the user can close the window,
    /// change folder, or answer a save dialog: the process itself when it is
    /// an app, or the app that owns it.
    static func showableApplication(for process: BlockingProcess) -> NSRunningApplication? {
        if let application = NSRunningApplication(processIdentifier: process.pid),
           application.activationPolicy != .prohibited {
            return application
        }
        guard let parent = process.parentApplication,
              let application = NSRunningApplication(processIdentifier: parent.pid),
              application.activationPolicy != .prohibited else {
            return nil
        }
        return application
    }

    static func label(for file: OpenFileReference) -> String {
        switch file.descriptor {
        case "cwd": return "Current folder: \(file.path)"
        case "rtd": return "Root folder: \(file.path)"
        case "txt": return "Running from: \(file.path)"
        default: return file.path
        }
    }

    private static func fallbackSymbol(for process: BlockingProcess) -> String {
        let command = process.command.lowercased()
        if command.contains("virtual") { return "shippingbox.fill" }
        if command.contains("mds") { return "magnifyingglass" }
        if ["zsh", "bash", "fish", "sh"].contains(command) { return "terminal.fill" }
        return "app.fill"
    }

    private static func applicationBundleURL(for process: BlockingProcess) -> URL? {
        guard let executablePath = process.executablePath else { return nil }
        var candidate = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}
