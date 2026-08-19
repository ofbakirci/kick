import AppKit
import KickCore
import SwiftUI

struct DiskSelectorView: View {
    let disks: [ExternalDisk]
    let selection: ExternalDisk.ID?
    let isEnabled: Bool
    let onSelect: (ExternalDisk.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("External Disks")
                    .font(.headline)
                Spacer()
                Text("\(disks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
                    .accessibilityLabel(diskCountAccessibilityLabel)
            }

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(disks) { disk in
                    DiskCard(
                        disk: disk,
                        isSelected: selection == disk.id,
                        isEnabled: isEnabled,
                        action: { onSelect(disk.id) }
                    )
                }
            }
            .frame(
                maxWidth: disks.count == 1 ? 260 : .infinity,
                alignment: .leading
            )
        }
    }

    private var gridColumns: [GridItem] {
        if disks.count == 1 {
            return [GridItem(.flexible(), spacing: 10)]
        }
        return [
            GridItem(.flexible(minimum: 176), spacing: 10),
            GridItem(.flexible(minimum: 176), spacing: 10),
        ]
    }

    private var diskCountAccessibilityLabel: String {
        disks.count == 1 ? "One connected external disk" : "\(disks.count) connected external disks"
    }
}

private struct DiskCard: View {
    let disk: ExternalDisk
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: diskIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelected ? Color.kickAccent : Color.secondary.opacity(0.45)
                    )
                    .accessibilityHidden(true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                cardBackground,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.kickAccent.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.64)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .help(disk.displayName)
        .accessibilityLabel("\(disk.displayName), \(detailText)")
        .accessibilityHint(isSelected ? "Selected disk" : "Select this disk")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardBackground: Color {
        if isSelected {
            return .kickAccent.opacity(0.11)
        }
        return .primary.opacity(isHovered && isEnabled ? 0.07 : 0.035)
    }

    private var diskIcon: NSImage {
        guard let path = disk.primaryMountURL?.path else {
            return NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)
                ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private var detailText: String {
        let capacity = disk.totalCapacity.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        return [capacity, disk.formatSummary].compactMap { $0 }.joined(separator: " · ")
    }
}
