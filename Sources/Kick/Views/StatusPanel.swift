import KickCore
import SwiftUI

struct StatusPanel: View {
    let phase: EjectionPhase
    let disk: ExternalDisk?
    let blockers: [BlockingProcess]
    let releasePlans: [ProcessReleasePlan]
    let stopPlans: [ProcessStopPlan]
    let releaseAttempts: [ReleaseAttempt]
    let onShow: (BlockingProcess) -> Void
    let onStop: (BlockingProcess) -> Void

    var body: some View {
        Group {
            switch phase {
            case .ready:
                if let disk {
                    ReadyView(disk: disk)
                } else {
                    EmptyDisksView()
                }
            case .ejecting:
                BusyStatusView(
                    title: "Checking \(quotedDiskName)…",
                    message: "Trying a normal eject first."
                )
            case .diagnosing:
                BusyStatusView(
                    title: "Finding what is in the way…",
                    message: "Checking which apps and services have files open."
                )
            case .blocked:
                BlockedStatusView(
                    blockers: blockers,
                    releasePlans: releasePlans,
                    stopPlans: stopPlans,
                    releaseAttempts: releaseAttempts,
                    onShow: onShow,
                    onStop: onStop
                )
            case .releasing:
                BusyStatusView(
                    title: "Releasing \(quotedDiskName)…",
                    message: "Asking eligible apps to quit."
                )
            case .stopping(let name):
                BusyStatusView(
                    title: "Stopping “\(name)”…",
                    message: "Waiting for it to release the disk."
                )
            case .retrying:
                BusyStatusView(
                    title: "Ejecting \(quotedDiskName)…",
                    message: "The blockers are gone."
                )
            case .ejected(let name):
                SuccessStatusView(name: name)
            case .failed(let title, let message, _):
                FailureStatusView(title: title, message: message)
            }
        }
        .transition(.opacity)
    }

    private var quotedDiskName: String {
        disk.map { "“\($0.displayName)”" } ?? "disk"
    }
}

private struct ReadyView: View {
    let disk: ExternalDisk

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.kickAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ready to eject")
                    .font(.headline)
                Text("Kick will try the normal macOS eject first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .kickCard()
    }
}

private struct EmptyDisksView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No external disks")
                .font(.headline)
            Text("Connect a disk to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(16)
        .kickCard()
    }
}

private struct BusyStatusView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 15) {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Working")
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(17)
        .kickCard()
    }
}

private struct BlockedStatusView: View {
    let blockers: [BlockingProcess]
    let releasePlans: [ProcessReleasePlan]
    let stopPlans: [ProcessStopPlan]
    let releaseAttempts: [ReleaseAttempt]
    let onShow: (BlockingProcess) -> Void
    let onStop: (BlockingProcess) -> Void
    @State private var expandedProcessIDs: Set<Int32> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(blockers.count == 1
                        ? "One app or service is using this disk"
                        : "\(blockers.count) apps or services are using this disk")
                        .font(.headline)
                    Text(blockedGuidance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(blockers) { process in
                        BlockingProcessRow(
                            process: process,
                            releasePlan: releasePlans.first { $0.processID == process.pid },
                            stopPlan: stopPlans.first { $0.processID == process.pid },
                            releaseAttempt: releaseAttempts.last { $0.processID == process.pid },
                            onShow: { onShow(process) },
                            onStop: { onStop(process) },
                            isExpanded: Binding(
                                get: { expandedProcessIDs.contains(process.pid) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedProcessIDs.insert(process.pid)
                                    } else {
                                        expandedProcessIDs.remove(process.pid)
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .frame(
                minHeight: min(blockerListHeight, 82),
                idealHeight: blockerListHeight,
                maxHeight: blockerListHeight
            )
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(14)
        .kickCard()
    }

    private var blockedGuidance: String {
        hasEligibleRelease
            ? "Review what Kick can quit before you continue."
            : "Follow the steps below, then check again."
    }

    private var hasEligibleRelease: Bool {
        releasePlans.contains { $0.strategy == .quitApplication }
    }

    private var blockerListHeight: CGFloat {
        let baseHeight = blockers.reduce(CGFloat.zero) { partial, process in
            let ownerHeight: CGFloat = process.parentApplication == nil ? 0 : 18
            let actionHeight: CGFloat = hasRowActions(process) ? 26 : 0
            return partial + 82 + ownerHeight + actionHeight
        }
        let detailsHeight = blockers.reduce(CGFloat.zero) { partial, process in
            guard expandedProcessIDs.contains(process.pid) else { return partial }
            let visiblePathCount = min(process.openFiles.count, 6)
            let pathHeight = CGFloat(visiblePathCount) * 30
            let emptyPathHeight: CGFloat = process.openFiles.isEmpty ? 22 : 0
            let moreItemsHeight: CGFloat = process.openFiles.count > 6 ? 20 : 0
            return partial + 28 + pathHeight + emptyPathHeight + moreItemsHeight
        }
        return min(max(baseHeight, 82) + detailsHeight, 320)
    }

    private func hasRowActions(_ process: BlockingProcess) -> Bool {
        let canStop = stopPlans.first { $0.processID == process.pid }?.method != .unavailable
            && releasePlans.first { $0.processID == process.pid }?.strategy == .manualAction
        return canStop || ProcessPresentation.showableApplication(for: process) != nil
    }
}

private struct SuccessStatusView: View {
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Ejected safely")
                .font(.title3.weight(.semibold))
            Text("You can unplug “\(name)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
        .kickCard()
    }
}

private struct FailureStatusView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "xmark.octagon.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(16)
        .kickCard()
    }
}
