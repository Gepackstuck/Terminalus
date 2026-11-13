import AppKit

enum DogPose { case walk, sit, bark, sleep, gnaw, mark, bow, jump }

/// Бэн — йоркширский терьер (золотисто-рыжий, стальная «седловина», торчащие ушки, чёлка на глазах).
/// Рисуется в локальных координатах 38×25 pt, смотрит вправо.
enum DogArt {
    static let width: CGFloat = 38
    static let height: CGFloat = 25

    private struct Look {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        var tan: NSColor { c(0.88, 0.62, 0.28) }
        var tanDark: NSColor { c(0.70, 0.43, 0.17) }
        var tanFar: NSColor { c(0.60, 0.37, 0.15) }
        var tanLight: NSColor { c(0.96, 0.78, 0.46) }
        var steel: NSColor { c(0.35, 0.37, 0.42) }
        var steelDark: NSColor { c(0.22, 0.24, 0.28) }
        var ear: NSColor { c(0.52, 0.30, 0.13) }
        var nose: NSColor { c(0.07, 0.07, 0.08) }
        var collar: NSColor { c(0.78, 0.25, 0.30) }
    }

    private typealias V = CatArt
    private static func ell(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rot: CGFloat = 0, _ c: NSColor) {
        V.ellipse(cx, cy, rx, ry, rot: rot, c)
    }

    // MARK: Голова

    /// s — масштаб головы, tilt — наклон, mouth 0…1 — раскрытие пасти, eyes — закрыты ли.
    private static func head(_ cx: CGFloat, _ cy: CGFloat, s: CGFloat = 0.95, tilt: CGFloat = 0,
                             mouth: CGFloat = 0, closed: Bool = false, _ L: Look) {
        NSGraphicsContext.current?.saveGraphicsState()
        var t = AffineTransform()
        t.translate(x: cx, y: cy)
        t.rotate(byRadians: tilt)
        t.scale(s)
        (t as NSAffineTransform).concat()

        // ушки «домиком» — небольшие, торчат чуть в стороны
        V.triangle(NSPoint(x: -6.4, y: 2.6), NSPoint(x: -6.2, y: 9.4), NSPoint(x: -0.8, y: 5.2), L.ear)
        V.triangle(NSPoint(x: 1.2, y: 5.2), NSPoint(x: 6.0, y: 9.6), NSPoint(x: 7.0, y: 2.4), L.ear)
        V.triangle(NSPoint(x: -5.2, y: 4.2), NSPoint(x: -5.0, y: 8.0), NSPoint(x: -2.0, y: 5.4), L.tanDark)
        V.triangle(NSPoint(x: 2.2, y: 5.4), NSPoint(x: 5.0, y: 8.2), NSPoint(x: 5.8, y: 4.0), L.tanDark)

        // голова и борода
        ell(0, 0, 7.0, 6.2, L.tan)
        ell(-3.8, -3.0, 3.2, 3.0, L.tan)
        ell(4.6, -2.4, 3.9, 2.8, L.tan.blended(withFraction: 0.25, of: L.tanLight) ?? L.tan)

        // глаза (за чёлкой)
        if closed {
            for x in [-2.2, 2.6] as [CGFloat] {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - 1.3, y: 0.9)); p.curve(to: NSPoint(x: x + 1.3, y: 0.9),
                    controlPoint1: NSPoint(x: x - 0.6, y: -0.3), controlPoint2: NSPoint(x: x + 0.6, y: -0.3))
                V.stroke(p, 0.7, L.steelDark)
            }
        } else {
            ell(-2.2, 0.9, 1.05, 1.15, L.nose)
            ell(2.6, 1.0, 1.05, 1.15, L.nose)
            ell(-1.9, 1.3, 0.3, 0.3, NSColor.white.withAlphaComponent(0.8))
            ell(2.9, 1.4, 0.3, 0.3, NSColor.white.withAlphaComponent(0.8))
        }
        // чёлка поверх глаз: мягкая, с лёгкими прядями
        ell(0.2, 3.4, 6.4, 3.6, L.tanLight)
        ell(-3.8, 1.6, 2.4, 2.0, L.tanLight)
        ell(4.4, 1.9, 2.6, 2.0, L.tanLight)
        for (i, x) in [-4.0, -2.0, 0.0, 2.0, 4.0].enumerated() {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x + 0.3, y: 5.8))
            p.curve(to: NSPoint(x: x - 0.2 + (i % 2 == 0 ? 0.6 : -0.3), y: 0.9),
                    controlPoint1: NSPoint(x: x + 0.8, y: 3.8), controlPoint2: NSPoint(x: x - 0.1, y: 2.2))
            V.stroke(p, 0.45, L.tan.withAlphaComponent(0.7))
        }

        // пасть, нос
        if mouth > 0 {
            ell(5.0, -3.9 - mouth * 0.6, 2.6, 1.0 + mouth * 1.5, NSColor(srgbRed: 0.72, green: 0.22, blue: 0.30, alpha: 1))
            ell(5.2, -4.6 - mouth * 1.0, 1.5, 0.7 + mouth * 0.5, NSColor(srgbRed: 0.95, green: 0.50, blue: 0.55, alpha: 1))
        }
        ell(7.5, -0.7, 1.6, 1.25, L.nose)
        ell(7.9, -0.3, 0.45, 0.3, NSColor.white.withAlphaComponent(0.7))
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: Ноги, хвост

    private static func leg(hip: NSPoint, phase: CGFloat, far: Bool, _ L: Look,
                            a1 o1: CGFloat? = nil, a2 o2: CGFloat? = nil, l1: CGFloat = 3.1, l2: CGFloat = 3.3) {
        let a1 = o1 ?? sin(phase) * 0.6
        let a2 = o2 ?? (a1 - max(0, cos(phase)) * 0.8)
        let knee = NSPoint(x: hip.x + sin(a1) * l1, y: hip.y - cos(a1) * l1)
        let foot = NSPoint(x: knee.x + sin(a2) * l2, y: knee.y - cos(a2) * l2)
        let p = NSBezierPath()
        p.move(to: hip); p.line(to: knee); p.line(to: foot)
        V.stroke(p, 3.2, far ? L.tanFar : L.tan)
        ell(foot.x + 0.6, foot.y + 0.5, 2.2, 1.6, far ? L.tanFar : L.tanLight)   // мохнатая лапка
    }

    private static func tail(_ p0: NSPoint, _ tip: NSPoint, _ L: Look) {
        let p = NSBezierPath()
        p.move(to: p0)
        p.curve(to: tip, controlPoint1: NSPoint(x: p0.x - 3.5, y: p0.y + 0.5), controlPoint2: NSPoint(x: tip.x - 1.5, y: tip.y - 3))
        V.stroke(p, 2.6, L.tanDark)
        ell(tip.x, tip.y, 1.6, 1.6, L.steelDark)
    }

    /// Бахрома шерсти по низу корпуса.
    private static func skirt(x0: CGFloat, x1: CGFloat, y: CGFloat, _ L: Look) {
        var x = x0
        var i = 0
        while x < x1 {
            ell(x + 1.3, y + 0.8 - (i % 2 == 0 ? 0 : 0.6), 1.7, 1.5, i % 3 == 0 ? L.tanLight : L.tan)
            x += 2.2
            i += 1
        }
    }

    // MARK: Позы

    private static func standLike(t: CGFloat, _ L: Look, still: Bool, rotate: CGFloat = 0, legs: [CGFloat?]? = nil,
                                  headTilt: CGFloat = 0, mouth: CGFloat = 0, closed: Bool = false,
                                  liftHind: Bool = false, headDX: CGFloat = 0, headDY: CGFloat = 0) {
        let phase = still ? 0 : t * 9
        let bob = still ? 0 : sin(phase * 2) * 0.4
        NSGraphicsContext.current?.saveGraphicsState()
        if rotate != 0 {
            var tr = AffineTransform()
            tr.translate(x: 16, y: 8); tr.rotate(byRadians: rotate); tr.translate(x: -16, y: -8)
            (tr as NSAffineTransform).concat()
        }
        func a(_ i: Int) -> CGFloat? { legs?[i] }
        let hy = 7.2 + bob
        // дальние ноги
        leg(hip: NSPoint(x: 8.5, y: hy), phase: phase + .pi, far: true, L, a1: a(2), a2: a(2).map { $0 - 0.2 })
        leg(hip: NSPoint(x: 22.0, y: hy), phase: phase, far: true, L, a1: a(3), a2: a(3).map { $0 - 0.2 })
        tail(NSPoint(x: 5.0, y: 12.8 + bob), NSPoint(x: 1.8 + sin(t * 8) * 0.6, y: 18.6 + bob), L)
        // корпус: рыжий низ, стальная седловина, бахрома
        ell(14.6, 11.2 + bob, 9.6, 5.3, L.tan)
        ell(13.6, 12.9 + bob, 9.0, 3.6, L.steel)
        ell(13.0, 13.8 + bob, 7.2, 1.7, L.steelDark.withAlphaComponent(0.55))
        skirt(x0: 6.5, x1: 22, y: 6.6 + bob, L)
        ell(21.6, 10.4 + bob, 4.0, 4.6, L.tan)            // рыжая грудка
        // ближние ноги
        if liftHind {
            leg(hip: NSPoint(x: 9.5, y: hy), phase: 0, far: false, L, a1: -1.15, a2: -0.55, l1: 3.2, l2: 3.0)
        } else {
            leg(hip: NSPoint(x: 9.5, y: hy), phase: phase, far: false, L, a1: a(0), a2: a(0).map { $0 - 0.2 })
        }
        leg(hip: NSPoint(x: 21.0, y: hy), phase: phase + .pi, far: false, L, a1: a(1), a2: a(1).map { $0 - 0.2 })
        // ошейник
        ell(24.0, 12.4 + bob, 1.1, 3.4, rot: 0.25, L.collar)
        head(28.4 + headDX, 14.6 + bob + headDY, tilt: headTilt, mouth: mouth, closed: closed, L)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func sitLike(t: CGFloat, _ L: Look) {
        let wag = sin(t * 8) * 0.8
        tail(NSPoint(x: 4.6, y: 4.0), NSPoint(x: 1.0, y: 8.6 + wag), L)
        ell(13.0, 5.4, 8.0, 5.2, L.tan)                          // бедро
        ell(17.6, 9.4, 6.6, 7.0, rot: -0.3, L.tan)               // торс
        ell(16.6, 11.0, 5.4, 5.0, rot: -0.3, L.steel)            // седловина
        skirt(x0: 5.5, x1: 18, y: 0.8, L)
        ell(21.4, 7.6, 3.2, 4.6, rot: -0.1, L.tanLight.withAlphaComponent(0.85))
        ell(12.0, 1.3, 3.8, 1.6, L.tanLight)                    // задняя лапа
        leg(hip: NSPoint(x: 21.6, y: 5.6), phase: 0, far: true, L, a1: 0, a2: 0, l1: 2.6, l2: 2.8)
        leg(hip: NSPoint(x: 23.6, y: 5.6), phase: 0, far: false, L, a1: 0, a2: 0, l1: 2.6, l2: 2.8)
        ell(21.0, 12.6, 1.0, 2.8, rot: 0.45, L.collar)
        head(24.2, 15.2, s: 0.9, tilt: -0.05, L)
    }

    private static func lieLike(t: CGFloat, _ L: Look, gnaw: Bool, closed: Bool) {
        let br = closed ? sin(t * 2.2) * 0.3 : 0
        tail(NSPoint(x: 4.0, y: 5.2), NSPoint(x: 0.8, y: 8.8), L)
        ell(16.5, 5.6, 12.8, 4.2 + br, L.tan)
        ell(15.5, 7.4 + br, 10.0, 2.6, L.steel)
        skirt(x0: 6, x1: 27, y: 2.8, L)
        ell(26.0, 2.4, 3.8, 1.6, L.tanLight)                      // передние лапы
        ell(24.0, 5.0, 1.0, 3.0, rot: 0.1, L.collar)
        if gnaw {
            let bob = sin(t * 11) * 0.9
            head(29.6, 6.6 + bob * 0.5, s: 0.85, tilt: -0.55 + bob * 0.06, L)
        } else {
            head(30.0, 5.4 + br * 0.5, s: 0.85, tilt: -0.3, closed: closed, L)
        }
    }

    // MARK: Вход

    static func draw(_ pose: DogPose, t: CGFloat, at origin: NSPoint, flipped: Bool) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        var tr = AffineTransform()
        if flipped {
            tr.translate(x: origin.x + width, y: origin.y); tr.scale(x: -1, y: 1)
        } else {
            tr.translate(x: origin.x, y: origin.y)
        }
        (tr as NSAffineTransform).concat()
        if Settings.petPixel { PixelArt.dog(pose, t: t); ctx.restoreGraphicsState(); return }
        let L = Look()
        switch pose {
        case .walk:  standLike(t: t, L, still: false)
        case .sit:   sitLike(t: t, L)
        case .bark:  standLike(t: t, L, still: true, headTilt: 0.32, mouth: sin(t * 14) > 0 ? 1 : 0.1, headDX: 0.5, headDY: 0.8)
        case .mark:  standLike(t: t, L, still: true, headTilt: -0.12, liftHind: true)
        case .bow:   standLike(t: t, L, still: true, rotate: -0.32, legs: [0.0, 0.9, 0.0, 0.9], headTilt: 0.2, mouth: 0.4)
        case .jump:  standLike(t: t, L, still: true, rotate: 0.18, legs: [-0.9, 1.0, -1.0, 0.9], headTilt: 0.2, mouth: 0.6)
        case .sleep: lieLike(t: t, L, gnaw: false, closed: true)
        case .gnaw:  lieLike(t: t, L, gnaw: true, closed: false)
        }
        ctx.restoreGraphicsState()
    }

    // MARK: Кость и будка

    /// Кость (белая) с центром в `center`, повёрнутая на `angle`.
    static func drawBone(center: NSPoint, angle: CGFloat, length: CGFloat = 12) {
        if Settings.petPixel { PixelArt.bone(center: center, flipped: angle < 0); return }
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        var tr = AffineTransform()
        tr.translate(x: center.x, y: center.y); tr.rotate(byRadians: angle)
        (tr as NSAffineTransform).concat()
        let bone = NSColor(srgbRed: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        let shade = NSColor(srgbRed: 0.80, green: 0.76, blue: 0.66, alpha: 1)
        let h = length / 2, r = length * 0.16
        NSRect(x: -h + r, y: -r * 0.55, width: length - 2 * r, height: r * 1.1).fill()
        bone.setFill()
        NSRect(x: -h + r, y: -r * 0.55, width: length - 2 * r, height: r * 1.1).fill()
        for sx in [-1.0, 1.0] as [CGFloat] {
            ell(sx * h, r * 0.7, r, r, bone)
            ell(sx * h, -r * 0.7, r, r, bone)
            ell(sx * (h - r * 0.4), -r * 1.0, r * 0.5, r * 0.4, shade)
        }
        ctx.restoreGraphicsState()
    }

    static let houseWidth: CGFloat = 50
    static let houseHeight: CGFloat = 27

    /// Будка с табличкой «БЭН». Левый нижний угол в `origin`.
    static func drawHouse(at origin: NSPoint) {
        if Settings.petPixel {
            guard let ctx = NSGraphicsContext.current else { return }
            ctx.saveGraphicsState()
            var tr = AffineTransform(); tr.translate(x: origin.x, y: origin.y)
            (tr as NSAffineTransform).concat()
            PixelArt.house()
            ctx.restoreGraphicsState()
            return
        }
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        var tr = AffineTransform(); tr.translate(x: origin.x, y: origin.y)
        (tr as NSAffineTransform).concat()
        let wood = NSColor(srgbRed: 0.74, green: 0.50, blue: 0.30, alpha: 1)
        let woodDark = NSColor(srgbRed: 0.55, green: 0.35, blue: 0.20, alpha: 1)
        let roof = NSColor(srgbRed: 0.72, green: 0.24, blue: 0.24, alpha: 1)
        let roofDark = NSColor(srgbRed: 0.52, green: 0.16, blue: 0.18, alpha: 1)

        // стены (доски)
        wood.setFill()
        NSBezierPath(roundedRect: NSRect(x: 3, y: 0, width: 44, height: 16), xRadius: 1.5, yRadius: 1.5).fill()
        for x in stride(from: CGFloat(9), through: 45, by: 6) {
            V.line(NSPoint(x: x, y: 0.6), NSPoint(x: x, y: 15.4), 0.6, woodDark.withAlphaComponent(0.6))
        }
        // крыша
        V.triangle(NSPoint(x: -1, y: 15), NSPoint(x: 51, y: 15), NSPoint(x: 25, y: 27), roof)
        for i in 0..<3 {
            let y = 17.2 + CGFloat(i) * 3.0
            let inset = CGFloat(i) * 6.2
            V.line(NSPoint(x: 3 + inset, y: y), NSPoint(x: 47 - inset, y: y), 0.7, roofDark)
        }
        // вход (арка)
        let door = NSBezierPath()
        door.move(to: NSPoint(x: 17.5, y: 0))
        door.line(to: NSPoint(x: 17.5, y: 8))
        door.curve(to: NSPoint(x: 32.5, y: 8), controlPoint1: NSPoint(x: 17.5, y: 17), controlPoint2: NSPoint(x: 32.5, y: 17))
        door.line(to: NSPoint(x: 32.5, y: 0))
        door.close()
        NSColor(srgbRed: 0.10, green: 0.07, blue: 0.06, alpha: 1).setFill()
        door.fill()
        // табличка
        NSColor(srgbRed: 0.96, green: 0.92, blue: 0.78, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 18.5, y: 17.3, width: 13, height: 5.4), xRadius: 1, yRadius: 1).fill()
        let label = NSAttributedString(string: "БЭН", attributes: [
            .font: NSFont.systemFont(ofSize: 4.8, weight: .heavy),
            .foregroundColor: NSColor(srgbRed: 0.45, green: 0.15, blue: 0.15, alpha: 1)])
        label.draw(at: NSPoint(x: 25 - label.size().width / 2, y: 17.5))
        ctx.restoreGraphicsState()
    }
}
