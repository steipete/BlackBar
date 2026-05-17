import AppKit
import Foundation

enum GraphExport {
    static func writeToPasteboard(_ image: NSImage, pasteboard: NSPasteboard = .general) throws {
        let data = try pngData(from: image)
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw GraphExportError.pasteboardWriteFailed
        }
    }

    static func saveToDownloads(
        _ image: NSImage,
        downloadsDirectory: URL? = nil,
        date: Date = Date()
    ) throws -> URL {
        let directory = downloadsDirectory ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("BlackBar-\(timestamp(for: date)).png")
        let data = try pngData(from: image)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func pngData(from image: NSImage) throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw GraphExportError.pngEncodingFailed
        }
        return pngData
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}

enum GraphExportError: LocalizedError {
    case pasteboardWriteFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .pasteboardWriteFailed:
            "Could not write the activity graph to the clipboard."
        case .pngEncodingFailed:
            "Could not encode the activity graph as PNG."
        }
    }
}
