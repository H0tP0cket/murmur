import Foundation
import CoreGraphics

/// Shared vector master for the native UI, app icon, and SVG exports.
/// Two tapered veils form an O around an untouched central void.
enum LogoGeometry {
    enum Command {
        case move(CGFloat, CGFloat)
        case curve(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        case close
    }

    static let commands: [Command] = [
        .move(142, 28),
        .curve(69, 20, 24, 48, 24, 120),
        .curve(24, 176, 57, 216, 105, 232),
        .curve(90, 198, 74, 175, 74, 135),
        .curve(74, 77, 99, 51, 142, 28),
        .close,
        .move(114, 228),
        .curve(187, 236, 232, 208, 232, 136),
        .curve(232, 80, 199, 40, 151, 24),
        .curve(166, 58, 182, 81, 182, 121),
        .curve(182, 179, 157, 205, 114, 228),
        .close
    ]

    static var path: CGPath {
        let path = CGMutablePath()
        for command in commands {
            switch command {
            case let .move(x, y): path.move(to: CGPoint(x: x, y: y))
            case let .curve(x1, y1, x2, y2, x, y):
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    static var svgPath: String {
        func values(_ numbers: CGFloat...) -> String { numbers.map { String(format: "%g", Double($0)) }.joined(separator: " ") }
        return commands.map { command in
            switch command {
            case let .move(x, y): return "M" + values(x, y)
            case let .curve(x1, y1, x2, y2, x, y): return "C" + values(x1, y1, x2, y2, x, y)
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }
}
