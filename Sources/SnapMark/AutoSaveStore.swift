import AppKit

enum AutoSaveStore {
    static var saveDirectory: URL {
        let directory = AppSettings.shared.saveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func newCaptureURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = "SnapMark-\(formatter.string(from: Date()))"
        return uniquePNGURL(baseName: baseName)
    }

    private static func uniquePNGURL(baseName: String) -> URL {
        var candidate = saveDirectory.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = saveDirectory
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }

        return candidate
    }

    static func save(_ image: NSImage, to url: URL) throws {
        guard let data = image.pngData else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    static func writeTemporaryImage(_ image: NSImage) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapMark-\(UUID().uuidString)")
            .appendingPathExtension("png")

        do {
            try save(image, to: url)
            return url
        } catch {
            return nil
        }
    }

}

extension NSImage {
    var snapMarkPixelSize: CGSize {
        if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }

        if let representation = representations.first {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }

        return size
    }

    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}
