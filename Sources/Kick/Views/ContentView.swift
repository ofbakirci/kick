import AppKit
import Combine
import KickCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var workflow: KickWorkflow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsKickConfirmation = false
    @State private var stopCandidate: BlockingProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderView(
                isRefreshEnabled: isRefreshEnabled,
                onRefresh: refresh
            )

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if !workflow.disks.isEmpty {
                        DiskSelectorView(
                            disks: workflow.disks,
                            selection: workflow.selectedDiskID,
                            isEnabled: workflow.phase.allowsDiskSelection,
                            onSelect: workflow.selectDisk
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    StatusPanel(
                        phase: workflow.phase,
                        disk: workflow.selectedDisk,
                        blockers: workflow.blockers,
                        releasePlans: workflow.releasePlans,
                        stopPlans: workflow.stopPlans,
                        releaseAttempts: workflow.releaseAttempts,
                        onShow: showApplication,
                        onStop: { stopCandidate = $0 }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            ActionBar(
                phase: workflow.phase,
                disk: workflow.selectedDisk,
                releasePlans: workflow.releasePlans,
                onEject: eject,
                onKick: { showsKickConfirmation = true },
                onRefresh: refresh,
                onReset: reset
            )
        }
        .padding(22)
        .frame(minWidth: 420, idealWidth: 440, maxWidth: 560)
        .frame(minHeight: 420, idealHeight: 500, maxHeight: 720)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    colors: [.kickAccent.opacity(0.14), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 360
                )
            }
            .ignoresSafeArea()
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: workflow.selectedDiskID
        )
        .task { await workflow.refresh() }
        .onChange(of: workflow.phase) { _, phase in
            if phase != .blocked {
                showsKickConfirmation = false
                stopCandidate = nil
            }
            announce(phase)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            refresh()
        }
        .sheet(isPresented: $showsKickConfirmation) {
            if let disk = workflow.selectedDisk {
                SafeKickConfirmationView(
                    disk: disk,
                    blockers: workflow.blockers,
                    releasePlans: workflow.releasePlans,
                    onCancel: { showsKickConfirmation = false },
                    onConfirm: {
                        showsKickConfirmation = false
                        Task { await workflow.performSafeKick() }
                    }
                )
            }
        }
        .sheet(item: $stopCandidate) { process in
            StopProcessConfirmationView(
                process: process,
                plan: workflow.stopPlans.first { $0.processID == process.pid },
                onCancel: { stopCandidate = nil },
                onConfirm: {
                    stopCandidate = nil
                    Task { await workflow.performStop(of: process) }
                }
            )
        }
    }

    private func showApplication(_ process: BlockingProcess) {
        guard let application = ProcessPresentation.showableApplication(for: process) else { return }
        application.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
    }

    private func refresh() {
        Task { await workflow.refresh() }
    }

    private var isRefreshEnabled: Bool {
        guard !workflow.phase.isBusy else { return false }
        if case .ejected = workflow.phase { return false }
        return true
    }

    private func eject() {
        Task { await workflow.attemptEject() }
    }

    private func reset() {
        Task { await workflow.resetResult() }
    }

    private func announce(_ phase: EjectionPhase) {
        let message: String?
        switch phase {
        case .ready:
            message = nil
        case .ejecting:
            message = "Checking the disk."
        case .diagnosing:
            message = "Finding what is using the disk."
        case .blocked:
            message = "The disk is still in use."
        case .releasing:
            message = "Asking eligible apps to quit."
        case let .stopping(name):
            message = "Stopping \(name)."
        case .retrying:
            message = "The blockers are gone. Ejecting the disk."
        case let .ejected(name):
            message = "\(name) ejected safely."
        case let .failed(title, detail, _):
            message = "\(title). \(detail)"
        }

        guard let message, let application = NSApp else { return }
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ]
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: userInfo
        )
    }
}
