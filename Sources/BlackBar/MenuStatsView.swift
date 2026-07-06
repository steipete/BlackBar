import SwiftUI

/// Borderless stat rows styled to sit flush with native menu content.
struct MenuStatsView: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                StatTile(value: self.snapshot.usage.activeJobs, label: "active jobs")
                StatTile(value: self.snapshot.usage.activeVCPU, label: "active vCPU")
                StatTile(value: self.snapshot.usage.queuedJobs, label: "queued")
            }

            if !self.historyChips.isEmpty {
                HStack(spacing: 10) {
                    ForEach(self.historyChips, id: \.label) { chip in
                        LegendChip(label: "\(chip.label) \(chip.count)", color: chip.color)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8, weight: .semibold))
                if let refreshedAt = self.snapshot.refreshedAt {
                    Text("Updated \(refreshedAt.formatted(date: .omitted, time: .standard))")
                }
                if self.snapshot.usage.fetchedJobs > 0 {
                    Text("· \(self.snapshot.usage.fetchedJobs) jobs sampled")
                }
                Spacer(minLength: 0)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)

            if let error = self.snapshot.error {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 360, alignment: .leading)
    }

    private struct HistoryChip {
        var label: String
        var count: Int
        var color: Color
    }

    private var historyChips: [HistoryChip] {
        let counts = self.snapshot.usage.statusCounts
        guard !counts.isEmpty else { return [] }
        let order = ["success", "failure", "cancelled", "in_progress", "queued"]
        let known = order.compactMap { status -> HistoryChip? in
            guard let count = counts[status], count > 0 else { return nil }
            return HistoryChip(label: Self.chipLabel(for: status), count: count, color: Self.chipColor(for: status))
        }
        let rest = counts
            .filter { !order.contains($0.key) && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { HistoryChip(label: $0.key.replacingOccurrences(of: "_", with: " "), count: $0.value, color: .secondary) }
        return Array((known + rest).prefix(4))
    }

    private static func chipLabel(for status: String) -> String {
        status == "in_progress" ? "running" : status
    }

    private static func chipColor(for status: String) -> Color {
        switch status {
        case "success": .green
        case "failure": .red
        case "cancelled": .secondary
        case "in_progress": .blue
        case "queued": .yellow
        default: .secondary
        }
    }
}

private struct StatTile: View {
    var value: Int
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.value, format: .number)
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.92))
            Text(self.label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
