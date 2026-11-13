import AppKit

/// Цветная метка вкладки (например, проект или окружение).
enum TagColor: String, CaseIterable, Codable {
    case red, orange, yellow, green, blue, purple

    var color: NSColor {
        switch self {
        case .red:    return NSColor(srgbRed: 0.95, green: 0.35, blue: 0.35, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.60, blue: 0.25, alpha: 1)
        case .yellow: return NSColor(srgbRed: 0.98, green: 0.80, blue: 0.25, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.35, green: 0.80, blue: 0.50, alpha: 1)
        case .blue:   return NSColor(srgbRed: 0.35, green: 0.62, blue: 1.00, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.70, green: 0.50, blue: 0.95, alpha: 1)
        }
    }
    var title: String {
        switch self {
        case .red: return "Красный"
        case .orange: return "Оранжевый"
        case .yellow: return "Жёлтый"
        case .green: return "Зелёный"
        case .blue: return "Синий"
        case .purple: return "Фиолетовый"
        }
    }

    /// Кружок для пунктов меню.
    var swatch: NSImage {
        let img = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            self.color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return img
    }
}
