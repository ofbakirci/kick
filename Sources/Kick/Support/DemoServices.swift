import Foundation
import KickCore

actor DemoScenario {
    private var activeBlockers: [BlockingProcess]

    init(blockers: [BlockingProcess]) {
        self.activeBlockers = blockers
    }

    func isBlocked() -> Bool { !activeBlockers.isEmpty }
    func blockers() -> [BlockingProcess] { activeBlockers }
    func release() { activeBlockers = [] }
}

struct DemoVolumeProvider: VolumeProviding {
    func mountedExternalDisks() async throws -> [ExternalDisk] {
        [DemoData.disk]
    }
}

struct DemoEjector: DiskEjecting {
    let scenario: DemoScenario

    func eject(_ disk: ExternalDisk) async throws {
        if await scenario.isBlocked() {
            throw EjectionFailure(
                message: "The disk is in use.",
                dissentingProcessID: 90294,
                kind: .busy
            )
        }
    }
}

struct DemoBlockerDiagnoser: BlockerDiagnosing {
    let scenario: DemoScenario

    func blockers(on disk: ExternalDisk) async throws -> [BlockingProcess] {
        await scenario.blockers()
    }
}

@MainActor
struct DemoProcessReleaser: ProcessReleasing, ProcessStopping {
    let scenario: DemoScenario
    let allowsAutomaticQuit: Bool

    func planStop(of process: BlockingProcess) -> ProcessStopPlan {
        let isProtected = process.command.localizedCaseInsensitiveContains(
            "Virtualization.VirtualMachine"
        )
        return ProcessStopPlan(
            processID: process.pid,
            processName: ProcessPresentation.name(for: process),
            method: isProtected ? .terminateProcess : .quitApplication,
            message: isProtected
                ? "Kick will send one stop request (SIGTERM) to Virtual Machine. Most tools stop cleanly. Kick never forces a kill."
                : "Kick will ask this app to quit, the same as Quit in its menu. The app can still show a save dialog.",
            warning: isProtected
                ? "A running virtual machine can lose unsaved state. Stop it from its own app if you can."
                : nil
        )
    }

    func requestStop(of process: BlockingProcess) async -> ReleaseAttempt {
        await scenario.release()
        return ReleaseAttempt(
            processID: process.pid,
            processName: ProcessPresentation.name(for: process),
            disposition: .requested,
            message: "Kick sent a stop request to \(ProcessPresentation.name(for: process))."
        )
    }

    func planRelease(of processes: [BlockingProcess]) -> [ProcessReleasePlan] {
        processes.map {
            let isProtected = $0.command.localizedCaseInsensitiveContains(
                "Virtualization.VirtualMachine"
            )
            return ProcessReleasePlan(
                processID: $0.pid,
                processName: $0.command,
                strategy: allowsAutomaticQuit && !isProtected
                    ? .quitApplication
                    : .manualAction,
                message: allowsAutomaticQuit && !isProtected
                    ? "Kick will ask this app to quit."
                    : "Stop the virtual machine, then try again."
            )
        }
    }

    func requestRelease(of processes: [BlockingProcess]) async -> [ReleaseAttempt] {
        if allowsAutomaticQuit {
            await scenario.release()
        }
        return processes.map {
            let isProtected = $0.command.localizedCaseInsensitiveContains(
                "Virtualization.VirtualMachine"
            )
            let wasRequested = allowsAutomaticQuit && !isProtected
            return ReleaseAttempt(
                processID: $0.pid,
                processName: $0.command,
                disposition: wasRequested ? .requested : .needsManualAction,
                message: wasRequested
                    ? "Kick asked the app to quit."
                    : isProtected
                    ? "Stop the virtual machine, then try again."
                    : "Close this process, then try again."
            )
        }
    }
}

enum DemoData {
    static let disk = ExternalDisk(
        id: "demo-disk",
        displayName: "345-BACKUP",
        deviceName: "External SSD",
        wholeDiskIdentifier: "disk9",
        volumes: [
            DiskVolume(
                id: "demo-volume",
                name: "345-BACKUP",
                mountURL: URL(fileURLWithPath: "/Volumes/345-BACKUP"),
                totalCapacity: 1_000_000_000_000,
                availableCapacity: 428_000_000_000,
                formatDescription: "APFS"
            )
        ],
        physicalCapacity: 1_000_000_000_000
    )

    static let protectedBlockers = [
        BlockingProcess(
            pid: 90294,
            parentPID: 1,
            command: "com.apple.Virtualization.VirtualMachine",
            userID: 501,
            loginName: "user",
            openFiles: [
                OpenFileReference(
                    path: "/Volumes/345-BACKUP/Virtual Machines/Studio.bundle/Disk.img",
                    descriptor: "32",
                    fileType: "REG",
                    access: .read
                ),
                OpenFileReference(
                    path: "/Volumes/345-BACKUP/Virtual Machines/Studio.bundle/Config.json",
                    descriptor: "35",
                    fileType: "REG",
                    access: .read
                )
            ]
        )
    ]

    static let kickableBlockers = [
        BlockingProcess(
            pid: 63_120,
            parentPID: 1,
            command: "Preview",
            userID: 501,
            loginName: "user",
            openFiles: [
                OpenFileReference(
                    path: "/Volumes/345-BACKUP/Reference/cover-art.png",
                    descriptor: "18",
                    fileType: "REG",
                    access: .read
                )
            ],
            executablePath: "/System/Applications/Preview.app/Contents/MacOS/Preview",
            startTime: ProcessStartTime(seconds: 1_787_089_200, microseconds: 0)
        )
    ]
}
