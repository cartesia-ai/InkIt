import AppKit
import CoreGraphics

let outputDirectory = URL(fileURLWithPath: "InkIt/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let icons: [(String, Int)] = [
    ("app-icon-16.png", 16),
    ("app-icon-32.png", 32),
    ("app-icon-64.png", 64),
    ("app-icon-128.png", 128),
    ("app-icon-256.png", 256),
    ("app-icon-512.png", 512),
    ("app-icon-1024.png", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let scale = size / 1024
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let outerRadius = s(228)
    let outer = NSBezierPath(roundedRect: rect.insetBy(dx: s(24), dy: s(24)), xRadius: outerRadius, yRadius: outerRadius)
    NSGradient(colors: [
        NSColor(calibratedRed: 1.000, green: 0.976, blue: 0.918, alpha: 1),
        NSColor(calibratedRed: 0.965, green: 0.925, blue: 0.835, alpha: 1),
        NSColor(calibratedRed: 0.920, green: 0.855, blue: 0.725, alpha: 1),
    ])?.draw(in: outer, angle: -35)

    NSColor(calibratedWhite: 1, alpha: 0.72).setStroke()
    outer.lineWidth = s(8)
    outer.stroke()

    let paper = NSBezierPath(roundedRect: CGRect(x: s(184), y: s(120), width: s(656), height: s(694)), xRadius: s(72), yRadius: s(72))
    context.saveGState()
    context.setShadow(offset: CGSize(width: s(10), height: -s(18)), blur: s(34), color: NSColor.black.withAlphaComponent(0.16).cgColor)
    NSGradient(colors: [
        NSColor(calibratedRed: 1.000, green: 0.996, blue: 0.965, alpha: 1),
        NSColor(calibratedRed: 0.990, green: 0.955, blue: 0.850, alpha: 1),
    ])?.draw(in: paper, angle: -72)
    context.restoreGState()

    NSColor(calibratedRed: 0.790, green: 0.710, blue: 0.570, alpha: 0.38).setStroke()
    paper.lineWidth = s(8)
    paper.stroke()

    let lineColor = NSColor(calibratedRed: 0.130, green: 0.140, blue: 0.190, alpha: 1)
    lineColor.setStroke()
    for (y, width) in [(610, 330), (504, 258), (398, 250)] {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: s(270), y: s(CGFloat(y))))
        path.line(to: NSPoint(x: s(270 + CGFloat(width)), y: s(CGFloat(y))))
        path.lineCapStyle = .round
        path.lineWidth = s(42)
        path.stroke()
    }

    let pen = NSBezierPath()
    pen.move(to: NSPoint(x: s(660), y: s(646)))
    pen.line(to: NSPoint(x: s(800), y: s(506)))
    pen.line(to: NSPoint(x: s(522), y: s(228)))
    pen.line(to: NSPoint(x: s(346), y: s(192)))
    pen.line(to: NSPoint(x: s(382), y: s(368)))
    pen.close()
    context.saveGState()
    context.setShadow(offset: CGSize(width: s(8), height: -s(10)), blur: s(18), color: NSColor.black.withAlphaComponent(0.20).cgColor)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.070, green: 0.075, blue: 0.105, alpha: 1),
        NSColor(calibratedRed: 0.135, green: 0.145, blue: 0.190, alpha: 1),
    ])?.draw(in: pen, angle: 45)
    context.restoreGState()

    let penAccent = NSBezierPath()
    penAccent.move(to: NSPoint(x: s(660), y: s(646)))
    penAccent.line(to: NSPoint(x: s(800), y: s(506)))
    penAccent.line(to: NSPoint(x: s(732), y: s(438)))
    penAccent.line(to: NSPoint(x: s(592), y: s(578)))
    penAccent.close()
    NSColor(calibratedRed: 1.000, green: 0.580, blue: 0.170, alpha: 1).setFill()
    penAccent.fill()

    NSColor(calibratedRed: 0.070, green: 0.075, blue: 0.105, alpha: 1).setStroke()
    pen.lineWidth = s(8)
    pen.stroke()

    let bubble = NSBezierPath()
    bubble.move(to: NSPoint(x: s(650), y: s(386)))
    bubble.line(to: NSPoint(x: s(804), y: s(386)))
    bubble.curve(to: NSPoint(x: s(908), y: s(282)), controlPoint1: NSPoint(x: s(862), y: s(386)), controlPoint2: NSPoint(x: s(908), y: s(340)))
    bubble.curve(to: NSPoint(x: s(804), y: s(178)), controlPoint1: NSPoint(x: s(908), y: s(224)), controlPoint2: NSPoint(x: s(862), y: s(178)))
    bubble.line(to: NSPoint(x: s(744), y: s(178)))
    bubble.line(to: NSPoint(x: s(652), y: s(100)))
    bubble.line(to: NSPoint(x: s(652), y: s(182)))
    bubble.curve(to: NSPoint(x: s(542), y: s(282)), controlPoint1: NSPoint(x: s(590), y: s(187)), controlPoint2: NSPoint(x: s(542), y: s(231)))
    bubble.curve(to: NSPoint(x: s(650), y: s(386)), controlPoint1: NSPoint(x: s(542), y: s(340)), controlPoint2: NSPoint(x: s(588), y: s(386)))
    bubble.close()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s(10)), blur: s(24), color: NSColor.black.withAlphaComponent(0.20).cgColor)
    NSGradient(colors: [
        NSColor(calibratedRed: 1.000, green: 0.640, blue: 0.230, alpha: 1),
        NSColor(calibratedRed: 1.000, green: 0.500, blue: 0.110, alpha: 1),
    ])?.draw(in: bubble, angle: -72)
    context.restoreGState()

    NSColor(calibratedRed: 1.000, green: 0.820, blue: 0.500, alpha: 0.80).setStroke()
    bubble.lineWidth = s(7)
    bubble.stroke()

    NSColor(calibratedRed: 0.090, green: 0.095, blue: 0.130, alpha: 1).setFill()
    for x in [688, 752, 816] {
        NSBezierPath(ovalIn: CGRect(x: s(CGFloat(x - 15)), y: s(267), width: s(30), height: s(30))).fill()
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }

    try png.write(to: url, options: .atomic)
}

for icon in icons {
    let image = drawIcon(size: CGFloat(icon.1))
    try writePNG(image, to: outputDirectory.appendingPathComponent(icon.0))
}

print("Generated \(icons.count) app icon PNGs in \(outputDirectory.path)")
