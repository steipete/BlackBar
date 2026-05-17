import AppKit
import Testing
@testable import BlackBar

@Suite("Graph export")
struct GraphExportTests {
    @Test("export render uses scaled dimensions")
    func exportRenderUsesScaledDimensions() {
        let image = StatusBarImage.renderGraphForExport(
            history: [0, 1, 2, 4, 8, 16, 8, 4, 2, 1],
            active: 16,
            scale: 6
        )

        #expect(image.size == NSSize(width: 348, height: 132))
        #expect(image.isTemplate == false)
    }

    @Test("saved graph is a readable PNG")
    func savedGraphIsReadablePNG() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = StatusBarImage.renderGraphForExport(history: [1, 3, 5, 7, 9], active: 9, scale: 2)
        let url = try GraphExport.saveToDownloads(
            image,
            downloadsDirectory: directory,
            date: Date(timeIntervalSince1970: 0)
        )

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent == "BlackBar-1970-01-01T00-00-00Z.png")

        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(NSImage(data: data)?.size == image.size)
    }

    @Test("clipboard write exposes a readable image")
    func clipboardWriteExposesReadableImage() throws {
        let pasteboard = NSPasteboard(name: .init("BlackBarGraphExportTests-\(UUID().uuidString)"))
        let image = StatusBarImage.renderGraphForExport(history: [2, 4, 8, 4, 2], active: 8, scale: 2)

        try GraphExport.writeToPasteboard(image, pasteboard: pasteboard)

        #expect(pasteboard.canReadObject(forClasses: [NSImage.self], options: nil))
        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        #expect(images?.first?.size == image.size)
    }
}
