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
                        accessibilityHint: String(localized: "Opens a review before Kick asks eligible apps to quit."),
                        action: onKick
                    )
                    Button(String(localized: "Check Again"), action: onEject)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "Check whether the disk can eject now"))
                }
            } else {
                VStack(spacing: 6) {
                    primaryButton(String(localized: "Check Again"), action: onEject)
                        .accessibilityLabel(checkAgainAccessibilityLabel)
                        .accessibilityHint(String(localized: "Checks whether the listed blockers have released the disk."))
                    Text(String(localized: "Follow the steps above, then check the disk again."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        case .ejected:
            primaryButton(String(localized: "Done"), action: onReset)
                .keyboardShortcut(.defaultAction)
        case .ejecting, .diagnosing, .releasing, .stopping, .retrying:
            primaryButton(String(localized: "Working…")) {}
                .disabled(true)
        case .ready:
            if disk != nil {
                primaryButton(String(localized: "Eject"), action: onEject)
                    .accessibilityLabel(ejectAccessibilityLabel)
            }
        case let .failed(_, _, recovery):
            if disk != nil && recovery == .retryEject {
                primaryButton(String(localized: "Try Again"), action: onEject)
                    .accessibilityLabel(ejectAccessibilityLabel)
            } else {
                primaryButton(String(localized: "Refresh Disks"), action: onRefresh)
                    .accessibilityLabel(String(localized: "Refresh external disks"))
            }
        }
    }

    private var hasEligibleRelease: Bool {
        releasePlans.contains { $0.strategy == .quitApplication }
    }

    private var ejectAccessibilityLabel: String {
        disk.map { String(localized: "Eject \($0.displayName)") } ?? String(localized: "Eject disk")
    }

    private var checkAgainAccessibilityLabel: String {
        disk.map { String(localized: "Check whether \($0.displayName) can eject") } ?? String(localized: "Check the disk again")
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
                Text(String(localized: "Safely"))
                    .font(.caption2.weight(.semibold))
                Text(String(localized: "safe-eject.button-verb", defaultValue: "Kick"))
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
        .accessibilityLabel(diskName.map { String(localized: "Safely eject \($0)") } ?? String(localized: "Safely eject disk"))
        .accessibilityHint(accessibilityHint)
    }
}
