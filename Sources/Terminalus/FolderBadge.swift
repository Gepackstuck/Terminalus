import AppKit

/// Иконка папки: цветной скруглённый квадрат с инициалами. Цвет и буквы стабильно выводятся из названия.
enum FolderBadge {
    private static let palette: [NSColor] = [
        NSColor(srgbRed: 0.93, green: 0.42, blue: 0.36, alpha: 1),   // коралловый
        NSColor(srgbRed: 0.96, green: 0.60, blue: 0.24, alpha: 1),   // оранжевый
        NSColor(srgbRed: 0.88, green: 0.72, blue: 0.20, alpha: 1),   // янтарный
        NSColor(srgbRed: 0.40, green: 0.72, blue: 0.36, alpha: 1),   // зелёный
        NSColor(srgbRed: 0.22, green: 0.70, blue: 0.62, alpha: 1),   // бирюзовый
        NSColor(srgbRed: 0.24, green: 0.66, blue: 0.88, alpha: 1),   // голубой
        NSColor(srgbRed: 0.34, green: 0.50, blue: 0.94, alpha: 1),   // синий
        NSColor(srgbRed: 0.52, green: 0.42, blue: 0.92, alpha: 1),   // индиго
        NSColor(srgbRed: 0.72, green: 0.44, blue: 0.88, alpha: 1),   // фиолетовый
        NSColor(srgbRed: 0.90, green: 0.40, blue: 0.64, alpha: 1),   // розовый
        NSColor(srgbRed: 0.18, green: 0.64, blue: 0.46, alpha: 1),   // изумрудный
        NSColor(srgbRed: 0.84, green: 0.34, blue: 0.20, alpha: 1),   // терракотовый
        NSColor(srgbRed: 0.40, green: 0.55, blue: 0.70, alpha: 1),   // стальной синий
        NSColor(srgbRed: 0.62, green: 0.38, blue: 0.70, alpha: 1),   // сливовый
    ]

    /// Детерминированный хэш (в отличие от hashValue не меняется между запусками).
    private static func stableHash(_ s: String) -> UInt32 {
        var h: UInt32 = 5381
        for u in s.lowercased().unicodeScalars { h = (h &* 33) &+ u.value }
        return h
    }

    static func color(for name: String) -> NSColor { palette[Int(stableHash(name)) % palette.count] }

    /// Части названия: «HRAdmin» → [HR, Admin], «myProject2» → [my, Project, 2], «api-gateway» → [api, gateway].
    static func tokens(_ name: String) -> [String] {
        var out: [String] = []
        var cur = ""
        let chars = Array(name)
        func flush() { if !cur.isEmpty { out.append(cur); cur = "" } }
        for (i, ch) in chars.enumerated() {
            guard ch.isLetter || ch.isNumber else { flush(); continue }
            if let prev = cur.last {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let lowerToUpper = prev.isLowercase && ch.isUppercase
                let acronymEnd = prev.isUppercase && ch.isUppercase && (next?.isLowercase ?? false)   // HRAdmin: перед «A»
                let digitEdge = prev.isNumber != ch.isNumber
                if lowerToUpper || acronymEnd || digitEdge { flush() }
            }
            cur.append(ch)
        }
        flush()
        return out
    }

    /// Две буквы, чтобы папки различались:
    /// «HRAdmin» → HA, «myProject» → MP, «api-gateway» → AG, «reports2024» → R2,
    /// одно слово: «terminalus» → Te, «tvclean» → Tv, «vibecode» → Vi, «API» → AP, «~» → ~.
    static func letters(for name: String) -> String {
        if name == "~" { return "~" }
        let t = tokens(name)
        guard let first = t.first else { return "·" }
        if t.count >= 2 {
            return t.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
        }
        let chars = Array(first)
        if chars.count == 1 { return String(chars[0]).uppercased() }
        let second = chars[1]
        let secondOut = (second.isUppercase || second.isNumber) ? String(second) : String(second).lowercased()
        return String(chars[0]).uppercased() + secondOut
    }

    /// Картинка бейджа (для пунктов меню).
    static func image(for name: String, size: CGFloat = 16) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            color(for: name).setFill()
            NSBezierPath(roundedRect: r, xRadius: size * 0.28, yRadius: size * 0.28).fill()
            let text = letters(for: name)
            let font = NSFont.systemFont(ofSize: size * (text.count > 1 ? 0.5 : 0.62), weight: .heavy)
            let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
            let sz = str.size()
            str.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
            return true
        }
    }
}

final class FolderBadgeView: NSView {
    static let size: CGFloat = 16

    var name: String? { didSet { if oldValue != name { needsDisplay = true; toolTip = name } } }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let name else { return }
        FolderBadge.color(for: name).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4.5, yRadius: 4.5).fill()
        let text = FolderBadge.letters(for: name)
        let font = NSFont.systemFont(ofSize: text.count > 1 ? 8.5 : 10, weight: .heavy)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let sz = str.size()
        str.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2))
    }
}
