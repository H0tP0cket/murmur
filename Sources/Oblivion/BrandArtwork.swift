import AppKit

/// Use the supplied artwork as a template, without redrawing or changing its silhouette.
/// Shared by the app and icon packager so every surface uses the same mark.
enum BrandArtwork {
    static func mark(from url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = try? Data(contentsOf: url), let bitmap = NSBitmapImageRep(data: data) else { return nil }
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = 0, maxY = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
        let size = NSSize(width: cropped.width, height: cropped.height)
        let original = NSImage(cgImage: cropped, size: size)
        let result = NSImage(size: size, flipped: false) { rect in
            original.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        result.isTemplate = true
        return result
    }
}
