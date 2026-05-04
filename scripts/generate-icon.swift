#!/usr/bin/env swift
// Generates an AppIcon.icns from scratch.
// Output: Resources/AppIcon.icns
//
// Run: swift scripts/generate-icon.swift

import AppKit
import CoreGraphics

let brandPurple = NSColor(red: 0x89/255.0, green: 0x5C/255.0, blue: 0x9B/255.0, alpha: 1)

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Rounded square background.
    let radius = size * 0.22
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: radius, yRadius: radius)
    brandPurple.setFill()
    bg.fill()

    // Bell symbol on top.
    let symbolPointSize = size * 0.55
    let cfg = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    guard let bell = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
        return image
    }
    let bellSize = bell.size
    let origin = NSPoint(x: (size - bellSize.width) / 2,
                         y: (size - bellSize.height) / 2)
    bell.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    return image
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try png.write(to: url)
}

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetDir = here.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Standard macOS icon sizes (pt × scale).
let sizes: [(pt: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for (pt, scale) in sizes {
    let pixels = CGFloat(pt * scale)
    let img = makeIcon(size: pixels)
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(pt)x\(pt)\(suffix).png"
    try savePNG(img, to: iconsetDir.appendingPathComponent(name))
    print("wrote \(name) (\(Int(pixels))×\(Int(pixels)))")
}

// Convert iconset → icns via iconutil.
let icnsURL = here.appendingPathComponent("Resources/AppIcon.icns")
try? FileManager.default.createDirectory(
    at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true
)
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try task.run()
task.waitUntilExit()
print("\nwrote \(icnsURL.path)")
