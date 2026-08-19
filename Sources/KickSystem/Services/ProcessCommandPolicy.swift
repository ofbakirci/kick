import Foundation

/// Commands Kick treats with extra care. Shells and terminals hold folders,
/// backup and sync tools write for a long time, and virtual machines lose
/// state when they stop abruptly.
enum ProcessCommandPolicy {
    static let protectedExecutables: Set<String> = [
        "sh", "bash", "zsh", "fish", "login", "ssh", "scp", "sftp", "rsync",
        "finder", "dock", "systemuiserver", "loginwindow"
    ]

    static let sensitiveFragments = [
        "backup", "time machine", "sync", "virtualization", "virtualmachine", "virtual machine",
        "vmware", "parallels", "qemu", "terminal", "iterm"
    ]

    static func executableName(of command: String) -> String {
        let value = command.lowercased()
        return value.split(separator: "/").last.map(String.init) ?? value
    }

    static func isSensitive(_ command: String) -> Bool {
        if protectedExecutables.contains(executableName(of: command)) {
            return true
        }
        let value = command.lowercased()
        return sensitiveFragments.contains { value.contains($0) }
    }

    static func isVirtualMachine(_ command: String) -> Bool {
        let value = command.lowercased()
        return value.contains("virtual") || value.contains("vmware")
            || value.contains("parallels") || value.contains("qemu")
    }

    static func isTransfer(_ command: String) -> Bool {
        let value = command.lowercased()
        return value.contains("backup") || value.contains("sync") || value.contains("rsync")
    }

    static func isShell(_ command: String) -> Bool {
        let value = command.lowercased()
        return value.contains("terminal") || value.contains("iterm")
            || ["sh", "bash", "zsh", "fish", "login", "ssh"].contains(executableName(of: command))
    }

    static func isSystemUserInterface(_ command: String) -> Bool {
        ["finder", "dock", "systemuiserver", "loginwindow"].contains(executableName(of: command))
    }

    /// What the user should do instead of an automatic quit.
    static func manualGuidance(for command: String) -> String {
        if isVirtualMachine(command) {
            return "Stop the virtual machine, then try again."
        }
        if isTransfer(command) {
            return "Wait for the transfer or backup to finish."
        }
        if isShell(command) {
            return "Change the terminal folder or close its window."
        }
        if isSystemUserInterface(command) {
            return "Close the file or wait for macOS to finish."
        }
        return "Close this process, then try again."
    }
}
