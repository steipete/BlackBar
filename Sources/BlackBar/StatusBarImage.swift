import AppKit

enum StatusBarImage {
    private enum Metrics {
        static let imageSize = NSSize(width: 58, height: 22)
        static let graphTopPadding: CGFloat = 3
        static let graphTrailingPadding: CGFloat = 2
        static let graphHeight: CGFloat = 16
        static let barWidth: CGFloat = 2
        static let spacing: CGFloat = 1
        static let cornerRadius: CGFloat = 1
        static let maxBars = 18
    }

    static func renderGraph(history: [Int], active: Int) -> NSImage {
        Self.renderGraph(history: history, active: active, scale: 1, isTemplate: true)
    }

    static func renderGraphForExport(history: [Int], active: Int, scale: CGFloat = 6) -> NSImage {
        Self.renderGraph(history: history, active: active, scale: max(1, scale), isTemplate: false)
    }

    private static func renderGraph(
        history: [Int],
        active: Int,
        scale: CGFloat,
        isTemplate: Bool
    ) -> NSImage {
        let size = NSSize(width: Metrics.imageSize.width * scale, height: Metrics.imageSize.height * scale)
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let graphRect = NSRect(
            x: 0,
            y: Metrics.graphTopPadding * scale,
            width: size.width - Metrics.graphTrailingPadding * scale,
            height: Metrics.graphHeight * scale
        )
        drawGraph(
            history: history,
            in: graphRect,
            active: active,
            activeColor: NSColor.labelColor,
            inactiveColor: NSColor.labelColor.withAlphaComponent(0.35),
            barWidth: Metrics.barWidth * scale,
            spacing: Metrics.spacing * scale,
            cornerRadius: Metrics.cornerRadius * scale
        )

        image.unlockFocus()
        image.isTemplate = isTemplate
        return image
    }

    private static func drawGraph(
        history: [Int],
        in rect: NSRect,
        active: Int,
        activeColor: NSColor,
        inactiveColor: NSColor,
        barWidth: CGFloat,
        spacing: CGFloat,
        cornerRadius: CGFloat
    ) {
        let values = Array(history.suffix(Metrics.maxBars))
        let maxValue = max(values.max() ?? active, active, 1)
        let startX = rect.maxX - CGFloat(values.count) * (barWidth + spacing)

        inactiveColor.setStroke()
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: rect.minX, y: rect.minY))
        baseline.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        baseline.stroke()

        for (index, value) in values.enumerated() {
            let height = max(CGFloat(2), rect.height * CGFloat(value) / CGFloat(maxValue))
            let x = max(rect.minX, startX + CGFloat(index) * (barWidth + spacing))
            let y = rect.minY
            let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)
            (value == 0 ? inactiveColor : activeColor).setFill()
            path.fill()
        }
    }
}
