#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make-icon.swift OUTPUT_PNG\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = CGSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("Could not create drawing context.\n", stderr)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let outerRect = CGRect(x: 62, y: 62, width: 900, height: 900)
let outerPath = CGPath(
    roundedRect: outerRect,
    cornerWidth: 208,
    cornerHeight: 208,
    transform: nil
)
context.saveGState()
context.addPath(outerPath)
context.clip()

let colorSpace = CGColorSpaceCreateDeviceRGB()
let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.24, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.31, green: 0.37, blue: 0.43, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: 180, y: 900),
    end: CGPoint(x: 870, y: 110),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

let glowGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(calibratedWhite: 1, alpha: 0.25).cgColor,
        NSColor(calibratedWhite: 1, alpha: 0).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    glowGradient,
    startCenter: CGPoint(x: 270, y: 820),
    startRadius: 0,
    endCenter: CGPoint(x: 270, y: 820),
    endRadius: 540,
    options: []
)
context.restoreGState()

context.addPath(outerPath)
context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.22).cgColor)
context.setLineWidth(3)
context.strokePath()

let warm = NSColor(calibratedRed: 0.96, green: 0.68, blue: 0.34, alpha: 1)
context.setShadow(offset: .zero, blur: 28, color: warm.withAlphaComponent(0.34).cgColor)
context.setStrokeColor(warm.withAlphaComponent(0.82).cgColor)
context.setLineWidth(7)
context.move(to: CGPoint(x: 272, y: 265))
context.addLine(to: CGPoint(x: 272, y: 759))
context.strokePath()
context.setShadow(offset: .zero, blur: 0, color: nil)

func drawPill(_ rect: CGRect, emphasized: Bool) {
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: rect.height / 2,
        cornerHeight: rect.height / 2,
        transform: nil
    )
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -15),
        blur: 28,
        color: NSColor(calibratedWhite: 0, alpha: 0.24).cgColor
    )
    context.addPath(path)
    context.setFillColor(
        NSColor(calibratedWhite: 1, alpha: emphasized ? 0.24 : 0.16).cgColor
    )
    context.fillPath()
    context.restoreGState()

    context.addPath(path)
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: emphasized ? 0.58 : 0.38).cgColor)
    context.setLineWidth(3)
    context.strokePath()
}

let pills = [
    CGRect(x: 228, y: 649, width: 594, height: 128),
    CGRect(x: 228, y: 447, width: 664, height: 128),
    CGRect(x: 228, y: 245, width: 528, height: 128)
]

for (index, rect) in pills.enumerated() {
    drawPill(rect, emphasized: index == 1)

    let dotRect = CGRect(x: rect.minX + 31, y: rect.midY - 18, width: 36, height: 36)
    context.setFillColor(
        (index == 1 ? warm.withAlphaComponent(0.96) : NSColor(calibratedWhite: 1, alpha: 0.56)).cgColor
    )
    context.fillEllipse(in: dotRect)

    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: index == 1 ? 0.92 : 0.66).cgColor)
    context.setLineWidth(index == 1 ? 12 : 10)
    context.setLineCap(.round)
    let lineStart = rect.minX + 95
    context.move(to: CGPoint(x: lineStart, y: rect.midY + 12))
    context.addLine(to: CGPoint(x: rect.maxX - 58, y: rect.midY + 12))
    context.strokePath()

    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.3).cgColor)
    context.setLineWidth(8)
    context.move(to: CGPoint(x: lineStart, y: rect.midY - 18))
    context.addLine(to: CGPoint(x: rect.maxX - (index == 2 ? 135 : 105), y: rect.midY - 18))
    context.strokePath()
}

for y in stride(from: CGFloat(275), through: 755, by: 80) {
    context.setFillColor(warm.withAlphaComponent(0.72).cgColor)
    context.fillEllipse(in: CGRect(x: 265, y: y, width: 14, height: 14))
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Could not encode icon.\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
