import Foundation

public struct LsofFieldParser {
    public init() {}

    public func parse(_ data: Data) -> [BlockingProcess] {
        var builder = ProcessBuilder()
        var parsed: [BlockingProcess] = []

        for rawField in data.split(separator: 0, omittingEmptySubsequences: true) {
            var field = rawField[...]
            while field.first == 10 || field.first == 13 {
                field = field.dropFirst()
            }
            guard let code = field.first else { continue }

            let value = String(decoding: field.dropFirst(), as: UTF8.self)
            switch code {
            case Character("p").asciiValue:
                if let process = builder.makeProcess() {
                    parsed.append(process)
                }
                builder = ProcessBuilder()
                builder.pid = Int32(value)
            case Character("R").asciiValue:
                builder.parentPID = Int32(value)
            case Character("c").asciiValue:
                builder.command = value
            case Character("u").asciiValue:
                builder.userID = UInt32(value)
            case Character("L").asciiValue:
                builder.loginName = value
            case Character("f").asciiValue:
                builder.currentDescriptor = value
                builder.currentType = nil
                builder.currentAccess = .unknown
            case Character("t").asciiValue:
                builder.currentType = value
            case Character("a").asciiValue:
                builder.currentAccess = OpenAccess(lsofValue: value)
            case Character("n").asciiValue:
                builder.openFiles.append(
                    OpenFileReference(
                        path: value,
                        descriptor: builder.currentDescriptor,
                        fileType: builder.currentType,
                        access: builder.currentAccess
                    )
                )
            default:
                continue
            }
        }

        if let process = builder.makeProcess() {
            parsed.append(process)
        }

        var order: [Int32] = []
        var byPID: [Int32: BlockingProcess] = [:]
        for process in parsed where !process.openFiles.isEmpty {
            if let existing = byPID[process.pid] {
                byPID[process.pid] = existing.merging(process)
            } else {
                order.append(process.pid)
                byPID[process.pid] = process
            }
        }

        return order.compactMap { byPID[$0] }
    }
}

private struct ProcessBuilder {
    var pid: Int32?
    var parentPID: Int32?
    var command = ""
    var userID: UInt32?
    var loginName: String?
    var openFiles: [OpenFileReference] = []
    var currentDescriptor: String?
    var currentType: String?
    var currentAccess = OpenAccess.unknown

    func makeProcess() -> BlockingProcess? {
        guard let pid else { return nil }
        return BlockingProcess(
            pid: pid,
            parentPID: parentPID,
            command: command.isEmpty ? "Process \(pid)" : command,
            userID: userID,
            loginName: loginName,
            openFiles: openFiles
        )
    }
}

private extension Character {
    var asciiValue: UInt8? {
        unicodeScalars.count == 1 ? unicodeScalars.first?.value.asUInt8 : nil
    }
}

private extension UInt32 {
    var asUInt8: UInt8? {
        self <= UInt8.max ? UInt8(self) : nil
    }
}
