import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(
                        systemName: iconName(
                            for: context.state.status,
                            isCompleted: context.state.isCompleted
                        )
                    )
                    .foregroundColor(
                        iconColor(
                            for: context.state.status,
                            isCompleted: context.state.isCompleted
                        )
                    )
                    .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(
                        context.state.isCompleted
                            ? "Done"
                            : "\(Int(context.state.progress * 100))%"
                    )
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.fileName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(
                            value: context.state.isCompleted
                                ? 1.0 : context.state.progress
                        )
                        .tint(context.state.isCompleted ? .green : .blue)

                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.caption2)
                                Text(context.state.speed)
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)

                            Spacer()

                            Text(context.state.status)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                Text(context.state.eta)
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }

                        Text(
                            "\(context.state.downloadedSize) / \(context.state.totalSize)"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Image(
                    systemName: context.state.isCompleted
                        ? "checkmark.circle.fill"
                        : "arrow.down.circle"
                )
                .foregroundColor(
                    context.state.isCompleted ? .green : .blue
                )
            } compactTrailing: {
                if context.state.isCompleted {
                    Text("Done")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
            } minimal: {
                Image(
                    systemName: context.state.isCompleted
                        ? "checkmark.circle.fill"
                        : "arrow.down.circle"
                )
                .foregroundColor(
                    context.state.isCompleted ? .green : .blue
                )
            }
        }
    }

    private func iconName(for status: String, isCompleted: Bool) -> String {
        if isCompleted { return "checkmark.circle.fill" }
        switch status.lowercased() {
        case "downloading": return "arrow.down.circle.fill"
        case "paused": return "pause.circle.fill"
        case "error", "failed": return "exclamationmark.circle.fill"
        case "queued": return "clock.fill"
        default: return "arrow.down.circle"
        }
    }

    private func iconColor(for status: String, isCompleted: Bool) -> Color {
        if isCompleted { return .green }
        switch status.lowercased() {
        case "downloading": return .blue
        case "paused": return .orange
        case "error", "failed": return .red
        case "queued": return .gray
        default: return .blue
        }
    }
}

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<DownloadActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: iconName())
                        .foregroundColor(iconColor())
                    Text(context.state.fileName)
                        .font(.headline)
                        .lineLimit(1)
                }
                if context.state.isCompleted {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.blue)
                        Text(context.state.speed)
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\u{2022}")
                            .foregroundColor(.secondary)
                        Text(context.state.status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    context.state.isCompleted
                        ? "Done"
                        : "\(Int(context.state.progress * 100))%"
                )
                .font(.title2)
                .fontWeight(.bold)
                Text("\(context.state.downloadedSize) / \(context.state.totalSize)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if !context.state.isCompleted {
                    Text(context.state.eta)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.2))
        .activitySystemActionForegroundColor(.blue)
    }

    private func iconName() -> String {
        if context.state.isCompleted { return "checkmark.circle.fill" }
        switch context.state.status.lowercased() {
        case "downloading": return "arrow.down.circle.fill"
        case "paused": return "pause.circle.fill"
        case "error", "failed": return "exclamationmark.circle.fill"
        case "queued": return "clock.fill"
        default: return "arrow.down.circle"
        }
    }

    private func iconColor() -> Color {
        if context.state.isCompleted { return .green }
        switch context.state.status.lowercased() {
        case "downloading": return .blue
        case "paused": return .orange
        case "error", "failed": return .red
        case "queued": return .gray
        default: return .blue
        }
    }
}
