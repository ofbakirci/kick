import SwiftUI

struct HeaderView: View {
    let isRefreshEnabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.kickAccent, .kickAccentEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Kick")
                    .font(.title2.weight(.bold))
                Text("External disks, explained.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!isRefreshEnabled)
            .help("Refresh disks")
            .accessibilityLabel("Refresh disks")
        }
    }
}
