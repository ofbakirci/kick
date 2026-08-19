import KickCore
import SwiftUI

struct ActionBar: View {
    let phase: EjectionPhase
    let disk: ExternalDisk?
    let releasePlans: [ProcessReleasePlan]
    let onEject: () -> Void
    let onKick: () -> Void
    let onRefresh: () -> Void
    let onReset: () -> Void

    var body: some View {
        switch phase {
        case .blocked:
            if hasEligibleRelease {
                VStack(spacing: 8) {
                    SafeKickButton(
                        diskName: disk?.displayName,
                        accessibilityHint: "Opens a review before Kick asks eligible apps to quit.",
                        action: onKick
                    )
                    Button("Check Again", action: onEject)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Check whether the disk can eject now")
                }
            } else {
                VStack(spacing: 6) {
                    primaryButton("Check Again", action: onEject)
                        .accessibilityLabel(checkAgainAccessibilityLabel)
                        .accessibilityHint("Checks whether the listed blockers have released the disk.")
                    Text("Follow the steps above, then check the disk again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        case .ejected:
            primaryButton("Done", action: onReset)
                .keyboardShortcut(.defaultAction)
        case .ejecting, .diagnosing, .releasing, .stopping, .retrying:
            primaryButton("Working…") {}
                .disabled(true)
        case .ready:
            if disk != nil {
                primaryButton("Eject", action: onEject)
                    .accessibilityLabel(ejectAccessibilityLabel)
            }
        case let .failed(_, _, recovery):
            if disk != nil && recovery == .retryEject {
                primaryButton("Try Again", action: onEject)
                    .accessibilityLabel(ejectAccessibilityLabel)
            } else {
                primaryButton("Refresh Disks", action: onRefresh)
                    .accessibilityLabel("Refresh external disks")
            }
        }
    }

    private var hasEligibleRelease: Bool {
        releasePlans.contains { $0.strategy == .quitApplication }
    }

    private var ejectAccessibilityLabel: String {
        disk.map { "Eject \($0.displayName)" } ?? "Eject disk"
    }

    private var checkAgainAccessibilityLabel: String {
        disk.map { "Check whether \($0.displayName) can eject" } ?? "Check the disk again"
    }

    private func primaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.kickProminentAccent)
        .controlSize(.large)
    }
}

struct SafeKickButton: View {
    let diskName: String?
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: -1) {
                Text("Safely")
                    .font(.caption2.weight(.semibold))
                Text("Kick")
                    .font(.title3.weight(.bold))
            }
            .foregroundStyle(Color.kickActionLabel)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                LinearGradient(
                    colors: [.kickAccent, .kickAccentEnd],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: .kickAccent.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(diskName.map { "Safely eject \($0)" } ?? "Safely eject disk")
        .accessibilityHint(accessibilityHint)
    }
}
