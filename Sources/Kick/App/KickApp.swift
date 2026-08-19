import AppKit
import KickCore
import KickSystem
import SwiftUI

@main
@MainActor
struct KickApp: App {
    @NSApplicationDelegateAdaptor(KickAppDelegate.self) private var appDelegate
    @StateObject private var workflow: KickWorkflow

    init() {
        let workflow: KickWorkflow
        if CommandLine.arguments.contains("--demo-kickable") {
            let scenario = DemoScenario(blockers: DemoData.kickableBlockers)
            let demoReleaser = DemoProcessReleaser(scenario: scenario, allowsAutomaticQuit: true)
            workflow = KickWorkflow(
                volumeProvider: DemoVolumeProvider(),
                ejector: DemoEjector(scenario: scenario),
                diagnoser: DemoBlockerDiagnoser(scenario: scenario),
                releaser: demoReleaser,
                stopper: demoReleaser,
                settleDelayNanoseconds: 250_000_000
            )
        } else if CommandLine.arguments.contains("--demo-blocked") {
            let scenario = DemoScenario(blockers: DemoData.protectedBlockers)
            let demoReleaser = DemoProcessReleaser(scenario: scenario, allowsAutomaticQuit: false)
            workflow = KickWorkflow(
                volumeProvider: DemoVolumeProvider(),
                ejector: DemoEjector(scenario: scenario),
                diagnoser: DemoBlockerDiagnoser(scenario: scenario),
                releaser: demoReleaser,
                stopper: demoReleaser,
                settleDelayNanoseconds: 250_000_000
            )
        } else if CommandLine.arguments.contains("--demo-ready") {
            let scenario = DemoScenario(blockers: [])
            let demoReleaser = DemoProcessReleaser(scenario: scenario, allowsAutomaticQuit: false)
            workflow = KickWorkflow(
                volumeProvider: DemoVolumeProvider(),
                ejector: DemoEjector(scenario: scenario),
                diagnoser: DemoBlockerDiagnoser(scenario: scenario),
                releaser: demoReleaser,
                stopper: demoReleaser,
                settleDelayNanoseconds: 250_000_000
            )
        } else {
            workflow = KickWorkflow(
                volumeProvider: SystemVolumeProvider(),
                ejector: FileManagerDiskEjector(),
                diagnoser: LsofBlockerDiagnoser(),
                releaser: GracefulProcessReleaser(),
                stopper: ExplicitProcessStopper()
            )
        }

        _workflow = StateObject(wrappedValue: workflow)
    }

    var body: some Scene {
        WindowGroup("Kick", id: "main") {
            ContentView(workflow: workflow)
        }
        .defaultSize(width: 440, height: 500)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Disk") {
                Button("Refresh Disks") {
                    Task { await workflow.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!isRefreshCommandEnabled)

                Divider()

                Button(ejectCommandTitle) {
                    Task { await workflow.attemptEject() }
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!isEjectCommandEnabled)
            }
        }
    }

    private var ejectCommandTitle: String {
        switch workflow.phase {
        case .blocked:
            return "Check Again"
        case let .failed(_, _, recovery):
            return recovery == .retryEject ? "Try Eject Again" : "Eject Disk"
        default:
            guard let name = workflow.selectedDisk?.displayName else { return "Eject Disk" }
            return "Eject \(name)"
        }
    }

    private var isEjectCommandEnabled: Bool {
        guard workflow.selectedDisk != nil, !workflow.phase.isBusy else { return false }
        if case .ejected = workflow.phase { return false }
        if case .failed(_, _, .refreshDisks) = workflow.phase { return false }
        return true
    }

    private var isRefreshCommandEnabled: Bool {
        guard !workflow.phase.isBusy else { return false }
        if case .ejected = workflow.phase { return false }
        return true
    }
}

final class KickAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--demo-light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if CommandLine.arguments.contains("--demo-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
