// Renders abstract landscape fixtures for Firsthand DEBUG demo content.
// Usage: swift fixtures.swift <output xcassets dir>
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 1080, H = 1350
let out = URL(fileURLWithPath: CommandLine.arguments[1])

struct RNG {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// A ridge line from left to right, filled down to `bottom`. y grows downward in our helper.
func ridge(_ ctx: CGContext, _ rng: inout RNG, base: CGFloat, amp: CGFloat, steps: Int, color: CGColor, bottom: CGFloat = CGFloat(H)) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: bottom))
    var y = base
    for i in 0...steps {
        let x = CGFloat(i) / CGFloat(steps) * CGFloat(W)
        y = base + CGFloat(rng.next() - 0.5) * amp * 2
        p.addLine(to: CGPoint(x: x, y: y))
    }
    p.addLine(to: CGPoint(x: CGFloat(W), y: bottom))
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func grain(_ ctx: CGContext, _ rng: inout RNG, amount: Double = 0.05) {
    for _ in 0..<26000 {
        let x = rng.next() * Double(W), y = rng.next() * Double(H)
        let v = rng.next()
        ctx.setFillColor(v > 0.5 ? CGColor(gray: 1, alpha: amount) : CGColor(gray: 0, alpha: amount))
        ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
    }
}

func vignette(_ ctx: CGContext) {
    radial(ctx, [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.28)],
           center: CGPoint(x: W / 2, y: H / 2), radius: CGFloat(H) * 0.75)
}

typealias Scene = (CGContext, inout RNG) -> Void

let scenes: [(String, UInt64, Scene)] = [
    ("demo-lake", 11, { ctx, rng in
        linear(ctx, [rgb(0x2B2F6B), rgb(0xC2577A), rgb(0xF6A35C), rgb(0xFFD58A)], from: .zero, to: CGPoint(x: 0, y: 760))
        radial(ctx, [rgb(0xFFF3C4), rgb(0xFFC56E, 0.6), rgb(0xFFC56E, 0)], center: CGPoint(x: 640, y: 700), radius: 260)
        ridge(ctx, &rng, base: 690, amp: 40, steps: 9, color: rgb(0x5B3A6E))
        ridge(ctx, &rng, base: 740, amp: 18, steps: 22, color: rgb(0x3A2550))
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 770, width: W, height: H - 770))
        linear(ctx, [rgb(0xE98A5E), rgb(0x6D3B63), rgb(0x241A3D)], from: CGPoint(x: 0, y: 770), to: CGPoint(x: 0, y: CGFloat(H)))
        ctx.restoreGState()
        for i in 0..<40 {
            let y = 790 + CGFloat(i) * 14 + CGFloat(rng.next() * 6)
            let w = 260 - CGFloat(i) * 4 + CGFloat(rng.next() * 120)
            ctx.setFillColor(rgb(0xFFE2A8, 0.5 - CGFloat(i) * 0.011))
            ctx.fill(CGRect(x: 640 - w / 2 + CGFloat(rng.next() * 40 - 20), y: y, width: max(w, 20), height: 4))
        }
        ridge(ctx, &rng, base: 1230, amp: 30, steps: 14, color: rgb(0x150E22))
    }),
    ("demo-mountain", 23, { ctx, rng in
        linear(ctx, [rgb(0x7FB6E6), rgb(0xCFE6F5)], from: .zero, to: CGPoint(x: 0, y: 700))
        radial(ctx, [rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)], center: CGPoint(x: 820, y: 230), radius: 180)
        ridge(ctx, &rng, base: 560, amp: 120, steps: 6, color: rgb(0xA9BCD6))
        ridge(ctx, &rng, base: 700, amp: 90, steps: 8, color: rgb(0x6E86A6))
        ridge(ctx, &rng, base: 860, amp: 60, steps: 12, color: rgb(0x3F5F5A))
        ridge(ctx, &rng, base: 1010, amp: 40, steps: 30, color: rgb(0x2D4A36))
        ridge(ctx, &rng, base: 1160, amp: 30, steps: 60, color: rgb(0x1B3022))
    }),
    ("demo-beach", 37, { ctx, rng in
        linear(ctx, [rgb(0x4AA3DF), rgb(0xA8DDF2)], from: .zero, to: CGPoint(x: 0, y: 620))
        for _ in 0..<5 {
            let cx = CGFloat(rng.next()) * CGFloat(W), cy = 120 + CGFloat(rng.next()) * 300
            radial(ctx, [rgb(0xFFFFFF, 0.8), rgb(0xFFFFFF, 0)], center: CGPoint(x: cx, y: cy), radius: 120 + CGFloat(rng.next()) * 80)
        }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 620, width: W, height: H - 620))
        linear(ctx, [rgb(0x1B7FA8), rgb(0x37B5C4), rgb(0x7FD9CF)], from: CGPoint(x: 0, y: 620), to: CGPoint(x: 0, y: 900))
        ctx.restoreGState()
        ctx.setFillColor(rgb(0x1B7FA8)); ctx.fill(CGRect(x: 0, y: 620, width: W, height: 4))
        let sand = CGMutablePath()
        sand.move(to: CGPoint(x: 0, y: 930))
        sand.addCurve(to: CGPoint(x: CGFloat(W), y: 860), control1: CGPoint(x: 300, y: 870), control2: CGPoint(x: 700, y: 960))
        sand.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(H))); sand.addLine(to: CGPoint(x: 0, y: CGFloat(H))); sand.closeSubpath()
        ctx.addPath(sand); ctx.setFillColor(rgb(0xEAD3A6)); ctx.fillPath()
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.8)); ctx.setLineWidth(10)
        let foam = CGMutablePath()
        foam.move(to: CGPoint(x: 0, y: 925))
        foam.addCurve(to: CGPoint(x: CGFloat(W), y: 855), control1: CGPoint(x: 300, y: 865), control2: CGPoint(x: 700, y: 955))
        ctx.addPath(foam); ctx.strokePath()
        ctx.setFillColor(rgb(0xF2605A)); ctx.fillEllipse(in: CGRect(x: 690, y: 1040, width: 150, height: 40))
        ctx.setFillColor(rgb(0xF6C343)); ctx.fill(CGRect(x: 760, y: 900, width: 8, height: 160))
        let umb = CGMutablePath()
        umb.move(to: CGPoint(x: 640, y: 930)); umb.addQuadCurve(to: CGPoint(x: 890, y: 930), control: CGPoint(x: 765, y: 800)); umb.closeSubpath()
        ctx.addPath(umb); ctx.setFillColor(rgb(0xF2603A)); ctx.fillPath()
    }),
    ("demo-city", 41, { ctx, rng in
        linear(ctx, [rgb(0x0B1030), rgb(0x2A2A6A), rgb(0x8B4A8C)], from: .zero, to: CGPoint(x: 0, y: 900))
        for _ in 0..<80 {
            ctx.setFillColor(rgb(0xFFFFFF, CGFloat(rng.next() * 0.7)))
            ctx.fillEllipse(in: CGRect(x: rng.next() * Double(W), y: rng.next() * 500, width: 3, height: 3))
        }
        var x: CGFloat = -20
        while x < CGFloat(W) {
            let w = 70 + CGFloat(rng.next()) * 110, h = 300 + CGFloat(rng.next()) * 520
            let top = CGFloat(H) - 250 - h
            ctx.setFillColor(rgb(0x14142E)); ctx.fill(CGRect(x: x, y: top, width: w, height: h + 260))
            var wy = top + 20
            while wy < CGFloat(H) - 260 {
                var wx = x + 12
                while wx < x + w - 16 {
                    if rng.next() > 0.45 {
                        ctx.setFillColor(rgb(rng.next() > 0.3 ? 0xFFD27A : 0x9FD3FF, 0.85))
                        ctx.fill(CGRect(x: wx, y: wy, width: 10, height: 14))
                    }
                    wx += 20
                }
                wy += 28
            }
            x += w + 6
        }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: H - 300, width: W, height: 300))
        linear(ctx, [rgb(0x1A1036, 0), rgb(0x05030F)], from: CGPoint(x: 0, y: CGFloat(H) - 300), to: CGPoint(x: 0, y: CGFloat(H)))
        ctx.restoreGState()
        for i in 0..<30 {
            radial(ctx, [rgb(i % 2 == 0 ? 0xFF7A52 : 0xFFE08A, 0.7), rgb(0xFF7A52, 0)],
                   center: CGPoint(x: rng.next() * Double(W), y: Double(H) - 120 + rng.next() * 60), radius: 30)
        }
    }),
    ("demo-forest", 53, { ctx, rng in
        linear(ctx, [rgb(0xDDE8C8), rgb(0x9CC08A)], from: .zero, to: CGPoint(x: 0, y: CGFloat(H)))
        for layer in 0..<4 {
            let color = [rgb(0x8BB07F), rgb(0x5E8E5C), rgb(0x3C6B42), rgb(0x1F4429)][layer]
            for _ in 0..<(10 + layer * 3) {
                let cx = CGFloat(rng.next()) * CGFloat(W)
                let h = 380 + CGFloat(layer) * 160 + CGFloat(rng.next()) * 160
                let base = CGFloat(H) - CGFloat(3 - layer) * 120
                let w = h * 0.36
                let t = CGMutablePath()
                t.move(to: CGPoint(x: cx, y: base - h)); t.addLine(to: CGPoint(x: cx + w / 2, y: base)); t.addLine(to: CGPoint(x: cx - w / 2, y: base)); t.closeSubpath()
                ctx.addPath(t); ctx.setFillColor(color); ctx.fillPath()
            }
            ctx.setFillColor(rgb(0xF5F9E8, 0.18)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        for i in 0..<6 {
            ctx.saveGState()
            ctx.setFillColor(rgb(0xFFF6D0, 0.08))
            let p = CGMutablePath()
            let x0 = 160 + CGFloat(i) * 120
            p.move(to: CGPoint(x: x0, y: 0)); p.addLine(to: CGPoint(x: x0 + 70, y: 0)); p.addLine(to: CGPoint(x: x0 + 300, y: CGFloat(H))); p.addLine(to: CGPoint(x: x0 + 160, y: CGFloat(H)))
            ctx.addPath(p); ctx.fillPath(); ctx.restoreGState()
        }
    }),
    ("demo-food", 67, { ctx, rng in
        linear(ctx, [rgb(0x7A4E32), rgb(0x4E3020)], from: .zero, to: CGPoint(x: CGFloat(W), y: CGFloat(H)))
        for i in 0..<18 {
            ctx.setFillColor(rgb(0x2E1B10, 0.25)); ctx.fill(CGRect(x: 0, y: CGFloat(i) * 80 + CGFloat(rng.next() * 10), width: CGFloat(W), height: 3))
        }
        ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 40, color: CGColor(gray: 0, alpha: 0.5))
        ctx.setFillColor(rgb(0xF4F1EA)); ctx.fillEllipse(in: CGRect(x: 140, y: 330, width: 800, height: 800))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(rgb(0xE6E1D6)); ctx.fillEllipse(in: CGRect(x: 230, y: 420, width: 620, height: 620))
        let fills: [UInt32] = [0xE2483A, 0xF2A33A, 0x6BA34A, 0xF6D365, 0xC2372E]
        for _ in 0..<26 {
            let a = rng.next() * .pi * 2, r = rng.next() * 220
            let cx = 540 + CGFloat(cos(a) * r), cy = 730 + CGFloat(sin(a) * r)
            let s = 50 + CGFloat(rng.next() * 60)
            ctx.setFillColor(rgb(fills[Int(rng.next() * 4.99)]))
            ctx.fillEllipse(in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s * 0.8))
        }
        ctx.setFillColor(rgb(0xD9D2C2)); ctx.fill(CGRect(x: 980, y: 280, width: 26, height: 900))
    }),
    ("demo-park", 79, { ctx, rng in
        linear(ctx, [rgb(0x9BD1F5), rgb(0xE9F5FB)], from: .zero, to: CGPoint(x: 0, y: 820))
        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: 0, y: 860)); hill.addCurve(to: CGPoint(x: CGFloat(W), y: 820), control1: CGPoint(x: 360, y: 740), control2: CGPoint(x: 720, y: 900))
        hill.addLine(to: CGPoint(x: CGFloat(W), y: CGFloat(H))); hill.addLine(to: CGPoint(x: 0, y: CGFloat(H))); hill.closeSubpath()
        ctx.addPath(hill); ctx.setFillColor(rgb(0x7DBB5A)); ctx.fillPath()
        ctx.saveGState()
        ctx.addPath(hill); ctx.clip()
        linear(ctx, [rgb(0x5E9E43, 0), rgb(0x3F7A2E, 0.9)], from: CGPoint(x: 0, y: 900), to: CGPoint(x: 0, y: CGFloat(H)))
        ctx.restoreGState()
        let colors: [UInt32] = [0xF2603A, 0xF6C343, 0x5AA9E6, 0xE85D9E, 0x8E6CEF]
        for i in 0..<7 {
            let cx = 260 + CGFloat(i) * 90 + CGFloat(rng.next() * 40), cy = 260 + CGFloat(rng.next() * 260)
            ctx.setStrokeColor(rgb(0x555555, 0.6)); ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: cx, y: cy + 70)); ctx.addLine(to: CGPoint(x: 560, y: 900)); ctx.strokePath()
            ctx.setFillColor(rgb(colors[i % colors.count])); ctx.fillEllipse(in: CGRect(x: cx - 50, y: cy - 60, width: 100, height: 130))
            ctx.setFillColor(rgb(0xFFFFFF, 0.35)); ctx.fillEllipse(in: CGRect(x: cx - 28, y: cy - 42, width: 26, height: 36))
        }
    }),
    ("demo-snow", 97, { ctx, rng in
        linear(ctx, [rgb(0x3D5A8A), rgb(0xA7B8D8), rgb(0xF3D9E0)], from: .zero, to: CGPoint(x: 0, y: 760))
        ridge(ctx, &rng, base: 620, amp: 160, steps: 5, color: rgb(0xEEF2FA))
        ridge(ctx, &rng, base: 780, amp: 90, steps: 9, color: rgb(0xC9D4E8))
        ridge(ctx, &rng, base: 940, amp: 50, steps: 14, color: rgb(0xF7F9FD))
        ridge(ctx, &rng, base: 1100, amp: 30, steps: 24, color: rgb(0xDCE4F2))
        for _ in 0..<300 {
            ctx.setFillColor(rgb(0xFFFFFF, CGFloat(0.4 + rng.next() * 0.6)))
            let s = 3 + rng.next() * 7
            ctx.fillEllipse(in: CGRect(x: rng.next() * Double(W), y: rng.next() * Double(H), width: s, height: s))
        }
    }),
]

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let contents = #"{"info":{"author":"xcode","version":1}}"#
try contents.write(to: out.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

for (name, seed, draw) in scenes {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip so y grows downward.
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    var rng = RNG(s: seed)
    draw(ctx, &rng)
    vignette(ctx)
    grain(ctx, &rng)
    let image = ctx.makeImage()!
    let dir = out.appending(path: "\(name).imageset")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appending(path: "\(name).jpg")
    let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
    CGImageDestinationFinalize(dest)
    let json = #"{"images":[{"filename":"\#(name).jpg","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
    try json.write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    print("wrote", name)
}
