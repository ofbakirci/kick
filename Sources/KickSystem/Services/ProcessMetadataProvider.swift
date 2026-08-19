import AppKit
import Darwin
import Foundation
import KickCore

struct ProcessMetadata: Equatable {
    let pid: Int32
    let parentPID: Int32
    let userID: UInt32
    let command: String
    let executablePath: String?
    let startTime: ProcessStartTime

    func blockerReportedByMacOS(parentApplication: ParentApplication? = nil) -> BlockingProcess {
        BlockingProcess(
            pid: pid,
            parentPID: parentPID,
            command: command,
            userID: userID,
            openFiles: [],
            executablePath: executablePath,
            startTime: startTime,
            isSystemDissent: true,
            parentApplication: parentApplication
        )
    }

    /// True when the live process is the same one Kick diagnosed earlier. A
    /// recycled PID has a different start time or executable.
    func matchesIdentity(of process: BlockingProcess) -> Bool {
        userID == process.userID
            && parentPID == process.parentPID
            && executablePath == process.executablePath
            && startTime == process.startTime
    }
}

protocol ProcessMetadataProviding {
    func metadata(for pid: Int32) -> ProcessMetadata?
    func parentApplication(for pid: Int32) -> ParentApplication?
}

extension ProcessMetadataProviding {
    func parentApplication(for pid: Int32) -> ParentApplication? { nil }
}

struct SystemProcessMetadataProvider: ProcessMetadataProviding {
    /// Walks up the parent chain and returns the first ancestor that is a
    /// normal macOS app, such as the Terminal window that owns a shell.
    func parentApplication(for pid: Int32) -> ParentApplication? {
        var current = pid
        for _ in 0..<12 {
            guard let info = bsdInfo(for: current) else { return nil }
            let parent = Int32(info.pbi_ppid)
            guard parent > 1, parent != current else { return nil }
            if let application = NSRunningApplication(processIdentifier: parent),
               application.activationPolicy != .prohibited {
                return ParentApplication(
                    pid: parent,
                    name: application.localizedName
                        ?? application.bundleIdentifier
                        ?? "App",
                    bundleIdentifier: application.bundleIdentifier
                )
            }
            current = parent
        }
        return nil
    }

    func metadata(for pid: Int32) -> ProcessMetadata? {
        guard let info = bsdInfo(for: pid) else { return nil }

        let command = runningApplicationName(for: pid)
            ?? processName(for: pid)
            ?? "Process \(pid)"
        return ProcessMetadata(
            pid: pid,
            parentPID: Int32(info.pbi_ppid),
            userID: info.pbi_uid,
            command: command,
            executablePath: executablePath(for: pid),
            startTime: ProcessStartTime(
                seconds: info.pbi_start_tvsec,
                microseconds: info.pbi_start_tvusec
            )
        )
    }

    private func bsdInfo(for pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let actualSize = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, expectedSize)
        }
        guard actualSize == expectedSize else { return nil }
        return info
    }

    private func runningApplicationName(for pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            ?? NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private func processName(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1_024)
        let length = buffer.withUnsafeMutableBytes {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return nil }
        return String(
            decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = buffer.withUnsafeMutableBytes {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return nil }
        return String(
            decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
}
