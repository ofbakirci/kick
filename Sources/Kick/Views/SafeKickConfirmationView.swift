import KickCore
import SwiftUI

struct SafeKickConfirmationView: View {
    let disk: ExternalDisk
    let blockers: [BlockingProcess]
    let releasePlans: [ProcessReleasePlan]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: hasEligibleRelease ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(hasEligibleRelease ? Color.kickAccent : Color.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(confirmationTitle)
                        .font(.title3.weight(.semibold))
                    Text(confirmationSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(confirmationMessage)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(blockers) { process in
                        HStack(spacing: 10) {
                            Image(nsImage: ProcessPresentation.icon(for: process))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ProcessPresentation.name(for: process))
                                    .font(.subheadline.weight(.medium))
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Image(systemName: planSymbol(for: process))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(planColor(for: process))
                                        .accessibilityHidden(true)
                                    Text(planMessage(for: process))
                                        .font(.caption)
                                        .foregroundStyle(isEligible(process) ? Color.secondary : Color.primary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(9)
                        .background(
                            isEligible(process)
                                ? Color.primary.opacity(0.035)
                                : Color.kickManualBackground,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }
            }
            .frame(maxHeight: 210)

            HStack {
                if hasEligibleRelease {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    SafeKickButton(
                        diskName: disk.displayName,
                        accessibilityHint: "Asks eligible apps to quit, rechecks the disk, then ejects it.",
                        action: onConfirm
                    )
                    .frame(width: 170)
                } else {
                    Spacer()
                    Button("Back", action: onCancel)
                        .buttonStyle(.borderedProminent)
                        .tint(.kickProminentAccent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var eligiblePlanCount: Int {
        releasePlans.filter { $0.strategy == .quitApplication }.count
    }

    private var manualBlockerCount: Int {
        max(blockers.count - eligiblePlanCount, 0)
    }

    private var hasEligibleRelease: Bool {
        eligiblePlanCount > 0
    }

    private var confirmationTitle: String {
        hasEligibleRelease
            ? "Safely eject “\(disk.displayName)”?"
            : "“\(disk.displayName)” still needs attention"
    }

    private var confirmationSubtitle: String {
        hasEligibleRelease
            ? "Save your work before you continue."
            : "Complete the steps below, then check again."
    }

    private var confirmationMessage: String {
        guard hasEligibleRelease else {
            return "Kick cannot close these blockers. The disk stays mounted until every blocker releases it."
        }

        let eligibleDescription = eligiblePlanCount == 1
            ? "one app"
            : "\(eligiblePlanCount) apps"
        let manualDescription: String
        if manualBlockerCount == 0 {
            manualDescription = ""
        } else if manualBlockerCount == 1 {
            manualDescription = " One blocker still needs you."
        } else {
            manualDescription = " \(manualBlockerCount) blockers still need you."
        }
        return "Kick will ask \(eligibleDescription) to quit.\(manualDescription) It ejects only after the disk is no longer in use. It never force quits."
    }

    private func releasePlan(for process: BlockingProcess) -> ProcessReleasePlan? {
        releasePlans.first { $0.processID == process.pid }
    }

    private func isEligible(_ process: BlockingProcess) -> Bool {
        releasePlan(for: process)?.strategy == .quitApplication
    }

    private func planMessage(for process: BlockingProcess) -> String {
        releasePlan(for: process)?.message ?? "Review this item before you continue."
    }

    private func planSymbol(for process: BlockingProcess) -> String {
        isEligible(process) ? "arrow.right.circle.fill" : "exclamationmark.circle.fill"
    }

    private func planColor(for process: BlockingProcess) -> Color {
        isEligible(process) ? .secondary : .orange
    }
}
