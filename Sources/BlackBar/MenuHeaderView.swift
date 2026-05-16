import Charts
import SwiftUI

struct MenuHeaderView: View {
    let snapshot: DashboardSnapshot
    let history: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("vCPU")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Self.vcpuText(self.snapshot.usage.activeVCPU))
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer()
                UsageSummaryView(samples: self.chartSamples, rangeLabel: self.chartRangeLabel)
                    .padding(.bottom, 2)
            }

            UsageTrendChart(samples: self.chartSamples, rangeLabel: self.chartRangeLabel)
                .frame(height: 74)

            PlatformLegendView(platformUsage: self.snapshot.usage.platformUsage)

            if !self.snapshot.usage.workflowDistribution.isEmpty {
                Divider()
                    .overlay(Color.secondary.opacity(0.18))
                WorkflowRunDistributionChart(buckets: self.snapshot.usage.workflowDistribution)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(self.snapshot.isOperational ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(self.snapshot.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360, alignment: .leading)
    }

    private var chartSamples: [CoreUsageHistorySample] {
        if !snapshot.usage.historySamples.isEmpty {
            return Array(snapshot.usage.historySamples.suffix(96))
        }
        let values = history.isEmpty ? [snapshot.usage.activeVCPU] : Array(history.suffix(96))
        return values.map { value in
            CoreUsageHistorySample(
                amd64: CoreUsage(vcpus: max(0, value), jobs: 0),
                arm64: CoreUsage(vcpus: 0, jobs: 0),
                macos: CoreUsage(vcpus: 0, jobs: 0)
            )
        }
    }

    private var chartRangeLabel: String {
        snapshot.usage.historySamples.isEmpty ? "recent vCPU" : "24h vCPU"
    }

    private static func vcpuText(_ value: Int) -> String {
        String(value)
    }
}

private struct WorkflowDistributionSummaryView: View {
    var buckets: [WorkflowRunDistributionBucket]

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("24h runs")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("peak \(peak)")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text("avg \(Self.durationText(avgDuration))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var peak: Int {
        buckets.map(\.totalCount).max() ?? 0
    }

    private var avgDuration: Double {
        let weighted = buckets.reduce((seconds: 0.0, runs: 0)) { partial, bucket in
            guard let duration = bucket.avgDurationSeconds, bucket.runsWithDuration > 0 else { return partial }
            return (
                partial.seconds + duration * Double(bucket.runsWithDuration),
                partial.runs + bucket.runsWithDuration
            )
        }
        guard weighted.runs > 0 else { return 0 }
        return weighted.seconds / Double(weighted.runs)
    }

    fileprivate static func durationText(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        if rounded >= 3600 {
            let hours = rounded / 3600
            let minutes = (rounded % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if rounded >= 60 {
            let minutes = rounded / 60
            let seconds = rounded % 60
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(rounded)s"
    }
}

private struct WorkflowRunDistributionChart: View {
    private struct Point: Identifiable {
        var id: String { "\(bucket.id.timeIntervalSince1970)-\(status)" }
        var bucket: WorkflowRunDistributionBucket
        var status: String
        var count: Int
    }

    private struct Model {
        var buckets: [WorkflowRunDistributionBucket]
        var points: [Point]
        var maxCount: Int
        var maxDuration: Double
        var axisDates: [Date]
    }

    var buckets: [WorkflowRunDistributionBucket]
    @State private var selectedBucketID: Date?

    var body: some View {
        let model = Self.makeModel(buckets: self.buckets)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                Text("Workflow runs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                WorkflowDistributionSummaryView(buckets: model.buckets)
            }

            Chart {
                ForEach(model.points) { point in
                    BarMark(
                        x: .value("Hour", point.bucket.start, unit: .hour),
                        y: .value("Runs", point.count)
                    )
                    .foregroundStyle(by: .value("Status", point.status))
                    .cornerRadius(1.5)
                }
                ForEach(model.buckets) { bucket in
                    if let duration = bucket.avgDurationSeconds {
                        let scaledDuration = Self.scaledDuration(duration, maxDuration: model.maxDuration, maxCount: model.maxCount)
                        LineMark(
                            x: .value("Hour", bucket.start, unit: .hour),
                            y: .value("Avg duration", scaledDuration)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Self.durationColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        PointMark(
                            x: .value("Hour", bucket.start, unit: .hour),
                            y: .value("Avg duration", scaledDuration)
                        )
                        .foregroundStyle(Self.durationColor)
                        .symbolSize(bucket.id == self.selectedBucketID ? 34 : 14)
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: Self.statuses,
                range: Self.statuses.map(Self.color(for:))
            )
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: model.axisDates) { _ in
                    AxisGridLine().foregroundStyle(Color.clear)
                    AxisTick().foregroundStyle(Color.clear)
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .chartLegend(.hidden)
            .frame(height: 68)
            .accessibilityLabel("Workflow run distribution")
            .chartOverlay { proxy in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        if let rect = self.selectionBandRect(model: model, proxy: proxy, geo: geo) {
                            Rectangle()
                                .fill(Self.selectionBandColor)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }
                        MouseLocationReader { location in
                            self.updateSelection(location: location, model: model, proxy: proxy, geo: geo)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                }
            }

            let detail = self.detailLine(model: model)
            Text(detail)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(Self.statuses, id: \.self) { status in
                    DistributionLegendItem(label: status, color: Self.color(for: status))
                }
                DistributionLegendItem(label: "duration", color: Self.durationColor)
                Spacer(minLength: 0)
            }
        }
    }

    private static let statuses = ["success", "cancelled", "failure", "running", "queued"]
    private static let durationColor = Color.primary.opacity(0.82)
    private static let selectionBandColor = Color(nsColor: .labelColor).opacity(0.1)

    private static func makeModel(buckets: [WorkflowRunDistributionBucket]) -> Model {
        let buckets = buckets.sorted { $0.start < $1.start }
        var points: [Point] = []
        points.reserveCapacity(buckets.count * statuses.count)
        for bucket in buckets {
            points.append(Point(bucket: bucket, status: "success", count: bucket.successCount))
            points.append(Point(bucket: bucket, status: "cancelled", count: bucket.cancelledCount))
            points.append(Point(bucket: bucket, status: "failure", count: bucket.failureCount))
            points.append(Point(bucket: bucket, status: "running", count: bucket.inProgressCount))
            points.append(Point(bucket: bucket, status: "queued", count: bucket.queuedCount))
        }
        let axisDates = [buckets.first?.start, buckets.dropFirst(buckets.count / 2).first?.start, buckets.last?.start].compactMap(\.self)
        return Model(
            buckets: buckets,
            points: points.filter { $0.count > 0 },
            maxCount: max(buckets.map(\.totalCount).max() ?? 0, 1),
            maxDuration: max(buckets.compactMap(\.avgDurationSeconds).max() ?? 0, 1),
            axisDates: axisDates
        )
    }

    private static func scaledDuration(_ duration: Double, maxDuration: Double, maxCount: Int) -> Double {
        guard maxDuration > 0 else { return 0 }
        return duration / maxDuration * Double(maxCount)
    }

    private static func color(for status: String) -> Color {
        switch status {
        case "success": Color(red: 0.31, green: 0.50, blue: 0.95)
        case "cancelled": Color(red: 0.39, green: 0.42, blue: 0.46)
        case "failure": Color(red: 0.96, green: 0.25, blue: 0.44)
        case "running": Color(red: 0.27, green: 0.78, blue: 0.86)
        case "queued": Color(red: 0.94, green: 0.69, blue: 0.24)
        default: .secondary
        }
    }

    private func detailLine(model: Model) -> String {
        let bucket = self.selectedBucketID.flatMap { id in model.buckets.first { $0.id == id } } ?? model.buckets.last
        guard let bucket else { return "No workflow distribution data" }
        let time = bucket.start.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
        let duration = bucket.avgDurationSeconds.map(WorkflowDistributionSummaryView.durationText) ?? "-"
        return "\(time): \(bucket.totalCount) runs · success \(bucket.successCount) · cancelled \(bucket.cancelledCount) · failure \(bucket.failureCount) · avg \(duration)"
    }

    private func updateSelection(location: CGPoint?, model: Model, proxy: ChartProxy, geo: GeometryProxy) {
        guard let location else {
            if self.selectedBucketID != nil { self.selectedBucketID = nil }
            return
        }
        guard !model.buckets.isEmpty, let plotFrame = proxy.plotFrame else { return }
        let frame = geo[plotFrame]
        guard frame.contains(location) else { return }
        let x = location.x - frame.origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        self.selectedBucketID = model.buckets.min {
            abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
        }?.id
    }

    private func selectionBandRect(model: Model, proxy: ChartProxy, geo: GeometryProxy) -> CGRect? {
        guard let selectedBucketID,
              let index = model.buckets.firstIndex(where: { $0.id == selectedBucketID }),
              let plotFrame = proxy.plotFrame,
              let x = proxy.position(forX: model.buckets[index].start)
        else { return nil }
        let frame = geo[plotFrame]
        let width = max(5, frame.width / CGFloat(max(model.buckets.count, 1)))
        return CGRect(x: frame.origin.x + x - width / 2, y: frame.origin.y, width: width, height: frame.height)
    }
}

private struct DistributionLegendItem: View {
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct UsageSummaryView: View {
    var samples: [CoreUsageHistorySample]
    var rangeLabel: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(rangeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("peak \(peak)")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text("avg \(average)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var totals: [Int] {
        samples.map(\.total.vcpus)
    }

    private var peak: Int {
        totals.max() ?? 0
    }

    private var average: Int {
        guard !totals.isEmpty else { return 0 }
        let total = totals.reduce(0, +)
        return Int((Double(total) / Double(totals.count)).rounded())
    }
}

private struct UsageTrendChart: View {
    var samples: [CoreUsageHistorySample]
    var rangeLabel: String

    var body: some View {
        Canvas { context, size in
            let samples = self.samples.isEmpty ? [CoreUsageHistorySample(amd64: .init(vcpus: 0, jobs: 0), arm64: .init(vcpus: 0, jobs: 0), macos: .init(vcpus: 0, jobs: 0))] : self.samples
            let maxTotal = max(samples.map(\.total.vcpus).max() ?? 0, 1)
            let count = samples.count
            let gap: CGFloat = count > 64 ? 1 : 2
            let barWidth = max(1, (size.width - CGFloat(max(count - 1, 0)) * gap) / CGFloat(max(count, 1)))

            self.drawGrid(in: &context, size: size)

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + gap)
                var bottom = size.height
                self.drawSegment(value: sample.amd64.vcpus, maxTotal: maxTotal, x: x, width: barWidth, bottom: &bottom, size: size, color: .indigo, context: &context)
                self.drawSegment(value: sample.arm64.vcpus, maxTotal: maxTotal, x: x, width: barWidth, bottom: &bottom, size: size, color: .cyan, context: &context)
                self.drawSegment(value: sample.macos.vcpus, maxTotal: maxTotal, x: x, width: barWidth, bottom: &bottom, size: size, color: .pink, context: &context)
            }

            var line = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + gap) + barWidth / 2
                let y = size.height - (size.height * CGFloat(sample.total.vcpus) / CGFloat(maxTotal))
                if index == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(line, with: .color(.primary.opacity(0.78)), lineWidth: 1.4)
        }
        .accessibilityLabel("\(rangeLabel) usage")
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
            var path = Path()
            let y = size.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
        }
    }

    private func drawSegment(
        value: Int,
        maxTotal: Int,
        x: CGFloat,
        width: CGFloat,
        bottom: inout CGFloat,
        size: CGSize,
        color: Color,
        context: inout GraphicsContext)
    {
        guard value > 0 else { return }
        let height = size.height * CGFloat(value) / CGFloat(maxTotal)
        guard height >= 0.5 else { return }
        bottom -= height
        let rect = CGRect(x: x, y: bottom, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: min(2, width / 2)), with: .color(color.opacity(0.86)))
    }
}

private struct PlatformLegendView: View {
    var platformUsage: [String: CoreUsage]

    var body: some View {
        HStack(spacing: 10) {
            PlatformLegendItem(label: "amd64", usage: platformUsage["amd64"], color: .indigo)
            PlatformLegendItem(label: "arm64", usage: platformUsage["arm64"], color: .cyan)
            PlatformLegendItem(label: "mac", usage: platformUsage["macos"], color: .pink)
            Spacer(minLength: 0)
        }
    }
}

private struct PlatformLegendItem: View {
    var label: String
    var usage: CoreUsage?
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label) \(usage?.vcpus ?? 0)v/\(usage?.jobs ?? 0)j")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct Sparkline: View {
    var values: [Int]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(self.values.max() ?? 1, 1)
            let count = max(self.values.count, 1)
            let barWidth = max(2, proxy.size.width / CGFloat(max(count, 24)) - 1)

            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(self.values.suffix(48).enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(value == 0 ? Color.secondary.opacity(0.24) : Color.cyan)
                        .frame(
                            width: barWidth,
                            height: max(2, proxy.size.height * CGFloat(value) / CGFloat(maxValue))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
