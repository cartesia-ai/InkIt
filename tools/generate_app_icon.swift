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
        NSColor(calibratedRed: 0.055, green: 0.060, blue: 0.075, alpha: 1),
        NSColor(calibratedRed: 0.105, green: 0.095, blue: 0.115, alpha: 1),
        NSColor(calibratedRed: 0.018, green: 0.024, blue: 0.038, alpha: 1),
    ])?.draw(in: outer, angle: 45)

    context.saveGState()
    outer.addClip()

    let glow = NSBezierPath(ovalIn: CGRect(x: s(520), y: s(555), width: s(410), height: s(330)))
    NSGradient(colors: [
        NSColor(calibratedRed: 0.440, green: 0.400, blue: 0.500, alpha: 0.30),
        NSColor(calibratedRed: 0.440, green: 0.400, blue: 0.500, alpha: 0.00),
    ])?.draw(in: glow, relativeCenterPosition: NSPoint(x: 0.18, y: 0.12))

    let warmGlow = NSBezierPath(ovalIn: CGRect(x: s(-70), y: s(-75), width: s(500), height: s(420)))
    NSGradient(colors: [
        NSColor(calibratedRed: 0.920, green: 0.600, blue: 0.240, alpha: 0.26),
        NSColor(calibratedRed: 1.000, green: 0.670, blue: 0.290, alpha: 0.00),
    ])?.draw(in: warmGlow, relativeCenterPosition: NSPoint(x: -0.12, y: -0.10))

    context.restoreGState()

    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    outer.lineWidth = s(9)
    outer.stroke()

    let nibShadow = NSBezierPath()
    nibShadow.move(to: NSPoint(x: s(340), y: s(760)))
    nibShadow.line(to: NSPoint(x: s(692), y: s(760)))
    nibShadow.line(to: NSPoint(x: s(812), y: s(420)))
    nibShadow.curve(to: NSPoint(x: s(512), y: s(185)), controlPoint1: NSPoint(x: s(738), y: s(318)), controlPoint2: NSPoint(x: s(640), y: s(225)))
    nibShadow.curve(to: NSPoint(x: s(212), y: s(420)), controlPoint1: NSPoint(x: s(384), y: s(225)), controlPoint2: NSPoint(x: s(286), y: s(318)))
    nibShadow.close()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s(22)), blur: s(34), color: NSColor.black.withAlphaComponent(0.34).cgColor)
    NSColor(calibratedRed: 0.010, green: 0.030, blue: 0.060, alpha: 0.58).setFill()
    nibShadow.fill()
    context.restoreGState()

    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: s(350), y: s(782)))
    nib.line(to: NSPoint(x: s(674), y: s(782)))
    nib.line(to: NSPoint(x: s(792), y: s(420)))
    nib.curve(to: NSPoint(x: s(512), y: s(206)), controlPoint1: NSPoint(x: s(726), y: s(318)), controlPoint2: NSPoint(x: s(628), y: s(232)))
    nib.curve(to: NSPoint(x: s(232), y: s(420)), controlPoint1: NSPoint(x: s(396), y: s(232)), controlPoint2: NSPoint(x: s(298), y: s(318)))
    nib.close()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.000, green: 0.975, blue: 0.885, alpha: 1),
        NSColor(calibratedRed: 0.960, green: 0.835, blue: 0.590, alpha: 1),
        NSColor(calibratedRed: 0.720, green: 0.520, blue: 0.285, alpha: 1),
    ])?.draw(in: nib, angle: -65)

    NSColor(calibratedWhite: 1, alpha: 0.78).setStroke()
    nib.lineWidth = s(12)
    nib.stroke()

    let slit = NSBezierPath()
    slit.move(to: NSPoint(x: s(512), y: s(702)))
    slit.line(to: NSPoint(x: s(512), y: s(396)))
    NSColor(calibratedRed: 0.020, green: 0.022, blue: 0.035, alpha: 0.86).setStroke()
    slit.lineWidth = s(34)
    slit.lineCapStyle = .round
    slit.stroke()

    let dot = NSBezierPath(ovalIn: CGRect(x: s(454), y: s(550), width: s(116), height: s(116)))
    NSGradient(colors: [
        NSColor(calibratedRed: 0.010, green: 0.012, blue: 0.022, alpha: 1),
        NSColor(calibratedRed: 0.050, green: 0.042, blue: 0.070, alpha: 1),
    ])?.draw(in: dot, angle: 90)

    let waveColor = NSColor(calibratedRed: 1.000, green: 0.575, blue: 0.185, alpha: 1)
    waveColor.setStroke()
    for (index, height) in [118, 190, 268, 190, 118].enumerated() {
        let x = s(362 + CGFloat(index) * 75)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: s(332) - s(CGFloat(height) / 2)))
        path.line(to: NSPoint(x: x, y: s(332) + s(CGFloat(height) / 2)))
        path.lineCapStyle = .round
        path.lineWidth = s(34)
        path.stroke()
    }

    let inkDrop = NSBezierPath()
    inkDrop.move(to: NSPoint(x: s(703), y: s(728)))
    inkDrop.curve(to: NSPoint(x: s(750), y: s(626)), controlPoint1: NSPoint(x: s(742), y: s(676)), controlPoint2: NSPoint(x: s(750), y: s(656)))
    inkDrop.curve(to: NSPoint(x: s(693), y: s(568)), controlPoint1: NSPoint(x: s(750), y: s(591)), controlPoint2: NSPoint(x: s(725), y: s(568)))
    inkDrop.curve(to: NSPoint(x: s(636), y: s(626)), controlPoint1: NSPoint(x: s(660), y: s(568)), controlPoint2: NSPoint(x: s(636), y: s(591)))
    inkDrop.curve(to: NSPoint(x: s(703), y: s(728)), controlPoint1: NSPoint(x: s(636), y: s(657)), controlPoint2: NSPoint(x: s(663), y: s(681)))
    inkDrop.close()
    NSColor(calibratedRed: 0.012, green: 0.014, blue: 0.028, alpha: 0.88).setFill()
    inkDrop.fill()

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
