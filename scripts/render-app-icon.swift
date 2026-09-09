#!/usr/bin/swift

import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("用法：render-app-icon.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("无法创建图标画布。\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

let tileRect = NSRect(x: 56, y: 56, width: 912, height: 912)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 224, yRadius: 224)
NSGradient(
    starting: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1),
    ending: NSColor(calibratedRed: 0.19, green: 0.23, blue: 0.33, alpha: 1)
)?.draw(in: tilePath, angle: -55)

NSColor.white.withAlphaComponent(0.22).setStroke()
tilePath.lineWidth = 12
tilePath.stroke()

let glassRect = NSRect(x: 168, y: 168, width: 688, height: 688)
let glassPath = NSBezierPath(ovalIn: glassRect)
NSGradient(
    starting: NSColor.white.withAlphaComponent(0.20),
    ending: NSColor.white.withAlphaComponent(0.05)
)?.draw(in: glassPath, angle: -45)
NSColor.white.withAlphaComponent(0.30).setStroke()
glassPath.lineWidth = 10
glassPath.stroke()

let center = NSPoint(x: 512, y: 500)
let radius: CGFloat = 246
let lineWidth: CGFloat = 88

let track = NSBezierPath()
track.appendArc(
    withCenter: center,
    radius: radius,
    startAngle: 90,
    endAngle: -270,
    clockwise: true
)
track.lineWidth = lineWidth
track.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.12).setStroke()
track.stroke()

let progress = NSBezierPath()
progress.appendArc(
    withCenter: center,
    radius: radius,
    startAngle: 90,
    endAngle: -180,
    clockwise: true
)
progress.lineWidth = lineWidth
progress.lineCapStyle = .round
NSColor(calibratedRed: 0.05, green: 0.48, blue: 1.0, alpha: 1).setStroke()
progress.stroke()

let percent = "%" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
percent.draw(
    in: NSRect(x: 312, y: 382, width: 400, height: 248),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 214, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
)

let statusDot = NSBezierPath(ovalIn: NSRect(x: 758, y: 760, width: 78, height: 78))
NSColor(calibratedRed: 0.04, green: 0.88, blue: 0.40, alpha: 1).setFill()
statusDot.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("无法生成应用图标。\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
