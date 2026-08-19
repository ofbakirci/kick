import KickCore
import SwiftUI

struct BlockingProcessRow: View {
    let process: BlockingProcess
    let releasePlan: ProcessReleasePlan?
    let stopPlan: ProcessStopPlan?
    let releaseAttempt: ReleaseAttempt?
    let onShow: () -> Void
    let onStop: () -> Void
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 11) {
                Image(nsImage: ProcessPresentation.icon(for: process))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(ProcessPresentation.name(for: process))
                        .font(.subheadline.weight(.semibold))
                    if let owner = ProcessPresentation.ownerDescription(for: process) {
                        Text(owner)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(ProcessPresentation.activity(for: process))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let statusMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: statusSymbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(statusSymbolColor)
                                .accessibilityHidden(true)
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(messageColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if showableApplicationName != nil || canStop {
                        HStack(spacing: 14) {
                            if let showableApplicationName {
                                Button("Show \(showableApplicationName)", action: onShow)
                                    .buttonStyle(.link)
                                    .font(.caption.weight(.medium))
                                    .help("Bring \(showableApplicationName) to the front so you can close the window or change its folder")
                                    .accessibilityHint("Brings the app to the front. Kick does not close it.")
                            }
                            if canStop {
                                Button("Stop…", action: onStop)
                                    .buttonStyle(.link)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.red)
                                    .help("Last resort: Kick asks for a review, then sends one stop request. It never forces a kill.")
                                    .accessibilityLabel("Stop \(ProcessPresentation.name(for: process))")
                                    .accessibilityHint("Opens a review before Kick sends one stop request to this process.")
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Hide details" : "Show details")
                .accessibilityLabel(
                    isExpanded
                        ? "Hide details for \(ProcessPresentation.name(for: process))"
                        : "Show details for \(ProcessPresentation.name(for: process))"
                )
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: "PID \(process.pid)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    ForEach(Array(process.openFiles.prefix(6).enumerated()), id: \.offset) { _, file in
                        Text(verbatim: ProcessPresentation.label(for: file))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(file.path)
                    }
                    if process.openFiles.isEmpty {
                        Text("No open paths were reported.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if process.openFiles.count > 6 {
                        Text("\(process.openFiles.count - 6) more items")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 41)
                .transition(.opacity)
            }
        }
        .padding(11)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Stop is the last stage. It appears only for blockers Safely Kick will
    /// not close on its own, and only when Kick is allowed to stop them.
    private var canStop: Bool {
        guard let stopPlan, stopPlan.method != .unavailable else { return false }
        return releasePlan?.strategy == .manualAction
    }

    private var showableApplicationName: String? {
        guard let application = ProcessPresentation.showableApplication(for: process) else {
            return nil
        }
        if application.processIdentifier == process.pid {
            return ProcessPresentation.name(for: process)
        }
        return application.localizedName ?? process.parentApplication?.name
    }

    private var statusMessage: String? {
        releaseAttempt?.message ?? releasePlan?.message
    }

    private var statusSymbol: String {
        if let releaseAttempt {
            switch releaseAttempt.disposition {
            case .requested: return "arrow.right.circle.fill"
            case .alreadyClosed: return "checkmark.circle.fill"
            case .needsManualAction: return "exclamationmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
        return releasePlan?.strategy == .quitApplication
            ? "arrow.right.circle.fill"
            : "exclamationmark.circle.fill"
    }

    private var statusSymbolColor: Color {
        if let releaseAttempt {
            switch releaseAttempt.disposition {
            case .requested, .alreadyClosed: return .green
            case .needsManualAction: return .orange
            case .failed: return .red
            }
        }
        return releasePlan?.strategy == .quitApplication ? .secondary : .orange
    }

    private var messageColor: Color {
        if releaseAttempt?.disposition == .needsManualAction
            || releaseAttempt?.disposition == .failed
            || releasePlan?.strategy == .manualAction {
            return .primary
        }
        return .secondary
    }
}
