import AppKit

enum StatusBarImage {
    private static let graphImageSize = NSSize(width: 58, height: 22)

    static func renderGraph(history: [Int], active: Int) -> NSImage {
        let size = Self.graphImageSize
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let graphRect = NSRect(x: 0, y: 3, width: size.width - 2, height: 16)
        drawGraph(
            history: history,
            in: graphRect,
            active: active,
            activeColor: NSColor.labelColor,
            inactiveColor: NSColor.labelColor.withAlphaComponent(0.35),
            barWidth: 2,
            spacing: 1,
            cornerRadius: 1
        )

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func renderGraphForExport(history: [Int], active: Int, scale: CGFloat = 6) -> NSImage {
        let scale = max(1, scale)
        let size = NSSize(width: Self.graphImageSize.width * scale, height: Self.graphImageSize.height * scale)
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let graphRect = NSRect(x: 0, y: 3 * scale, width: size.width - 2 * scale, height: 16 * scale)
        drawGraph(
            history: history,
            in: graphRect,
            active: active,
            activeColor: NSColor.labelColor,
            inactiveColor: NSColor.labelColor.withAlphaComponent(0.35),
            barWidth: 2 * scale,
            spacing: scale,
            cornerRadius: scale
        )

        image.unlockFocus()
        image.isTemplate = false
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
        let values = Array(history.suffix(18))
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
