import AppKit

/// Пиксельный стиль питомцев (как в первой версии): Тян, Бэн, будка, кость и клубок.
/// Всё рисуется внутри тех же рамок, что и векторные версии (кошка 48×27, пёс 38×25, будка 50×27),
/// один пиксель спрайта = 2 pt.
enum PixelArt {
    static let px: CGFloat = 2

    // MARK: Холст для процедурного пиксель-арта

    struct Canvas {
        let w: Int, h: Int
        var g: [[Character]]
        init(_ w: Int, _ h: Int) { self.w = w; self.h = h; g = Array(repeating: Array(repeating: ".", count: w), count: h) }
        mutating func set(_ x: Int, _ y: Int, _ c: Character) {
            if x >= 0 && x < w && y >= 0 && y < h { g[y][x] = c }
        }
        mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: Character) {
            for j in 0..<max(0, rh) { for i in 0..<max(0, rw) { set(x + i, y + j, c) } }
        }
        /// Эллипс с центром (cx, cy) в координатах пикселей (y вниз).
        mutating func ell(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Character) {
            for y in 0..<h { for x in 0..<w {
                let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 { g[y][x] = c }
            } }
        }
        mutating func pts(_ list: [(Int, Int)], _ c: Character) { for p in list { set(p.0, p.1, c) } }
        var rows: [String] { g.map { String($0) } }
    }

    // MARK: Рисование сетки символов

    static func drawGrid(_ rows: [String], palette: [Character: NSColor], at origin: NSPoint,
                         flippedInside: Bool = false, dim: Bool = false, closedEyes: Bool = false) {
        let h = rows.count
        let w = rows.map(\.count).max() ?? 0
        // Без сглаживания: иначе при дробном масштабе между пикселями появляются светлые швы.
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        defer { NSGraphicsContext.current?.restoreGraphicsState() }
        for (ry, row) in rows.enumerated() {
            for (cx, ch) in row.enumerated() {
                var c = ch
                if closedEyes && c == "e" { c = "d" }
                guard c != ".", var color = palette[c] else { continue }
                if dim {
                    let s = color.usingColorSpace(.sRGB) ?? color
                    let l = 0.3 * s.redComponent + 0.59 * s.greenComponent + 0.11 * s.blueComponent
                    color = NSColor(white: l * 0.62 + 0.05, alpha: 1)
                }
                let x = flippedInside ? CGFloat(w - 1 - cx) : CGFloat(cx)
                color.setFill()
                NSRect(x: origin.x + x * px, y: origin.y + CGFloat(h - 1 - ry) * px, width: px, height: px).fill()
            }
        }
    }

    private static func rotate90(_ rows: [String]) -> [String] {
        let h = rows.count, w = rows[0].count
        let g = rows.map { Array($0) }
        return (0..<w).map { x in String((0..<h).map { y in g[h - 1 - y][x] }) }
    }

    // MARK: Тян (серебристая полосатая)

    static let catPalette: [Character: NSColor] = [
        "b": NSColor(srgbRed: 0.75, green: 0.76, blue: 0.79, alpha: 1),   // мех
        "d": NSColor(srgbRed: 0.38, green: 0.40, blue: 0.46, alpha: 1),   // полоски
        "w": NSColor(srgbRed: 0.95, green: 0.95, blue: 0.94, alpha: 1),   // грудка, подбородок
        "e": NSColor(srgbRed: 0.68, green: 0.84, blue: 0.26, alpha: 1),   // зелёные глаза
        "n": NSColor(srgbRed: 0.80, green: 0.50, blue: 0.46, alpha: 1),   // нос
        "p": NSColor(srgbRed: 0.93, green: 0.68, blue: 0.66, alpha: 1),   // розовые уши
        "k": NSColor(srgbRed: 0.86, green: 0.86, blue: 0.85, alpha: 1),   // светлые лапки
    ]

    /// Раскраска «под Тян»: уши с розовой серединой, полоски на лбу и по бокам.
    private static func tyan(_ rows: [String]) -> [String] {
        var out = rows.map { Array($0) }
        for y in out.indices {
            var line = String(out[y])
            if y == 1 { line = line.replacingOccurrences(of: "bb.bb", with: "bp.pb") }
            if y == 2 { line = line.replacingOccurrences(of: "bbbbb", with: "bdbdb") }
            out[y] = Array(line)
            if y >= 6 && y <= 9 {
                for x in out[y].indices where x >= 2 && x <= 11 {
                    if out[y][x] == "d" { out[y][x] = "b" }
                    if out[y][x] == "b" && x % 3 == 1 { out[y][x] = "d" }
                }
            }
        }
        return out.map { String($0) }
    }

    private static let walkA = tyan([
        "..........b...b...", "..........bb.bb...", "..........bbbbb...", ".........bbebebb..", "........bbbbnbbb..",
        "...bbbbbbbbwwwwb..", "..bbdbdbdbbbbwb...", ".dbbbbbbbbbbbb....", ".d.bbbbbbbbbbb....", "...bb.b....bb.b...",
        "...bb.b....bb.b...", "..kk..kk..kk..kk..",
    ])
    private static let walkB = tyan([
        "..........b...b...", "..........bb.bb...", "..........bbbbb...", ".........bbebebb..", "........bbbbnbbb..",
        "...bbbbbbbbwwwwb..", "..bbdbdbdbbbbwb...", ".dbbbbbbbbbbbb....", ".d.bbbbbbbbbbb....", "....bb.b..bb.b....",
        "....bb.b..bb.b....", "...kk..kk.kk.kk...",
    ])
    private static let sitA = tyan([
        "...........b...b..", "...........bb.bb..", "...........bbbbb..", "..........bbebebb.", ".........bbbbnbbb.",
        "....bb...bbbwwwb..", "...bbbb..bbbwwwb..", "..bbdbbbbbbbbwb...", "..bbbbbbbbbbbb....", ".dbbbbbbbbbbbb....",
        ".dbbbbbbbbbbbb....", "..kkkkkkkkkkk.....",
    ])
    private static let sitB = tyan([
        "...........b...b..", "...........bb.bb..", "...........bbbbb..", "..........bbebebb.", ".........bbbbnbbb.",
        "..........bbwwwb..", "...bb....bbbwwwb..", "..bbbb.bbbbbbbwb..", "..bbdbbbbbbbbbb...", "..dbbbbbbbbbbb....",
        "..dbbbbbbbbbbb....", "..kkkkkkkkkkk.....",
    ])
    private static let sleepA = tyan([
        "..................", "..................", "..................", "..................", "..................",
        "....bbbbbbbb......", "..bbbbdbdbbbbb....", ".bbbbbbbbbbbbbbbb.", ".bdbbbbbbbbbbebeb.", ".bbbbbbbbbbbwwnbb.",
        "..dddbbbbbbbbbbb..", "....dddddddddd....",
    ])
    private static let sleepB = tyan([
        "..................", "..................", "..................", "..................", "..................",
        "..................", "....bbbbbbbb......", "..bbbbdbdbbbbb....", ".bbbbbbbbbbbbbbbb.", ".bdbbbbbbbbbbebeb.",
        ".bbbbbbbbbbbwwnbb.", "..dddddddddddddd..",
    ])
    private static let waveA = tyan([
        "...........b...b..", "...........bb.bb..", "...........bbbbb..", "..........bbebebb.", ".........bbbbnbbb.",
        "....bb...bbbwwwb.b", "...bbbb..bbbwwwbbb", "..bbdbbbbbbbbwb.b.", "..bbbbbbbbbbbb....", ".dbbbbbbbbbbbb....",
        ".dbbbbbbbbbbbb....", "..kkkkkkkkkkk.....",
    ])
    private static let waveB = tyan([
        "...........b...b..", "...........bb.bb..", "...........bbbbb..", "..........bbebebb.", ".........bbbbnbbb.",
        "....bb...bbbwwwbbb", "...bbbb..bbbwwwb.b", "..bbdbbbbbbbbwb...", "..bbbbbbbbbbbb....", ".dbbbbbbbbbbbb....",
        ".dbbbbbbbbbbbb....", "..kkkkkkkkkkk.....",
    ])
    private static let jump = tyan([
        "..........b...b...", "..........bb.bb...", "..........bbbbb...", ".........bbebebb..", "........bbbbnbbb.b",
        "..d.bbbbbbbbwwwbbb", ".dbbbbbbbbbbbwb.b.", ".dbbbbbbbbbbbb....", "..bbbbbbbbbbb.....", "..bb.bb....bb.b...",
        "..kk.kk....kk.kk..", "..................",
    ])

    /// Тян внутри рамки 48×27 (спрайт 36×24 по центру).
    static func cat(_ pose: CatPose, t: CGFloat) {
        let origin = NSPoint(x: (CatArt.width - 18 * px) / 2, y: 1)
        var rows: [String]
        var closed = false, dim = false
        switch pose {
        case .walk:  rows = Int(t * 9 / .pi) % 2 == 0 ? walkA : walkB
        case .sit:   rows = Int(t * 2.5) % 2 == 0 ? sitA : sitB
        case .wave:  rows = Int(t * 4) % 2 == 0 ? waveA : waveB
        case .sleep: rows = Int(t * 1.1) % 2 == 0 ? sleepA : sleepB
        case .jump:  rows = jump
        case .pet:   rows = sitA; closed = true
        case .sad:   rows = sitB; dim = true
        }
        drawGrid(rows, palette: catPalette, at: origin, dim: dim, closedEyes: closed)
    }

    // MARK: Бэн (йоркширский терьер)

    static let dogPalette: [Character: NSColor] = [
        "b": NSColor(srgbRed: 0.88, green: 0.62, blue: 0.28, alpha: 1),   // рыжий
        "l": NSColor(srgbRed: 0.97, green: 0.79, blue: 0.47, alpha: 1),   // светло-золотой (чёлка, грудка, лапки)
        "f": NSColor(srgbRed: 0.62, green: 0.39, blue: 0.17, alpha: 1),   // дальние лапы
        "g": NSColor(srgbRed: 0.36, green: 0.38, blue: 0.44, alpha: 1),   // стальная седловина
        "d": NSColor(srgbRed: 0.50, green: 0.29, blue: 0.13, alpha: 1),   // уши
        "k": NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),   // нос, глаза
        "r": NSColor(srgbRed: 0.80, green: 0.25, blue: 0.30, alpha: 1),   // ошейник
        "t": NSColor(srgbRed: 0.95, green: 0.45, blue: 0.52, alpha: 1),   // язык
        "w": NSColor(srgbRed: 0.97, green: 0.95, blue: 0.88, alpha: 1),   // кость
    ]

    static let dogW = 17, dogH = 11

    /// Голова: центр головы (cx, cy), mouth — пасть открыта.
    private static func dogHead(_ c: inout Canvas, _ cx: Int, _ cy: Int, mouth: Bool = false, closed: Bool = false) {
        c.pts([(cx - 3, cy - 3), (cx - 2, cy - 3), (cx - 3, cy - 2)], "d")      // левое ухо
        c.pts([(cx + 2, cy - 3), (cx + 3, cy - 3), (cx + 3, cy - 2)], "d")      // правое ухо
        c.ell(Double(cx) + 0.5, Double(cy) + 0.5, 3.4, 2.9, "b")                // голова
        c.ell(Double(cx) + 0.5, Double(cy) - 0.5, 3.1, 1.8, "l")                // чёлка
        c.rect(cx - 1, cy + 1, 4, 2, "b")                                       // морда
        c.set(cx + 3, cy + 1, "k")                                              // нос
        if closed { c.pts([(cx - 1, cy), (cx + 1, cy)], "g") }
        else { c.pts([(cx - 1, cy), (cx + 2, cy)], "k") }                       // глаза из-под чёлки
        if mouth { c.pts([(cx + 2, cy + 2), (cx + 3, cy + 2)], "t") }
    }

    private static func dogBody(_ c: inout Canvas, tailUp: Bool = true, saddleShift: Int = 0) {
        c.ell(8, 6.2, 6.2, 2.7, "b")                                            // корпус
        c.ell(7.6, 5.2, 5.6, 1.6, "g")                                          // седловина
        c.ell(11.3, 6.6, 2.0, 2.2, "l")                                         // грудка
        if tailUp { c.pts([(2, 4), (1, 3), (1, 2)], "b"); c.set(0, 1, "g") }
    }

    private static func dogLegs(_ c: inout Canvas, _ offs: [Int], lift: [Int] = [0, 0, 0, 0]) {
        // порядок: дальняя задняя, дальняя передняя, ближняя задняя, ближняя передняя
        let xs = [5, 10, 4, 11]
        let far = [true, true, false, false]
        for i in 0..<4 {
            let x = xs[i] + offs[i]
            let col: Character = far[i] ? "f" : "b"
            let top = 8 - lift[i]
            c.rect(x, top, 1, 2, col)
            c.rect(x, 10 - lift[i], 2, 1, far[i] ? "f" : "l")
        }
    }

    private static func dogStand(frame: Int, mouth: Bool = false, headUp: Bool = false) -> [String] {
        var c = Canvas(dogW, dogH)
        let phases: [[Int]] = [[-1, 1, 1, -1], [0, 0, 0, 0], [1, -1, -1, 1], [0, 0, 0, 0]]
        let lifts: [[Int]] = [[0, 1, 1, 0], [0, 0, 0, 0], [1, 0, 0, 1], [0, 0, 0, 0]]
        dogLegs(&c, phases[frame % 4], lift: lifts[frame % 4])
        dogBody(&c)
        c.set(10, 5, "r"); c.set(10, 6, "r")
        dogHead(&c, 13, headUp ? 2 : 3, mouth: mouth)
        return c.rows
    }

    private static func dogSit() -> [String] {
        var c = Canvas(dogW, dogH)
        c.ell(5.5, 7.6, 3.6, 2.6, "b")                                          // бедро
        c.ell(9.0, 5.8, 2.6, 4.0, "b")                                          // торс
        c.ell(8.6, 5.0, 2.0, 3.0, "g")
        c.ell(10.8, 6.6, 1.4, 2.8, "l")
        c.rect(10, 8, 1, 3, "f"); c.rect(12, 8, 1, 3, "b"); c.rect(10, 10, 4, 1, "l")
        c.rect(3, 10, 4, 1, "l")
        c.pts([(1, 8), (0, 7), (0, 6)], "b"); c.set(0, 5, "g")
        c.set(10, 4, "r")
        dogHead(&c, 12, 2)
        return c.rows
    }

    private static func dogLie(frame: Int, gnaw: Bool, closed: Bool) -> [String] {
        var c = Canvas(dogW, dogH)
        let bob = gnaw ? (frame % 2) : 0
        c.ell(8, 8.2, 6.8, 2.3, "b")
        c.ell(7.6, 7.3, 5.8, 1.4, "g")
        c.rect(12, 9, 4, 2, "l")                                               // передние лапки
        c.pts([(1, 8), (0, 7), (0, 6)], "b"); c.set(0, 5, "g")
        c.set(11, 7, "r")
        dogHead(&c, 14, 6 + bob, mouth: false, closed: closed)
        return c.rows
    }

    private static func dogMark(frame: Int) -> [String] {
        var c = Canvas(dogW, dogH)
        dogLegs(&c, [0, 0, 0, 0])
        // дальняя задняя нога поднята назад
        c.rect(5, 8, 1, 2, "b")
        c.pts([(2, 6), (3, 7)], "b"); c.set(1, 5, "l")
        dogBody(&c)
        c.set(10, 5, "r"); c.set(10, 6, "r")
        dogHead(&c, 13, 3)
        return c.rows
    }

    private static func dogBow() -> [String] {
        var c = Canvas(dogW, dogH)
        c.ell(7.5, 5.2, 6.0, 2.4, "b")
        c.ell(7.2, 4.2, 5.4, 1.5, "g")
        c.ell(10.8, 6.6, 1.8, 2.0, "l")
        c.pts([(2, 3), (1, 2), (1, 1)], "b"); c.set(0, 0, "g")
        c.rect(3, 7, 1, 3, "b"); c.rect(5, 7, 1, 3, "f"); c.rect(3, 10, 2, 1, "l")
        c.rect(11, 8, 4, 2, "l"); c.rect(10, 8, 1, 2, "b")               // передние лапы вытянуты вперёд
        c.set(10, 5, "r")
        dogHead(&c, 14, 6, mouth: true)
        return c.rows
    }

    private static func dogJump() -> [String] {
        var c = Canvas(dogW, dogH)
        c.ell(8, 5.4, 6.0, 2.4, "b")
        c.ell(7.6, 4.4, 5.4, 1.5, "g")
        c.ell(11.3, 5.8, 1.8, 2.0, "l")
        c.pts([(2, 3), (1, 2), (1, 1)], "b"); c.set(0, 0, "g")
        c.pts([(2, 7), (1, 8), (0, 9)], "f"); c.pts([(4, 7), (3, 8), (2, 9)], "b")       // задние назад
        c.pts([(11, 7), (12, 8), (13, 9)], "b"); c.pts([(13, 6), (14, 7), (15, 8)], "f")  // передние вперёд
        c.set(10, 4, "r")
        dogHead(&c, 14, 2, mouth: true)
        return c.rows
    }

    static func dog(_ pose: DogPose, t: CGFloat) {
        let origin = NSPoint(x: (DogArt.width - CGFloat(dogW) * px) / 2, y: 1)
        let frame4 = Int(t * 9 / (.pi / 2))
        let rows: [String]
        var closed = false
        switch pose {
        case .walk:  rows = dogStand(frame: frame4)
        case .sit:   rows = dogSit()
        case .bark:  rows = dogStand(frame: 1, mouth: Int(t * 3.5) % 2 == 0, headUp: true)
        case .mark:  rows = dogMark(frame: 0)
        case .bow:   rows = dogBow()
        case .jump:  rows = dogJump()
        case .sleep: rows = dogLie(frame: Int(t * 1.1), gnaw: false, closed: true); closed = true
        case .gnaw:  rows = dogLie(frame: Int(t * 5), gnaw: true, closed: false)
        }
        drawGrid(rows, palette: dogPalette, at: origin, closedEyes: closed)
    }

    // MARK: Кость, клубок, будка

    private static let boneRows = [
        "ww...ww",
        ".wwwww.",
        "ww...ww",
    ]

    static func bone(center: NSPoint, flipped: Bool) {
        drawGrid(boneRows, palette: dogPalette,
                 at: NSPoint(x: center.x - 3.5 * px, y: center.y - 1.5 * px), flippedInside: flipped)
    }

    private static let yarnRows = [
        "..yyy..", ".yYyyy.", "yyyYyyy", "yYyyyYy", "yyYyyyy", ".yyYyy.", "..yyy..",
    ]
    private static let yarnPalette: [Character: NSColor] = [
        "y": NSColor(srgbRed: 0.88, green: 0.32, blue: 0.42, alpha: 1),
        "Y": NSColor(srgbRed: 0.62, green: 0.17, blue: 0.28, alpha: 1),
    ]

    static func yarn(center: NSPoint, angle: CGFloat) {
        var rows = yarnRows
        let quarter = ((Int((angle / (.pi / 2)).rounded()) % 4) + 4) % 4
        for _ in 0..<quarter { rows = rotate90(rows) }
        drawGrid(rows, palette: yarnPalette, at: NSPoint(x: center.x - 3.5 * px, y: center.y - 3.5 * px))
    }

    private static let housePalette: [Character: NSColor] = [
        "R": NSColor(srgbRed: 0.72, green: 0.24, blue: 0.24, alpha: 1),
        "S": NSColor(srgbRed: 0.52, green: 0.16, blue: 0.18, alpha: 1),
        "o": NSColor(srgbRed: 0.74, green: 0.50, blue: 0.30, alpha: 1),
        "O": NSColor(srgbRed: 0.55, green: 0.35, blue: 0.20, alpha: 1),
        "x": NSColor(srgbRed: 0.10, green: 0.07, blue: 0.06, alpha: 1),
        "s": NSColor(srgbRed: 0.96, green: 0.92, blue: 0.78, alpha: 1),
        "m": NSColor(srgbRed: 0.45, green: 0.15, blue: 0.15, alpha: 1),
    ]

    private static func houseRows() -> [String] {
        let w = 25, h = 13
        var c = Canvas(w, h)
        // крыша ступеньками
        for i in 0..<6 { c.rect(i * 2, 6 - i, w - i * 4, 1, i % 2 == 0 ? "R" : "S") }
        c.rect(0, 6, w, 1, "S")
        // стены
        c.rect(1, 7, w - 2, 6, "o")
        for x in stride(from: 4, to: w - 1, by: 3) { c.rect(x, 7, 1, 6, "O") }
        // вход
        c.rect(9, 9, 7, 4, "x"); c.rect(10, 8, 5, 1, "x"); c.rect(11, 7, 3, 1, "x")
        // табличка «БЭН»
        c.rect(9, 2, 7, 4, "s")
        c.rect(10, 3, 5, 1, "m"); c.rect(11, 4, 3, 1, "m")
        return c.rows
    }

    static func house() {
        drawGrid(houseRows(), palette: housePalette, at: NSPoint(x: (DogArt.houseWidth - 25 * px) / 2, y: 0))
    }
}
