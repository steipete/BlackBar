import Charts
import SwiftUI

struct MenuHeaderView: View {
    let snapshot: DashboardSnapshot
    let history: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionCaption("Active vCPU")
                    Text(self.snapshot.usage.activeVCPU, format: .number)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary.opacity(0.95), .primary.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer()
                UsageSummaryView(samples: self.chartSamples, rangeLabel: self.chartRangeLabel)
                    .padding(.bottom, 2)
            }

            UsageTrendChart(samples: self.chartSamples, rangeLabel: self.chartRangeLabel)
                .frame(height: 74)
                .overlay {
                    RightClickExportOverlay { saveToDownloads in
                        self.exportUsageGraph(saveToDownloads: saveToDownloads)
                    }
                }

            PlatformLegendView(platformUsage: self.snapshot.usage.platformUsage)

            if !self.snapshot.usage.workflowDistribution.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.08))
                WorkflowRunDistributionChart(
                    buckets: self.snapshot.usage.workflowDistribution,
                    onRightClick: { saveToDownloads in
                        self.exportWorkflowGraph(saveToDownloads: saveToDownloads)
                    }
                )
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

    @MainActor
    private func exportUsageGraph(saveToDownloads: Bool) {
        self.exportGraph(
            title: "BlackBar vCPU Usage",
            subtitle: self.chartRangeLabel,
            filenamePrefix: "BlackBar-vCPU",
            saveToDownloads: saveToDownloads
        ) {
            VStack(alignment: .leading, spacing: 12) {
                UsageTrendChart(samples: self.chartSamples, rangeLabel: self.chartRangeLabel)
                    .frame(height: 220)
                HStack(alignment: .top) {
                    PlatformLegendView(platformUsage: self.snapshot.usage.platformUsage)
                    Spacer()
                    UsageSummaryView(samples: self.chartSamples, rangeLabel: self.chartRangeLabel)
                }
            }
        }
    }

    @MainActor
    private func exportWorkflowGraph(saveToDownloads: Bool) {
        self.exportGraph(
            title: "BlackBar Workflow Runs",
            subtitle: "24h runs",
            filenamePrefix: "BlackBar-workflow-runs",
            saveToDownloads: saveToDownloads
        ) {
            WorkflowRunDistributionChart(
                buckets: self.snapshot.usage.workflowDistribution,
                chartHeight: 220
            )
        }
    }

    @MainActor
    private func exportGraph<Content: View>(
        title: String,
        subtitle: String,
        filenamePrefix: String,
        saveToDownloads: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        do {
            let image = try GraphExport.image(
                from: GraphExportCard(title: title, subtitle: subtitle) {
                    content()
                },
                size: CGSize(width: 720, height: 480)
            )
            if saveToDownloads {
                _ = try GraphExport.saveToDownloads(image, filenamePrefix: filenamePrefix)
            } else {
                try GraphExport.writeToPasteboard(image)
            }
        } catch {
            NSLog("BlackBar graph export failed: \(error.localizedDescription)")
        }
    }
}

private struct GraphExportCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.title)
                        .font(.system(size: 24, weight: .semibold))
                    Text(self.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            self.content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RightClickExportOverlay: View {
    let export: (Bool) -> Void

    var body: some View {
        MouseLocationReader(
            onMoved: { _ in },
            onRightMouseUp: { modifiers in
                self.export(modifiers.contains(.shift))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

struct SectionCaption: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(self.text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct LegendChip: View {
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(self.color)
                .frame(width: 5, height: 5)
            Text(self.label)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct SummaryMetricsView: View {
    var caption: String
    var metrics: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            SectionCaption(self.caption)
            ForEach(self.metrics, id: \.label) { metric in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(metric.value)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
        }
    }
}

enum StatusPalette {
    static func color(for status: BlacksmithStatus) -> Color {
        if !status.incidents.isEmpty { return .red }
        if !status.maintenances.isEmpty { return .blue }
        return status.pageStatus.uppercased() == "UP" ? .green : .orange
    }

    static func foreground(for status: BlacksmithStatus, isHighlighted: Bool) -> Color {
        if isHighlighted { return .white }
        return self.color(for: status)
    }

    static func background(for status: BlacksmithStatus, isHighlighted: Bool) -> Color {
        if isHighlighted { return .white.opacity(0.18) }
        return self.color(for: status).opacity(0.16)
    }
}

private struct WorkflowDistributionSummaryView: View {
    var buckets: [WorkflowRunDistributionBucket]

    var body: some View {
        SummaryMetricsView(caption: "24h runs", metrics: [
            (label: "peak", value: peak.formatted(.number)),
            (label: "avg", value: Self.durationText(avgDuration)),
        ])
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
    var chartHeight: CGFloat = 68
    var onRightClick: ((Bool) -> Void)?
    @State private var selectedBucketID: Date?

    var body: some View {
        let model = Self.makeModel(buckets: self.buckets)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                SectionCaption("Workflow runs")
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
                    .cornerRadius(2.5)
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
            .frame(height: self.chartHeight)
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
                        MouseLocationReader(
                            onMoved: { location in
                                self.updateSelection(location: location, model: model, proxy: proxy, geo: geo)
                            },
                            onRightMouseUp: { modifiers in
                                self.onRightClick?(modifiers.contains(.shift))
                            }
                        )
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
                .minimumScaleFactor(0.8)
                .frame(height: 14, alignment: .leading)

            HStack(spacing: 5) {
                ForEach(Self.presentStatuses(in: model.buckets), id: \.self) { status in
                    LegendChip(label: status, color: Self.color(for: status))
                }
                LegendChip(label: "avg", color: Self.durationColor)
                Spacer(minLength: 0)
            }
        }
    }

    private static let statuses = ["success", "cancelled", "failure", "running", "queued"]

    /// Legend only lists statuses that occur in the window, so the chips fit the menu width.
    private static func presentStatuses(in buckets: [WorkflowRunDistributionBucket]) -> [String] {
        var counts: [String: Int] = [:]
        for bucket in buckets {
            counts["success", default: 0] += bucket.successCount
            counts["cancelled", default: 0] += bucket.cancelledCount
            counts["failure", default: 0] += bucket.failureCount
            counts["running", default: 0] += bucket.inProgressCount
            counts["queued", default: 0] += bucket.queuedCount
        }
        return self.statuses.filter { counts[$0, default: 0] > 0 }
    }
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


private struct UsageSummaryView: View {
    var samples: [CoreUsageHistorySample]
    var rangeLabel: String

    var body: some View {
        SummaryMetricsView(caption: rangeLabel, metrics: [
            (label: "peak", value: peak.formatted(.number)),
            (label: "avg", value: average.formatted(.number)),
        ])
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

            self.drawGrid(in: &context, size: size)

            // Stacked layers bottom-up; each boundary is the cumulative total so far.
            let lower = [CGFloat](repeating: size.height, count: samples.count)
            let amd = self.boundary(samples.map(\.amd64.vcpus), stackedOn: samples.map { _ in 0 }, maxTotal: maxTotal, size: size)
            let arm = self.boundary(samples.map(\.arm64.vcpus), stackedOn: samples.map(\.amd64.vcpus), maxTotal: maxTotal, size: size)
            let mac = self.boundary(samples.map(\.total.vcpus), stackedOn: samples.map { _ in 0 }, maxTotal: maxTotal, size: size)

            self.fillLayer(upper: amd, lower: lower, color: .indigo, size: size, context: &context)
            self.fillLayer(upper: arm, lower: amd, color: .cyan, size: size, context: &context)
            self.fillLayer(upper: mac, lower: arm, color: .pink, size: size, context: &context)

            let line = self.polyline(mac, size: size)
            context.stroke(line, with: .color(.primary.opacity(0.6)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("\(rangeLabel) usage")
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
            var path = Path()
            let y = size.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 1)
        }
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
        baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
        context.stroke(baseline, with: .color(.secondary.opacity(0.22)), lineWidth: 1)
    }

    /// Y positions of the stacked boundary `base + value` per sample.
    private func boundary(_ values: [Int], stackedOn base: [Int], maxTotal: Int, size: CGSize) -> [CGFloat] {
        zip(values, base).map { value, base in
            size.height - size.height * CGFloat(value + base) / CGFloat(maxTotal)
        }
    }

    private func xPosition(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        count > 1 ? CGFloat(index) / CGFloat(count - 1) * width : width / 2
    }

    private func polyline(_ ys: [CGFloat], size: CGSize) -> Path {
        var path = Path()
        guard let first = ys.first else { return path }
        guard ys.count > 1 else {
            path.move(to: CGPoint(x: 0, y: first))
            path.addLine(to: CGPoint(x: size.width, y: first))
            return path
        }
        path.move(to: CGPoint(x: 0, y: first))
        for (index, y) in ys.enumerated().dropFirst() {
            path.addLine(to: CGPoint(x: self.xPosition(index, count: ys.count, width: size.width), y: y))
        }
        return path
    }

    private func fillLayer(
        upper: [CGFloat],
        lower: [CGFloat],
        color: Color,
        size: CGSize,
        context: inout GraphicsContext)
    {
        guard zip(upper, lower).contains(where: { $0 < $1 - 0.25 }) else { return }
        var path = Path()
        let count = upper.count
        if count == 1 {
            path.addRect(CGRect(x: 0, y: upper[0], width: size.width, height: max(0, lower[0] - upper[0])))
        } else {
            path.move(to: CGPoint(x: 0, y: upper[0]))
            for index in 1..<count {
                path.addLine(to: CGPoint(x: self.xPosition(index, count: count, width: size.width), y: upper[index]))
            }
            for index in stride(from: count - 1, through: 0, by: -1) {
                path.addLine(to: CGPoint(x: self.xPosition(index, count: count, width: size.width), y: lower[index]))
            }
            path.closeSubpath()
        }
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [color.opacity(0.85), color.opacity(0.3)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        )
        context.fill(path, with: shading)
    }
}

private struct PlatformLegendView: View {
    var platformUsage: [String: CoreUsage]

    var body: some View {
        HStack(spacing: 6) {
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
        LegendChip(label: "\(label) \(usage?.vcpus ?? 0)v/\(usage?.jobs ?? 0)j", color: color)
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
