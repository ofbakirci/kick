import KickCore
import SwiftUI

/// Review sheet for the explicit Stop action. Separate from Safely Kick: one
/// process, one polite request, never a forced kill.
struct StopProcessConfirmationView: View {
    let process: BlockingProcess
    let plan: ProcessStopPlan?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: ProcessPresentation.icon(for: process))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stop “\(processName)”?")
                        .font(.title3.weight(.semibold))
                    Text("Last resort. Safely Kick does not close this one on its own.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(plan?.message ?? "Kick cannot stop this process.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let warning = plan?.warning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(warning)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.kickManualBackground, in: RoundedRectangle(cornerRadius: 10))
            }

            if let owner = ProcessPresentation.ownerDescription(for: process) {
                Text("\(owner). You can also close it there yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Kick sends one request and waits. If the process ignores it, the disk stays mounted and Kick shows what is still open. Kick never forces a kill.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(stopButtonTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!isAvailable)
                    .accessibilityHint("Sends one stop request to \(processName), then rechecks the disk.")
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var isAvailable: Bool {
        guard let plan else { return false }
        return plan.method != .unavailable
    }

    private var processName: String {
        plan?.processName ?? ProcessPresentation.name(for: process)
    }

    private var stopButtonTitle: String {
        plan?.method == .quitApplication ? "Ask to Quit" : "Stop Process"
    }
}
