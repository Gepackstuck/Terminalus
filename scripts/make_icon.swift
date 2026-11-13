// Генератор иконки приложения: swift scripts/make_icon.swift <out.iconset>
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Подложка (отступ под тень по гайдлайнам macOS)
    let inset = s * 0.055
    let base = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = base.width * 0.225
    let basePath = NSBezierPath(roundedRect: base, xRadius: radius, yRadius: radius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                  color: NSColor.black.withAlphaComponent(0.5).cgColor)
    NSColor.black.setFill(); basePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    basePath.addClip()
    let grad = NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                                   NSColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1)])!
    grad.draw(in: base, angle: -90)
    // мягкий акцентный блик сверху
    let glow = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.55, blue: 0.30, alpha: 0.28), .clear])!
    glow.draw(fromCenter: CGPoint(x: base.midX, y: base.maxY), radius: 0,
              toCenter: CGPoint(x: base.midX, y: base.maxY), radius: base.width * 0.75, options: [])
    ctx.restoreGState()

    // Крупные формы, читаемые даже в 32 px: стопка окон + большая вкладка-терминал с промптом
    let orange = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.28, alpha: 1)
    let green = NSColor(srgbRed: 0.30, green: 0.85, blue: 0.52, alpha: 1)
    let W = base.width
    let cardW = W * 0.70, cardH = W * 0.56

    // два окна «позади» — намёк на несколько терминалов
    for (i, a) in [(2, 0.10), (1, 0.18)] as [(Int, CGFloat)] {
        let off = CGFloat(i) * W * 0.055
        let r = CGRect(x: base.midX - cardW / 2 + off, y: base.midY - cardH / 2 + W * 0.02 + off,
                       width: cardW, height: cardH)
        NSColor.white.withAlphaComponent(a).setFill()
        NSBezierPath(roundedRect: r, xRadius: W * 0.07, yRadius: W * 0.07).fill()
    }

    // переднее окно
    let front = CGRect(x: base.midX - cardW / 2 - W * 0.02, y: base.midY - cardH / 2 - W * 0.04, width: cardW, height: cardH)
    let fp = NSBezierPath(roundedRect: front, xRadius: W * 0.07, yRadius: W * 0.07)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.55).cgColor)
    NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1).setFill()
    fp.fill()
    ctx.restoreGState()
    orange.setStroke(); fp.lineWidth = max(1.5, W * 0.016); fp.stroke()

    // полоса вкладок: активная оранжевая + две серые
    let barH = cardH * 0.20
    let tabY = front.maxY - barH - cardH * 0.07
    var tx = front.minX + cardW * 0.07
    for (i, w) in [0.34, 0.20, 0.20].enumerated() {
        let tw = cardW * w
        let tr = CGRect(x: tx, y: tabY, width: tw, height: barH)
        (i == 0 ? orange : NSColor.white.withAlphaComponent(0.20)).setFill()
        NSBezierPath(roundedRect: tr, xRadius: barH * 0.4, yRadius: barH * 0.4).fill()
        tx += tw + cardW * 0.035
    }
    // индикатор статуса — крупная зелёная точка справа
    let d = barH * 0.95
    green.setFill()
    NSBezierPath(ovalIn: CGRect(x: front.maxX - cardW * 0.07 - d, y: tabY + (barH - d) / 2, width: d, height: d)).fill()

    // огромный промпт  >_
    let font = NSFont.monospacedSystemFont(ofSize: cardH * 0.62, weight: .heavy)
    let str = NSAttributedString(string: ">_", attributes: [.font: font, .foregroundColor: orange])
    let sz = str.size()
    str.draw(at: CGPoint(x: front.midX - sz.width / 2, y: front.minY + cardH * 0.02))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(size: px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
