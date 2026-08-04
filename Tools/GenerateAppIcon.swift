// Regenerates the VirtualShift app icons and the repository logo.
//
//   swift Tools/GenerateAppIcon.swift .
//
// One mark is used everywhere: a bicycle sprocket with an upward shift chevron
// in the hub. The app icons are opaque squares, as iOS requires; the repository
// logo keeps its rounded corners and alpha.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let c = size / 2

func ctx(opaque: Bool) -> CGContext {
    CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue
                                : CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func rgb(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
}

/// A bicycle sprocket: many shallow teeth with clipped points, not the deep
/// square teeth of a machine gear.
func sprocket(teeth: Int, tip: Double, root: Double, tipFrac: Double) -> CGPath {
    let p = CGMutablePath()
    let step = 2 * Double.pi / Double(teeth)
    let half = step / 2
    let t = half * tipFrac
    func pt(_ r: Double, _ a: Double) -> CGPoint {
        CGPoint(x: c + r * cos(a), y: c + r * sin(a))
    }
    for i in 0..<teeth {
        let a = Double(i) * step - Double.pi / 2
        p.addArc(center: CGPoint(x: c, y: c), radius: root,
                 startAngle: a - half + t * 0.9, endAngle: a - t * 1.5, clockwise: false)
        p.addLine(to: pt(tip, a - t * 0.5))
        p.addLine(to: pt(tip, a + t * 0.5))
        p.addLine(to: pt(root, a + t * 1.5))
    }
    p.closeSubpath()
    return p
}

func chevron(width: Double, rise: Double, offsetY: Double) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c - width, y: c + offsetY - rise / 2))
    p.addLine(to: CGPoint(x: c, y: c + offsetY + rise / 2))
    p.addLine(to: CGPoint(x: c + width, y: c + offsetY - rise / 2))
    return p
}

func draw(teeth: Int, tip: Double, root: Double, hub: Double, tipFrac: Double,
          chevW: Double, chevRise: Double, chevLine: Double,
          top: CGColor, bottom: CGColor, mark: CGColor, rounded: Bool, to url: URL) {
    let g = ctx(opaque: !rounded)
    if rounded {
        let r = size * 0.2237
        g.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                         cornerWidth: r, cornerHeight: r, transform: nil))
        g.clip()
    }
    g.drawLinearGradient(
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [top, bottom] as CFArray, locations: [0, 1])!,
        start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    let ring = CGMutablePath()
    ring.addPath(sprocket(teeth: teeth, tip: tip, root: root, tipFrac: tipFrac))
    ring.addEllipse(in: CGRect(x: c - hub, y: c - hub, width: hub * 2, height: hub * 2))
    g.addPath(ring)
    g.setFillColor(mark)
    g.fillPath(using: .evenOdd)

    g.addPath(chevron(width: chevW, rise: chevRise, offsetY: -chevRise * 0.14))
    g.setStrokeColor(mark)
    g.setLineWidth(chevLine)
    g.setLineCap(.round)
    g.setLineJoin(.round)
    g.strokePath()

    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, g.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let repo = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

/// One shape for everything: a bicycle sprocket with a shift chevron in the hub.
func mark(top: CGColor, bottom: CGColor, tint: CGColor, rounded: Bool, path: String) {
    let url = repo.appendingPathComponent(path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    draw(teeth: 20, tip: 414, root: 348, hub: 242, tipFrac: 0.5,
         chevW: 150, chevRise: 134, chevLine: 64,
         top: top, bottom: bottom, mark: tint, rounded: rounded, to: url)
    print("wrote \(path)")
}

let blueTop = rgb(64, 156, 255), blueBottom = rgb(10, 74, 214)
let labTop = rgb(116, 124, 138), labBottom = rgb(42, 46, 54)

mark(top: blueTop, bottom: blueBottom, tint: white, rounded: false,
     path: "VirtualShiftProduct/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
mark(top: labTop, bottom: labBottom, tint: rgb(255, 159, 10), rounded: false,
     path: "VirtualShift/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
mark(top: blueTop, bottom: blueBottom, tint: white, rounded: true, path: "docs/logo.png")
