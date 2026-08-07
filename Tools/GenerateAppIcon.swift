// Regenerates the Virtual Gears app icon, repository logo, and banner.
//
//   swift Tools/GenerateAppIcon.swift .
//
// One mark is used everywhere: a bicycle sprocket with an upward shift chevron
// in the hub. The app icons are opaque squares, as iOS requires; the repository
// logo keeps its rounded corners and alpha.

import CoreGraphics
import CoreText
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

/// The sprocket and chevron on their own, with a transparent background, so the
/// banner can place the same artwork next to the wordmark.
func markImage(tint: CGColor) -> CGImage {
    let g = CGContext(data: nil, width: Int(size), height: Int(size),
                      bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    paintMark(in: g, teeth: 20, tip: 414, root: 348, hub: 242, tipFrac: 0.5,
              chevW: 150, chevRise: 134, chevLine: 64, tint: tint)
    return g.makeImage()!
}

func paintMark(in g: CGContext, teeth: Int, tip: Double, root: Double,
               hub: Double, tipFrac: Double, chevW: Double, chevRise: Double,
               chevLine: Double, tint: CGColor) {
    let ring = CGMutablePath()
    ring.addPath(sprocket(teeth: teeth, tip: tip, root: root, tipFrac: tipFrac))
    ring.addEllipse(in: CGRect(x: c - hub, y: c - hub, width: hub * 2, height: hub * 2))
    g.addPath(ring)
    g.setFillColor(tint)
    g.fillPath(using: .evenOdd)

    g.addPath(chevron(width: chevW, rise: chevRise, offsetY: -chevRise * 0.14))
    g.setStrokeColor(tint)
    g.setLineWidth(chevLine)
    g.setLineCap(.round)
    g.setLineJoin(.round)
    g.strokePath()
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// A wide banner for the repository's social preview: the mark, the name and one
/// line saying what the app does.
func banner(to url: URL) {
    let width = 1280.0, height = 640.0
    let g = CGContext(data: nil, width: Int(width), height: Int(height),
                      bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    g.drawLinearGradient(
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: [rgb(20, 34, 66), rgb(8, 14, 30)] as CFArray,
                   locations: [0, 1])!,
        start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])

    let markSize = 300.0
    g.draw(markImage(tint: rgb(90, 170, 255)),
           in: CGRect(x: 120, y: (height - markSize) / 2, width: markSize, height: markSize))

    func text(_ string: String, size fontSize: Double, weight: String,
              color: CGColor, at point: CGPoint) {
        let font = CTFontCreateWithName(weight as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: string,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            ]
        ))
        g.textPosition = point
        CTLineDraw(line, g)
    }

    let left = 120 + markSize + 70.0
    text("Virtual Gears", size: 104, weight: "HelveticaNeue-Bold",
         color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
         at: CGPoint(x: left, y: height / 2 + 24))
    text("Virtual shifting for KICKR V5", size: 42,
         weight: "HelveticaNeue", color: rgb(150, 180, 225),
         at: CGPoint(x: left, y: height / 2 - 54))

    write(g.makeImage()!, to: url)
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

    paintMark(in: g, teeth: teeth, tip: tip, root: root, hub: hub,
              tipFrac: tipFrac, chevW: chevW, chevRise: chevRise,
              chevLine: chevLine, tint: mark)
    write(g.makeImage()!, to: url)
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

mark(top: blueTop, bottom: blueBottom, tint: white, rounded: false,
     path: "VirtualGearsProduct/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
mark(top: blueTop, bottom: blueBottom, tint: white, rounded: true, path: "docs/logo.png")

banner(to: repo.appendingPathComponent("docs/banner.png"))
print("wrote docs/banner.png")
