import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift make_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let side = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to allocate icon bitmap\n", stderr)
    exit(3)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(x: 0, y: 0, width: side, height: side)
NSColor.clear.setFill()
canvas.fill()

let tileRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 205, yRadius: 205)

NSGraphicsContext.current?.saveGraphicsState()
let tileShadow = NSShadow()
tileShadow.shadowBlurRadius = 44
tileShadow.shadowOffset = NSSize(width: 0, height: -18)
tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
tileShadow.set()
NSGradient(
    colors: [
        NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.23, alpha: 1),
        NSColor(calibratedRed: 0.055, green: 0.064, blue: 0.085, alpha: 1)
    ]
)?.draw(in: tile, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.12).setStroke()
tile.lineWidth = 3
tile.stroke()

let orbRect = NSRect(x: 206, y: 206, width: 612, height: 612)
let orb = NSBezierPath(ovalIn: orbRect)

NSGraphicsContext.current?.saveGraphicsState()
let orbShadow = NSShadow()
orbShadow.shadowBlurRadius = 42
orbShadow.shadowOffset = NSSize(width: 0, height: -14)
orbShadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
orbShadow.set()
NSGradient(
    colors: [
        NSColor(calibratedWhite: 1, alpha: 0.22),
        NSColor(calibratedWhite: 1, alpha: 0.055)
    ],
    atLocations: [0, 1],
    colorSpace: .deviceRGB
)?.draw(in: orb, relativeCenterPosition: NSPoint(x: -0.32, y: 0.34))
NSGraphicsContext.current?.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.28).setStroke()
orb.lineWidth = 4
orb.stroke()

let trackRect = orbRect.insetBy(dx: 64, dy: 64)
let track = NSBezierPath(ovalIn: trackRect)
NSColor.white.withAlphaComponent(0.11).setStroke()
track.lineWidth = 50
track.stroke()

let center = NSPoint(x: trackRect.midX, y: trackRect.midY)
let radius = trackRect.width / 2
let progress = NSBezierPath()
progress.appendArc(
    withCenter: center,
    radius: radius,
    startAngle: 94,
    endAngle: -196,
    clockwise: true
)
progress.lineCapStyle = .round
progress.lineWidth = 50

NSGraphicsContext.current?.saveGraphicsState()
let glow = NSShadow()
glow.shadowBlurRadius = 26
glow.shadowOffset = .zero
glow.shadowColor = NSColor.systemBlue.withAlphaComponent(0.48)
glow.set()
NSColor(calibratedRed: 0.09, green: 0.55, blue: 1, alpha: 1).setStroke()
progress.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

let coreRect = NSRect(x: 432, y: 432, width: 160, height: 160)
let core = NSBezierPath(ovalIn: coreRect)
NSGradient(
    colors: [
        NSColor(calibratedRed: 0.45, green: 0.78, blue: 1, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.45, blue: 1, alpha: 1)
    ]
)?.draw(in: core, angle: -60)

let highlight = NSBezierPath(
    ovalIn: NSRect(x: 470, y: 522, width: 62, height: 24)
)
NSColor.white.withAlphaComponent(0.55).setFill()
highlight.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode icon PNG\n", stderr)
    exit(4)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
