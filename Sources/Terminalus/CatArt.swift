import AppKit

enum CatPose { case walk, sit, wave, sleep, jump, pet, sad }

/// Векторная Тян (серебристая полосатая, зелёные глаза). Рисуется в локальных координатах
/// 48×27 pt, кошка смотрит вправо; влево — отражаем.
enum CatArt {
    static let width: CGFloat = 48
    static let height: CGFloat = 27

    // MARK: Палитра

    private struct Look {
        let dim: Bool
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            if dim {
                let l = (0.3 * r + 0.59 * g + 0.11 * b) * 0.78 + 0.06
                return NSColor(white: l, alpha: 1)
            }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        var fur: NSColor { c(0.75, 0.76, 0.79) }
        var furFar: NSColor { c(0.56, 0.58, 0.63) }
        var stripe: NSColor { c(0.37, 0.39, 0.45) }
        var light: NSColor { c(0.95, 0.95, 0.94) }
        var pink: NSColor { c(0.93, 0.68, 0.66) }
        var nose: NSColor { c(0.80, 0.50, 0.46) }
        var eye: NSColor { c(0.70, 0.84, 0.28) }
        var pupil: NSColor { NSColor(srgbRed: 0.08, green: 0.09, blue: 0.10, alpha: 1) }
    }

    // MARK: Примитивы

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
                                rot: CGFloat = 0, _ color: NSColor) {
        let p = NSBezierPath(ovalIn: NSRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
        var t = AffineTransform()
        t.translate(x: cx, y: cy)
        t.rotate(byRadians: rot)
        p.transform(using: t)
        color.setFill()
        p.fill()
    }

    static func triangle(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, _ color: NSColor) {
        let p = NSBezierPath()
        p.move(to: a); p.line(to: b); p.line(to: c); p.close()
        p.lineJoinStyle = .round
        color.setFill()
        p.fill()
    }

    static func stroke(_ path: NSBezierPath, _ width: CGFloat, _ color: NSColor, dash: [CGFloat]? = nil) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if let d = dash { path.setLineDash(d, count: d.count, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    static func line(_ a: NSPoint, _ b: NSPoint, _ w: CGFloat, _ color: NSColor) {
        let p = NSBezierPath()
        p.move(to: a); p.line(to: b)
        stroke(p, w, color)
    }

    // MARK: Части тела

    enum Eyes { case open, happy, sleepy, droopy }

    /// Голова с большими ушами. (cx, cy) — центр головы, tilt — наклон в радианах.
    private static func head(_ cx: CGFloat, _ cy: CGFloat, tilt: CGFloat = 0, eyes: Eyes, _ L: Look) {
        NSGraphicsContext.current?.saveGraphicsState()
        var t = AffineTransform()
        t.translate(x: cx, y: cy)
        t.rotate(byRadians: tilt)
        (t as NSAffineTransform).concat()

        // уши (большие, как у мау)
        triangle(NSPoint(x: -5.4, y: 3.2), NSPoint(x: -4.3, y: 10.6), NSPoint(x: -0.4, y: 5.2), L.fur)
        triangle(NSPoint(x: 0.9, y: 5.2), NSPoint(x: 4.9, y: 10.6), NSPoint(x: 6.0, y: 3.0), L.fur)
        triangle(NSPoint(x: -4.4, y: 4.6), NSPoint(x: -3.95, y: 8.6), NSPoint(x: -1.6, y: 5.6), L.pink)
        triangle(NSPoint(x: 1.8, y: 5.6), NSPoint(x: 4.3, y: 8.4), NSPoint(x: 5.0, y: 4.4), L.pink)

        // голова и мордочка
        ellipse(0, 0, 7.2, 6.0, L.fur)
        ellipse(3.6, -2.2, 3.6, 2.7, L.light)
        ellipse(-2.5, -3.0, 2.6, 1.8, L.light, )

        // полоски на лбу и щеках
        for (i, x) in [-1.6, 0.4, 2.4].enumerated() {
            let h: CGFloat = i == 1 ? 3.2 : 2.5
            line(NSPoint(x: x, y: 4.4), NSPoint(x: x + 0.3, y: 4.4 - h), 0.9, L.stripe)
        }
        let cheek = NSBezierPath()
        cheek.move(to: NSPoint(x: -6.6, y: 0.4)); cheek.curve(to: NSPoint(x: -3.8, y: -1.2),
            controlPoint1: NSPoint(x: -5.6, y: -0.6), controlPoint2: NSPoint(x: -4.6, y: -1.2))
        stroke(cheek, 0.8, L.stripe)

        // глаза
        func eye(_ x: CGFloat, _ y: CGFloat) {
            switch eyes {
            case .open:
                ellipse(x, y, 1.75, 2.0, L.eye)
                ellipse(x + 0.1, y, 0.55, 1.5, L.pupil)
                ellipse(x + 0.6, y + 0.8, 0.4, 0.4, NSColor.white.withAlphaComponent(0.9))
            case .happy:      // ^
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - 1.6, y: y - 0.7))
                p.curve(to: NSPoint(x: x + 1.6, y: y - 0.7), controlPoint1: NSPoint(x: x - 0.8, y: y + 1.5),
                        controlPoint2: NSPoint(x: x + 0.8, y: y + 1.5))
                stroke(p, 0.9, L.pupil)
            case .sleepy:     // ‿
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - 1.6, y: y + 0.4))
                p.curve(to: NSPoint(x: x + 1.6, y: y + 0.4), controlPoint1: NSPoint(x: x - 0.8, y: y - 1.2),
                        controlPoint2: NSPoint(x: x + 0.8, y: y - 1.2))
                stroke(p, 0.9, L.pupil)
            case .droopy:     // полуприкрыты
                ellipse(x, y - 0.5, 1.75, 1.35, L.eye)
                ellipse(x + 0.1, y - 0.4, 0.55, 1.0, L.pupil)
                ellipse(x, y + 0.7, 1.9, 0.9, L.fur)
            }
        }
        eye(-2.6, 0.9)
        eye(2.6, 1.0)

        // нос, рот, усы
        triangle(NSPoint(x: 4.8, y: -1.0), NSPoint(x: 7.0, y: -1.0), NSPoint(x: 5.9, y: -2.4), L.nose)
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 5.9, y: -2.4)); mouth.line(to: NSPoint(x: 5.9, y: -3.2))
        mouth.curve(to: NSPoint(x: 4.0, y: -3.6), controlPoint1: NSPoint(x: 5.6, y: -4.0), controlPoint2: NSPoint(x: 4.6, y: -4.0))
        stroke(mouth, 0.5, L.stripe)
        for (dy, ey) in [(0.2, 1.6), (-1.0, -0.6), (-2.0, -2.8)] as [(CGFloat, CGFloat)] {
            line(NSPoint(x: 6.3, y: -2.0 + dy), NSPoint(x: 12.0, y: -2.0 + ey), 0.4, NSColor.white.withAlphaComponent(0.75))
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Хвост с полосками: base → кончик, w — взмах.
    private static func tail(from p0: NSPoint, c1: NSPoint, c2: NSPoint, to p1: NSPoint, _ L: Look, far: Bool = false) {
        let p = NSBezierPath()
        p.move(to: p0)
        p.curve(to: p1, controlPoint1: c1, controlPoint2: c2)
        stroke(p, 3.4, far ? L.furFar : L.fur)
        let q = p.copy() as! NSBezierPath
        stroke(q, 3.4, L.stripe, dash: [1.4, 2.6])
        ellipse(p1.x, p1.y, 1.8, 1.8, L.stripe)    // тёмный кончик
    }

    /// Нога с коленом: phase — фаза шага.
    private static func leg(hip: NSPoint, phase: CGFloat, far: Bool, _ L: Look,
                            a1 override1: CGFloat? = nil, a2 override2: CGFloat? = nil,
                            l1: CGFloat = 5.0, l2: CGFloat = 5.4) {
        let a1 = override1 ?? sin(phase) * 0.55
        let a2 = override2 ?? (a1 - max(0, cos(phase)) * 0.75)
        let knee = NSPoint(x: hip.x + sin(a1) * l1, y: hip.y - cos(a1) * l1)
        let foot = NSPoint(x: knee.x + sin(a2) * l2, y: knee.y - cos(a2) * l2)
        let p = NSBezierPath()
        p.move(to: hip); p.line(to: knee); p.line(to: foot)
        stroke(p, 3.3, far ? L.furFar : L.fur)
        ellipse(foot.x + 0.7, foot.y + 0.5, 2.3, 1.45, far ? L.furFar : L.light)
    }

    private static func bodyStripes(_ xs: [CGFloat], top: CGFloat, height: CGFloat, bob: CGFloat, _ L: Look) {
        for (i, x) in xs.enumerated() {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: top + bob))
            p.curve(to: NSPoint(x: x + 1.2, y: top - height + bob), controlPoint1: NSPoint(x: x - 0.8, y: top - height * 0.35 + bob),
                    controlPoint2: NSPoint(x: x + 0.4, y: top - height * 0.7 + bob))
            stroke(p, i % 2 == 0 ? 1.5 : 1.2, L.stripe)
        }
    }

    // MARK: Позы

    private static func walkLike(t: CGFloat, _ L: Look, still: Bool, rotate: CGFloat = 0,
                                 legs: [CGFloat?]? = nil, tailUp: Bool = false, eyes: Eyes = .open) {
        let phase = still ? 0 : t * 9
        let bob = still ? 0 : sin(phase * 2) * 0.5
        let wag = sin(t * 3.2) * 2.2

        NSGraphicsContext.current?.saveGraphicsState()
        if rotate != 0 {
            var tr = AffineTransform()
            tr.translate(x: 22, y: 10); tr.rotate(byRadians: rotate); tr.translate(x: -22, y: -10)
            (tr as NSAffineTransform).concat()
        }
        func a(_ i: Int) -> CGFloat? { legs?[i] }

        // дальние ноги, хвост
        leg(hip: NSPoint(x: 11.5, y: 11 + bob), phase: phase + .pi, far: true, L, a1: a(2), a2: a(2).map { $0 - 0.2 })
        leg(hip: NSPoint(x: 27.0, y: 11 + bob), phase: phase, far: true, L, a1: a(3), a2: a(3).map { $0 - 0.2 })
        if tailUp {
            tail(from: NSPoint(x: 7.0, y: 14.0), c1: NSPoint(x: 2.0, y: 15), c2: NSPoint(x: 1.0, y: 20 + wag * 0.3), to: NSPoint(x: 4.0, y: 25), L)
        } else {
            tail(from: NSPoint(x: 7.0, y: 14.2 + bob), c1: NSPoint(x: 1.0, y: 13), c2: NSPoint(x: 0.0 + wag * 0.2, y: 18.5 + wag), to: NSPoint(x: 3.5, y: 23 + wag * 0.6), L)
        }
        // тело
        ellipse(19.5, 13.8 + bob, 12.2, 5.6, L.fur)
        ellipse(20, 11.4 + bob, 9.8, 2.4, L.light.withAlphaComponent(0.55))
        bodyStripes([10.5, 13.5, 16.5, 19.5, 22.5, 25.0], top: 19.0, height: 5.2, bob: bob, L)
        // ближние ноги
        leg(hip: NSPoint(x: 10.5, y: 11 + bob), phase: phase, far: false, L, a1: a(0), a2: a(0).map { $0 - 0.2 })
        leg(hip: NSPoint(x: 26.0, y: 11 + bob), phase: phase + .pi, far: false, L, a1: a(1), a2: a(1).map { $0 - 0.2 })
        head(33.6, 16.4 + bob, eyes: eyes, L)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func sitLike(t: CGFloat, _ L: Look, wave: Bool, eyes: Eyes, headDrop: CGFloat = 0) {
        let wag = sin(t * 2.4) * 1.0
        // хвост лежит впереди на полу, кончик виляет
        tail(from: NSPoint(x: 9.5, y: 2.6), c1: NSPoint(x: 15, y: 0.3), c2: NSPoint(x: 21, y: 0.8), to: NSPoint(x: 26.5, y: 2.4 + wag), L, far: false)
        // туловище и бедро
        ellipse(22.5, 11.0, 6.6, 9.0, rot: -0.35, L.fur)               // грудь/туловище
        ellipse(14.5, 6.2, 8.8, 6.0, L.fur)                              // бедро
        ellipse(25.5, 9.5, 2.9, 6.0, rot: -0.15, L.light.withAlphaComponent(0.8))   // светлая грудка
        bodyStripes([10, 13, 16], top: 11.0, height: 6.0, bob: 0, L)
        ellipse(15.2, 1.5, 4.3, 1.6, L.light)                            // задняя лапа
        // передние лапы
        let sh = NSPoint(x: 26.8, y: 8.8)
        leg(hip: sh, phase: 0, far: true, L, a1: 0.0, a2: 0.0, l1: 4.0, l2: 4.2)
        if wave {
            let up = sin(t * 9) * 0.35
            let knee = NSPoint(x: sh.x + 3.6, y: sh.y + 1.6)
            let paw = NSPoint(x: knee.x + 3.2 + up * 3, y: knee.y + 4.4)
            let p = NSBezierPath(); p.move(to: NSPoint(x: sh.x + 0.5, y: sh.y)); p.line(to: knee); p.line(to: paw)
            stroke(p, 3.3, L.fur)
            ellipse(paw.x, paw.y + 0.5, 2.0, 2.0, L.light)
        } else {
            leg(hip: NSPoint(x: 29.0, y: 8.8), phase: 0, far: false, L, a1: 0.0, a2: 0.0, l1: 4.0, l2: 4.2)
        }
        head(30.6 + headDrop * 0.4, 17.4 - headDrop, eyes: eyes, L)
    }

    private static func sleepLike(t: CGFloat, _ L: Look) {
        let br = sin(t * 2.0) * 0.35
        // хвост обнимает тело снизу
        tail(from: NSPoint(x: 6.0, y: 4.6), c1: NSPoint(x: 10, y: 0.2), c2: NSPoint(x: 24, y: 0.2), to: NSPoint(x: 34.5, y: 3.0), L, far: false)
        ellipse(21.5, 6.4, 16.0, 5.6 + br, L.fur)
        ellipse(22, 3.6, 12.0, 2.2, L.light.withAlphaComponent(0.55))
        bodyStripes([9, 12, 15, 18, 21, 24, 27], top: 11.2 + br, height: 5.0, bob: 0, L)
        ellipse(33.5, 2.6, 3.4, 1.7, L.light)                           // лапки под подбородком
        head(35.6, 6.0 + br * 0.5, tilt: -0.28, eyes: .sleepy, L)
    }

    // MARK: Вход

    /// Рисует кошку с левым нижним углом в `origin`.
    static func draw(_ pose: CatPose, t: CGFloat, at origin: NSPoint, flipped: Bool) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        var tr = AffineTransform()
        if flipped {
            tr.translate(x: origin.x + width, y: origin.y)
            tr.scale(x: -1, y: 1)
        } else {
            tr.translate(x: origin.x, y: origin.y)
        }
        (tr as NSAffineTransform).concat()
        if Settings.petPixel { PixelArt.cat(pose, t: t); ctx.restoreGraphicsState(); return }
        let L = Look(dim: pose == .sad)
        switch pose {
        case .walk:  walkLike(t: t, L, still: false)
        case .sit:   sitLike(t: t, L, wave: false, eyes: .open)
        case .wave:  sitLike(t: t, L, wave: true, eyes: .open)
        case .pet:   sitLike(t: t, L, wave: false, eyes: .happy)
        case .sad:   sitLike(t: t, L, wave: false, eyes: .droopy, headDrop: 2.2)
        case .sleep: sleepLike(t: t, L)
        case .jump:  walkLike(t: t, L, still: true, rotate: 0.2, legs: [-0.9, 1.0, -1.0, 0.9], tailUp: true, eyes: .happy)
        }
        ctx.restoreGraphicsState()
    }

    /// Клубок: круг с нитками, вращается.
    static func drawYarn(center: NSPoint, radius r: CGFloat, angle: CGFloat) {
        if Settings.petPixel { PixelArt.yarn(center: center, angle: angle); return }
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        var tr = AffineTransform()
        tr.translate(x: center.x, y: center.y)
        tr.rotate(byRadians: angle)
        (tr as NSAffineTransform).concat()
        let base = NSColor(srgbRed: 0.90, green: 0.36, blue: 0.46, alpha: 1)
        let dark = NSColor(srgbRed: 0.64, green: 0.19, blue: 0.31, alpha: 1)
        let light = NSColor(srgbRed: 0.98, green: 0.62, blue: 0.68, alpha: 1)
        ellipse(0, 0, r, r, base)
        for (k, rot) in [CGFloat(0.4), 1.5, 2.6].enumerated() {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: -r * 0.9, y: 0))
            p.curve(to: NSPoint(x: r * 0.9, y: 0), controlPoint1: NSPoint(x: -r * 0.4, y: r * 0.9), controlPoint2: NSPoint(x: r * 0.4, y: -r * 0.9))
            var t = AffineTransform(); t.rotate(byRadians: rot + CGFloat(k) * 0.15)
            p.transform(using: t)
            stroke(p, 1.0, k == 1 ? light : dark)
        }
        ctx.restoreGraphicsState()
    }
}
