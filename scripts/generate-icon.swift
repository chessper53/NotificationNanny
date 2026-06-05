#!/usr/bin/env swift
// Generates Resources/AppIcon.icns from scratch.
// Run: swift scripts/generate-icon.swift

import AppKit
import CoreGraphics

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // Rounded-rect clip
    let radius = size * 0.225
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background gradient — deep indigo → vivid violet
    let colors = [
        CGColor(red: 0.22, green: 0.18, blue: 0.52, alpha: 1),   // deep indigo
        CGColor(red: 0.55, green: 0.28, blue: 0.82, alpha: 1),   // vivid violet
    ] as CFArray
    let locs: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    if let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: 0, y: 0),
            end:   CGPoint(x: size, y: size),
            options: []
        )
    }

    // Subtle inner glow — slightly lighter at top-left
    let glowColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: space, colors: glowColors, locations: locs) {
        ctx.drawRadialGradient(
            glowGrad,
            startCenter: CGPoint(x: size * 0.3, y: size * 0.75),
            startRadius: 0,
            endCenter:   CGPoint(x: size * 0.3, y: size * 0.75),
            endRadius:   size * 0.7,
            options: []
        )
    }

    // SF Symbol — bell.badge.fill, white
    let symbolPt = size * 0.52
    let cfg = NSImage.SymbolConfiguration(pointSize: symbolPt, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sw = sym.size.width
        let sh = sym.size.height
        // Nudge slightly up-right so badge reads cleanly
        let ox = (size - sw) / 2 + size * 0.04
        let oy = (size - sh) / 2 - size * 0.02
        sym.draw(at: NSPoint(x: ox, y: oy), from: .zero, operation: .sourceOver, fraction: 1)
    }

    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: url)
}

let here       = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetDir = here.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try  FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(pt: Int, scale: Int)] = [
    (16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2),
]

for (pt, scale) in sizes {
    let px  = CGFloat(pt * scale)
    let img = makeIcon(size: px)
    let sfx = scale == 1 ? "" : "@2x"
    let name = "icon_\(pt)x\(pt)\(sfx).png"
    try savePNG(img, to: iconsetDir.appendingPathComponent(name))
    print("wrote \(name) (\(Int(px))×\(Int(px)))")
}

let icnsURL = here.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments  = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try task.run()
task.waitUntilExit()
print("\nwrote \(icnsURL.path)")
