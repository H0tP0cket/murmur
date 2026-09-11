import AppKit

// Compiled with LogoGeometry.swift by make-icon.sh. All outputs share one path.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let brand = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
for (name, fill) in [("OblivionMark", "#F5F5F5"), ("OblivionMark-Black", "#181818")] {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="none">
      <title>Oblivion</title>
      <desc>Two flowing veils form an O around a central void.</desc>
      <path fill="\(fill)" d="\(LogoGeometry.svgPath)"/>
    </svg>
    """
    try svg.write(to: brand.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
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
        cg.saveGState()
        cg.translateBy(x: 166, y: 858)
        cg.scaleBy(x: 692 / 256, y: -692 / 256)
        cg.addPath(LogoGeometry.path)
        cg.setFillColor(NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1).cgColor)
        cg.fillPath()
        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: output.appendingPathComponent(name))
        if pixels == 1024 { try data.write(to: brand.appendingPathComponent("AppIcon.png")) }
    }
}
