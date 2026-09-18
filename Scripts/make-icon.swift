#!/usr/bin/env swift
// Малює AppIcon.icns без Xcode і без сторонніх утиліт: CoreGraphics рендерить
// PNG для всіх розмірів iconset, далі їх збирає iconutil (див. кінець файлу).
//
// Запуск: ./Scripts/make-icon.swift  (або swift Scripts/make-icon.swift)
//
// Сюжет іконки — те саме, що застосунок показує на екрані: темна пластина
// дисплея з вирізом у верхньому краю, а під ним дві шкали лімітів —
// Codex (синя) і Claude (помаранчева).

import AppKit
import CoreGraphics
import Foundation
import ImageIO

// Акценти тримаємо в синхроні з Notch/Style.swift.
let codexAccent = CGColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
let claudeAccent = CGColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)

// Наскільки заповнені шкали на іконці. Права «гарячіша» — так одразу видно,
// що шкали незалежні.
let codexFill: CGFloat = 0.62
let claudeFill: CGFloat = 0.88

/// Суперелліпс — форма, за якою macOS малює кути іконок: рівніша за коло.
func squirclePath(center: CGPoint, side: CGFloat, n: CGFloat = 5) -> CGPath {
    let a = side / 2
    let path = CGMutablePath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = a * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = a * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let p = CGPoint(x: center.x + x, y: center.y + y)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

/// Прямокутник із закругленими лише нижніми кутами — власне виріз.
func notchPath(rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
}

func capsule(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
}

func drawIcon(size px: CGFloat, into ctx: CGContext) {
    // Дрібні розміри не витримують ні тіні, ні волосяних ліній.
    let detailed = px >= 64

    // Пластина займає не весь холст: поля потрібні самій системі, а знизу ще
    // й місце під тінь.
    let side = px * 0.80
    let center = CGPoint(x: px / 2, y: px / 2 + px * 0.018)
    let plate = squirclePath(center: center, side: side)
    let top = center.y + side / 2

    if detailed {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -px * 0.016), blur: px * 0.03,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        ctx.addPath(plate)
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.11, blue: 0.13, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Далі все ріжеться формою пластини — виріз може спокійно вилазити за
    // верхній край, клип зробить його заокругленим по краю.
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // На дрібних розмірах верх пластини світліший: інакше чорний виріз
    // зливається з фоном і від іконки лишаються самі шкали.
    let body = CGGradient(colorsSpace: space, colors: [
        detailed
            ? CGColor(srgbRed: 0.267, green: 0.294, blue: 0.337, alpha: 1)
            : CGColor(srgbRed: 0.353, green: 0.384, blue: 0.435, alpha: 1),
        CGColor(srgbRed: 0.106, green: 0.118, blue: 0.141, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(body,
                           start: CGPoint(x: center.x, y: top),
                           end: CGPoint(x: center.x, y: center.y - side / 2),
                           options: [])

    // Виріз: головний знак іконки, тому помітно ширший за справжній.
    let notchW = side * 0.44
    let notchH = max(side * 0.15, px * 0.15)
    let notchRect = CGRect(x: center.x - notchW / 2, y: top - notchH,
                           width: notchW, height: notchH + px * 0.02)
    ctx.addPath(notchPath(rect: notchRect, radius: notchH * 0.38))
    ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.025, alpha: 1))
    ctx.fillPath()

    // Шкали живуть у полі під вирізом: дві смуги читаються як шкали навіть
    // тоді, коли від іконки лишається 16 точок.
    let gaugeW = side * 0.56
    let gaugeH = max(side * 0.10, px * 0.085)
    let gap = gaugeH * 0.85
    let field = (top: top - notchH, bottom: center.y - side / 2)
    let stackTop = (field.top + field.bottom) / 2 + (gaugeH * 2 + gap) / 2
    let gaugeX = center.x - gaugeW / 2

    for (index, spec) in [(codexFill, codexAccent), (claudeFill, claudeAccent)].enumerated() {
        let (fill, accent) = spec
        let y = stackTop - gaugeH - CGFloat(index) * (gaugeH + gap)
        let track = CGRect(x: gaugeX, y: y, width: gaugeW, height: gaugeH)
        ctx.addPath(capsule(track))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20))
        ctx.fillPath()

        let filled = CGRect(x: gaugeX, y: y, width: max(gaugeW * fill, gaugeH), height: gaugeH)
        ctx.addPath(capsule(filled))
        ctx.setFillColor(accent)
        ctx.fillPath()
    }

    if detailed {
        // Верхній відблиск: пластина перестає виглядати пласкою наліпкою.
        let sheen = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: center.x, y: top),
                               end: CGPoint(x: center.x, y: top - side * 0.55),
                               options: [])
    }
    ctx.restoreGState()

    if detailed {
        ctx.addPath(plate)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
        ctx.setLineWidth(max(px * 0.004, 1))
        ctx.strokePath()
    }
}

func renderPNG(size: Int, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "make-icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "не вдалося створити контекст \(size)px"])
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    drawIcon(size: CGFloat(size), into: ctx)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "не вдалося записати \(url.lastPathComponent)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "не вдалося зберегти \(url.lastPathComponent)"])
    }
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
               ? CommandLine.arguments[1]
               : FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let icns = root.appendingPathComponent("Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// iconutil розпізнає варіанти саме за цими іменами.
for base in [16, 32, 128, 256, 512] {
    try renderPNG(size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderPNG(size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else { exit(convert.terminationStatus) }

print("готово: \(icns.path)")
