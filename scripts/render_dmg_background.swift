#!/usr/bin/env swift
// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render_dmg_background.swift <output.png> <app-icon.icns>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])

let canvas = NSSize(width: 660, height: 420)
let image = NSImage(size: canvas)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawRadialGradient(center: NSPoint, radius: CGFloat, inner: NSColor, outer: NSColor) {
    guard let gradient = NSGradient(starting: inner, ending: outer) else { return }
    gradient.draw(
        fromCenter: center,
        radius: 0,
        toCenter: center,
        radius: radius,
        options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
    )
}

func drawString(_ string: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    string.draw(in: rect, withAttributes: attributes)
}

image.lockFocus()

let bounds = NSRect(origin: .zero, size: canvas)
color(251, 248, 241).setFill()
bounds.fill()

drawRadialGradient(
    center: NSPoint(x: 330, y: 470),
    radius: 430,
    inner: color(251, 232, 181, 0.90),
    outer: color(251, 232, 181, 0)
)
drawRadialGradient(
    center: NSPoint(x: 130, y: 285),
    radius: 260,
    inner: color(242, 180, 58, 0.42),
    outer: color(242, 180, 58, 0)
)
drawRadialGradient(
    center: NSPoint(x: 520, y: 300),
    radius: 230,
    inner: color(217, 119, 87, 0.30),
    outer: color(217, 119, 87, 0)
)
drawRadialGradient(
    center: NSPoint(x: 520, y: 95),
    radius: 220,
    inner: color(122, 135, 99, 0.20),
    outer: color(122, 135, 99, 0)
)

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.setAlpha(0.13)
    context.setLineWidth(1)
    color(20, 17, 10).setStroke()
    for x in stride(from: CGFloat(0), through: canvas.width, by: 24) {
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x + 120, y: canvas.height))
    }
    context.strokePath()
    context.restoreGState()
}

let titleColor = color(20, 17, 10)
let mutedColor = color(81, 72, 58)

if let appIcon = NSImage(contentsOf: iconURL) {
    appIcon.draw(
        in: NSRect(x: 294, y: 292, width: 72, height: 72),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.96
    )
}

drawString("Install Manifold", in: NSRect(x: 90, y: 256, width: 480, height: 32), size: 23, weight: .semibold, color: titleColor)
drawString("Drag Manifold.app onto the Applications folder to install.", in: NSRect(x: 90, y: 226, width: 480, height: 28), size: 13, weight: .medium, color: mutedColor)

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(3)
    color(198, 137, 24, 0.72).setStroke()
    context.move(to: CGPoint(x: 270, y: 168))
    context.addLine(to: CGPoint(x: 390, y: 168))
    context.move(to: CGPoint(x: 374, y: 182))
    context.addLine(to: CGPoint(x: 390, y: 168))
    context.addLine(to: CGPoint(x: 374, y: 154))
    context.strokePath()
    context.restoreGState()
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("error: failed to render DMG background PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
