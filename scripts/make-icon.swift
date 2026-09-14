import AppKit

// Compiled with BrandArtwork.swift by make-icon.sh. All outputs share one path.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let brand = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
let mark = BrandArtwork.mark(from: brand.appendingPathComponent("MurMurSource.png"))!
mark.isTemplate = false
let markBitmap = NSBitmapImageRep(data: mark.tiffRepresentation!)!
try markBitmap.representation(using: .png, properties: [:])!.write(to: brand.appendingPathComponent("MurMurMark.png"))
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
        NSColor(srgbRed: 0.095, green: 0.095, blue: 0.095, alpha: 1).setFill(); base.fill()
        let width: CGFloat = 696
        let height = width * mark.size.height / mark.size.width
        mark.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: output.appendingPathComponent(name))
        if pixels == 1024 { try data.write(to: brand.appendingPathComponent("AppIcon.png")) }
    }
}
