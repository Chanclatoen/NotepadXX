// Draws NotepadXX's app icon and writes Resources/AppIcon.icns.
//
// The icon is drawn rather than assembled from stock art for two reasons: SF
// Symbols are not licensed for use in app icons, and a drawn icon can use the
// app's own design tokens, so the thing in the Dock is the same green as the
// thing on screen.
//
// Usage: swift scripts/make-icon.swift [output-directory]
import AppKit

// MARK: - Palette, from the design system

enum Palette {
    static let brand = NSColor(srgbRed: 0x0F / 255, green: 0x8A / 255, blue: 0x63 / 255, alpha: 1)
    static let brandDeep = NSColor(srgbRed: 0x0A / 255, green: 0x5F / 255, blue: 0x45 / 255, alpha: 1)
    static let brandLift = NSColor(srgbRed: 0x2A / 255, green: 0xA8 / 255, blue: 0x7C / 255, alpha: 1)
    static let paper = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let paperEdge = NSColor(srgbRed: 0xE7 / 255, green: 0xE7 / 255, blue: 0xEA / 255, alpha: 1)
    static let rule = NSColor(srgbRed: 0xC3 / 255, green: 0xC7 / 255, blue: 0xCE / 255, alpha: 1)
    static let heading = NSColor(srgbRed: 0x1F / 255, green: 0x20 / 255, blue: 0x24 / 255, alpha: 1)
    static let caret = NSColor(srgbRed: 0x0A / 255, green: 0x6C / 255, blue: 0xFF / 255, alpha: 1)
}

/// Apple's icon grid: the shape sits inside the canvas with a margin, so the
/// Dock's own spacing works out.
func superellipse(in rect: NSRect, exponent: CGFloat = 5) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2
    let b = rect.height / 2
    let centre = NSPoint(x: rect.midX, y: rect.midY)
    let steps = 720

    for step in 0...steps {
        let theta = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(theta)
        let sinT = sin(theta)
        // |x/a|^n + |y/b|^n = 1, parameterised so the corners stay continuous.
        let x = centre.x + a * pow(abs(cosT), 2 / exponent) * (cosT < 0 ? -1 : 1)
        let y = centre.y + b * pow(abs(sinT), 2 / exponent) * (sinT < 0 ? -1 : 1)
        step == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
    }
    path.close()
    return path
}

/// Draws the icon at `size` points into the current context.
///
/// Below 64 px the artwork is simplified rather than merely scaled: five wire
/// rings and five ruled lines turn into grey mush at 16 px. Fewer, heavier
/// shapes keep the icon recognisable, which is what shipping icons do by
/// drawing each size separately.
func drawIcon(size: CGFloat) {
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let unit = size / 1024
    let compact = size < 64

    NSColor.clear.setFill()
    canvas.fill()

    // MARK: The rounded body
    let bodyInset = 100 * unit
    let body = canvas.insetBy(dx: bodyInset, dy: bodyInset)
    let shape = superellipse(in: body)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    // A vertical gradient, lighter at the top, the way light falls on a Dock
    // icon. Flat colour reads as a placeholder at large sizes.
    NSGradient(colors: [Palette.brandLift, Palette.brand, Palette.brandDeep],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
        .draw(in: body, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // A hairline inside the edge keeps the shape crisp against a light Dock.
    NSColor.black.withAlphaComponent(0.12).setStroke()
    shape.lineWidth = 2 * unit
    shape.stroke()

    // MARK: The page
    //
    // Off-centre and slightly narrow, so it reads as a sheet on a surface
    // rather than a filled rectangle.
    let page = NSRect(x: body.minX + 118 * unit,
                      y: body.minY + 92 * unit,
                      width: body.width - 236 * unit,
                      height: body.height - 176 * unit)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 26 * unit, yRadius: 26 * unit)

    // A shadow so the page lifts off the green.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 34 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -12 * unit)
    shadow.set()
    Palette.paper.setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    Palette.paperEdge.setStroke()
    pagePath.lineWidth = 2 * unit
    pagePath.stroke()

    // MARK: The binding
    //
    // Rings straddling the top edge, drawn over the page: that is how a spiral
    // pad looks head-on, and it is what still says "notepad" at 32 pt when the
    // ruled lines below have merged into a grey block.
    let ringCount = compact ? 3 : 5
    let ringSpacing = page.width / CGFloat(ringCount)
    for index in 0..<ringCount {
        let x = page.minX + ringSpacing * (CGFloat(index) + 0.5)
        // Heavier and rounder when small, so the ring survives as a shape
        // rather than thinning into the paper.
        let ringWidth = (compact ? 74 : 54) * unit
        let ringHeight = (compact ? 74 : 64) * unit
        let ring = NSRect(x: x - ringWidth / 2, y: page.maxY - ringHeight / 2,
                          width: ringWidth, height: ringHeight)
        let path = NSBezierPath(ovalIn: ring)

        // A dark pass then a light one gives the wire an edge without needing
        // a gradient that would disappear at small sizes.
        path.lineWidth = (compact ? 26 : 17) * unit
        NSColor.black.withAlphaComponent(0.22).setStroke()
        path.stroke()
        path.lineWidth = (compact ? 18 : 11) * unit
        NSColor(srgbRed: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255, alpha: 1).setStroke()
        path.stroke()
    }

    // MARK: Ruled lines and a caret
    //
    // A heading and five rules, filling the page the way a written-on pad is
    // filled. The caret at the end of the last line says editor rather than
    // notes app.
    let textLeft = page.minX + 62 * unit
    let textRight = page.maxX - 62 * unit
    let textWidth = textRight - textLeft

    let headingRect = NSRect(x: textLeft, y: page.maxY - (compact ? 200 : 172) * unit,
                             width: textWidth * (compact ? 0.62 : 0.5),
                             height: (compact ? 52 : 30) * unit)
    Palette.heading.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: headingRect, xRadius: 15 * unit, yRadius: 15 * unit).fill()

    let widths: [CGFloat] = compact ? [1.0, 0.78] : [1.0, 0.88, 0.95, 0.72, 0.45]
    for (index, fraction) in widths.enumerated() {
        let spacing: CGFloat = compact ? 130 : 84
        let firstLine: CGFloat = compact ? 330 : 258
        let y = page.maxY - (firstLine + CGFloat(index) * spacing) * unit
        let width = textWidth * fraction
        let line = NSRect(x: textLeft, y: y, width: width, height: (compact ? 44 : 20) * unit)
        Palette.rule.setFill()
        NSBezierPath(roundedRect: line, xRadius: (compact ? 22 : 10) * unit,
                     yRadius: (compact ? 22 : 10) * unit).fill()

        // A one-pixel caret at 16 px is noise, not a signal.
        if index == widths.count - 1, !compact {
            let caret = NSRect(x: textLeft + width + 22 * unit, y: y - 14 * unit,
                               width: 15 * unit, height: 48 * unit)
            Palette.caret.setFill()
            NSBezierPath(roundedRect: caret, xRadius: 7 * unit, yRadius: 7 * unit).fill()
        }
    }
}

// MARK: - Rendering

func image(size: CGFloat) -> NSBitmapImageRep? {
    let pixels = Int(size)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    drawIcon(size: size)
    NSGraphicsContext.restoreGraphicsState()
    guard let cgImage = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: cgImage)
}

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let iconset = URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects, each as a point size and a scale.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
for variant in variants {
    let pixels = CGFloat(variant.points * variant.scale)
    guard let rep = image(size: pixels), let data = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("failed at \(pixels)px\n".utf8))
        exit(1)
    }
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

// A 1024 preview, for looking at the result without opening the bundle.
if let rep = image(size: 1024), let data = rep.representation(using: .png, properties: [:]) {
    try data.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("AppIcon-preview.png"))
}

print("wrote \(iconset.path)")
