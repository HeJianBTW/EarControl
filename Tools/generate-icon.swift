import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate-icon.swift output.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let tileRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 205, yRadius: 205)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
tile.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.25, alpha: 1),
    NSColor(calibratedWhite: 0.08, alpha: 1)
])!
gradient.draw(in: tile, angle: -45)

NSColor.white.withAlphaComponent(0.12).setStroke()
tile.lineWidth = 3
tile.stroke()

let cable = NSBezierPath()
cable.lineWidth = 28
cable.lineCapStyle = .round
cable.move(to: NSPoint(x: 512, y: 880))
cable.line(to: NSPoint(x: 512, y: 785))
cable.move(to: NSPoint(x: 512, y: 239))
cable.line(to: NSPoint(x: 512, y: 144))
NSColor.white.withAlphaComponent(0.94).setStroke()
cable.stroke()

let remote = NSBezierPath(roundedRect: NSRect(x: 418, y: 228, width: 188, height: 568), xRadius: 94, yRadius: 94)
remote.lineWidth = 30
NSColor.white.withAlphaComponent(0.96).setStroke()
remote.stroke()

for (y, radius, color) in [
    (650.0, 24.0, NSColor.white),
    (512.0, 31.0, NSColor(calibratedRed: 0.20, green: 0.56, blue: 1.00, alpha: 1)),
    (374.0, 24.0, NSColor.white)
] {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
