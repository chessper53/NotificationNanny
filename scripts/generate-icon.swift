#!/usr/bin/env swift
// Generates Resources/AppIcon.icns from scratch.
// Run: swift scripts/generate-icon.swift

import AppKit
import CoreGraphics

let accent = NSColor(srgbRed: 0xE8 / 255, green: 0x83 / 255, blue: 0x3A / 255, alpha: 1)

// Computed, not stored: top-level `let`s initialise in source order, and this is
// read from makeIcon() above where `here` is declared.
var glyphURL: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/Glyphs/bell-nanny.png")
}

/// Recolours the black-ink glyph PNG, preserving its alpha. The scratch bitmap
/// starts fully transparent, so `.sourceAtop` lands only on the glyph's own
/// pixels rather than flooding the canvas.
func tinted(_ url: URL, color: NSColor, size: CGFloat) -> NSImage? {
    guard let src = NSImage(contentsOf: url) else { return nil }
    let px = Int(size.rounded())
    guard px > 0, let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: px * 4, bitsPerPixel: 32
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = gctx

    let r = NSRect(x: 0, y: 0, width: size, height: size)
    src.draw(in: r)
    color.set()
    r.fill(using: .sourceAtop)

    let out = NSImage(size: r.size)
    out.addRepresentation(rep)
    return out
}

/// Tightest rect containing non-transparent pixels, in the image's own coordinate
/// space (origin bottom-left, matching `NSImage.draw(at:)`). Nil if fully clear.
func inkBounds(of image: NSImage) -> CGRect? {
    let w = Int(image.size.width.rounded(.up))
    let h = Int(image.size.height.rounded(.up))
    guard w > 0, h > 0,
          let rep = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32
          ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.bitmapData else { return nil }
    var minX = w, minY = h, maxX = -1, maxY = -1
    for row in 0..<h {
        for col in 0..<w where data[row * rep.bytesPerRow + col * 4 + 3] > 8 {
            if col < minX { minX = col }
            if col > maxX { maxX = col }
            if row < minY { minY = row }
            if row > maxY { maxY = row }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }

    // Bitmap rows run top-down; flip into the image's bottom-left origin.
    return CGRect(x: CGFloat(minX), y: CGFloat(h - 1 - maxY),
                  width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
}

/// Draws at exactly `size` *pixels*. Deliberately not `NSImage.lockFocus()`, which
/// picks up the main display's backing scale and silently emits 2x-size PNGs on a
/// Retina Mac — that put every iconset slot at double its nominal size.
func makeIcon(size: CGFloat, glyphScale: CGFloat = 0.62) -> NSBitmapImageRep? {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: px * 4, bitsPerPixel: 32
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)   // one point == one pixel

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    // Rounded-rect clip
    let radius = size * 0.225
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background gradient — graphite, barely a gradient on purpose
    let colors = [
        CGColor(red: 0.102, green: 0.110, blue: 0.129, alpha: 1),  // #1A1C21
        CGColor(red: 0.165, green: 0.176, blue: 0.204, alpha: 1),  // #2A2D34
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
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
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

    // The nanny bell, in the brand accent. The artwork is one flat shape, so unlike the
    // old bell.badge.fill there's no separate badge layer to colour, so the glyph
    // itself carries the accent.
    if let glyph = tinted(glyphURL, color: accent, size: size * glyphScale) {
        // Centre on the glyph's actual ink: the shared crop box is sized to fit
        // the slashed variant too, so the plain bell sits inside extra margin.
        let ink = inkBounds(of: glyph) ?? CGRect(origin: .zero, size: glyph.size)
        let ox = (size - ink.width) / 2 - ink.minX
        let oy = (size - ink.height) / 2 - ink.minY
        glyph.draw(at: NSPoint(x: ox, y: oy), from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        FileHandle.standardError.write("error: missing \(glyphURL.path)\n".data(using: .utf8)!)
        exit(1)
    }

    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
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
    guard let img = makeIcon(size: px) else { throw NSError(domain: "icon", code: 2) }
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

// Website assets, generated from the same source so the GitHub Pages site and
// the app icon can't drift apart. The favicon gets a zoomed glyph: at 32px the
// standard inset turns the bonnet's detail into an orange smudge.
let siteAssets = here.appendingPathComponent("site/assets")
if FileManager.default.fileExists(atPath: siteAssets.path) {
    let webIcons: [(name: String, px: CGFloat, glyphScale: CGFloat)] = [
        ("icon-512.png",          512, 0.62),   // OG / Twitter card, hero, nav
        ("apple-touch-icon.png",  180, 0.62),
        ("favicon-32.png",         32, 0.82),
    ]
    print("")
    for icon in webIcons {
        guard let img = makeIcon(size: icon.px, glyphScale: icon.glyphScale) else {
            throw NSError(domain: "icon", code: 3)
        }
        try savePNG(img, to: siteAssets.appendingPathComponent(icon.name))
        print("wrote site/assets/\(icon.name) (\(Int(icon.px))×\(Int(icon.px)))")
    }
}
