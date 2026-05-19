import AppKit
import CoreGraphics

let outputDirectory = URL(fileURLWithPath: "tools/assets", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// DMG window is 600x400 in our make-dmg.sh. Background images need
// a @1x and a @2x in a single TIFF (or separately + named .background).
// create-dmg accepts a single PNG — for retina we'd need a multi-resolution
// asset, but a 1200x800 PNG drawn into a 600x400 window scales cleanly enough.
let baseWidth: CGFloat = 600
let baseHeight: CGFloat = 400

func drawBackground(scale: CGFloat) -> NSImage {
    let width = baseWidth * scale
    let height = baseHeight * scale
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Background fill — light gray, matches macOS Finder default
    ctx.setFillColor(NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Solid right-pointing arrow centered between icon at Finder x=160 and Applications at x=440.
    let arrowColor = NSColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1.0).cgColor
    ctx.setStrokeColor(arrowColor)
    ctx.setFillColor(arrowColor)
    ctx.setLineWidth(6 * scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let centerY = height - 200 * scale
    let shaftLength: CGFloat = 70 * scale
    let arrowSize: CGFloat = 24 * scale
    let arrowCenterX = 300 * scale
    let totalSpan = shaftLength + arrowSize
    let shaftLeft = arrowCenterX - totalSpan / 2
    let shaftRight = shaftLeft + shaftLength

    ctx.move(to: CGPoint(x: shaftLeft, y: centerY))
    ctx.addLine(to: CGPoint(x: shaftRight, y: centerY))
    ctx.strokePath()

    let tipX = shaftRight + arrowSize
    ctx.move(to: CGPoint(x: shaftRight, y: centerY + arrowSize * 0.85))
    ctx.addLine(to: CGPoint(x: tipX, y: centerY))
    ctx.addLine(to: CGPoint(x: shaftRight, y: centerY - arrowSize * 0.85))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "dmg-bg", code: 1)
    }
    try png.write(to: url)
}

let bg1x = drawBackground(scale: 1)
let bg2x = drawBackground(scale: 2)
try writePNG(bg1x, to: outputDirectory.appendingPathComponent("dmg-background.png"))
try writePNG(bg2x, to: outputDirectory.appendingPathComponent("dmg-background@2x.png"))

print("Wrote tools/assets/dmg-background.png and dmg-background@2x.png")
