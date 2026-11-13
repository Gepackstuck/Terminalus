import AppKit

enum SessionStatus {
    case idle      // ничего не происходит
    case working   // задача выполняется
    case done      // задача завершилась, пока вкладка была не в фокусе
    case waiting   // Claude ждёт вашего ответа (запрос разрешения и т.п.)
    case sleeping  // вкладка в архиве: процессы остановлены

    var color: NSColor {
        switch self {
        case .idle:    return NSColor.white.withAlphaComponent(0.28)
        case .working: return NSColor(srgbRed: 1.0, green: 0.62, blue: 0.25, alpha: 1)
        case .done:    return NSColor(srgbRed: 0.30, green: 0.80, blue: 0.48, alpha: 1)
        case .waiting: return NSColor(srgbRed: 1.0, green: 0.82, blue: 0.22, alpha: 1)
        case .sleeping: return NSColor(srgbRed: 0.55, green: 0.62, blue: 0.88, alpha: 1)
        }
    }
    var label: String {
        switch self {
        case .idle: return "Ожидание"
        case .working: return "Выполняется"
        case .done: return "Завершено — ждёт вас"
        case .waiting: return "Ждёт вашего ответа"
        case .sleeping: return "В архиве"
        }
    }
}

/// Индикатор статуса 12×12:
///  • простой — тусклая точка
///  • работа — вращающаяся дуга на тонком кольце
///  • готово — зелёный кружок с галочкой
final class StatusDotView: NSView {
    static let size: CGFloat = 12

    var status: SessionStatus = .idle { didSet { if oldValue != status { apply() } } }

    private let track = CAShapeLayer()   // кольцо / точка / заливка
    private let arc = CAShapeLayer()     // вращающаяся дуга
    private let check = CAShapeLayer()   // галочка
    private let bang = CAShapeLayer()    // восклицательный знак

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        [track, arc, check, bang].forEach { layer?.addSublayer($0) }
        bang.fillColor = nil
        bang.strokeColor = NSColor(white: 0.1, alpha: 1).cgColor
        bang.lineWidth = 1.8
        bang.lineCap = .round
        arc.fillColor = nil
        arc.lineCap = .round
        arc.lineWidth = 2
        arc.strokeEnd = 0.3
        track.fillColor = nil
        check.fillColor = nil
        check.strokeColor = NSColor.white.cgColor
        check.lineWidth = 1.6
        check.lineCap = .round
        check.lineJoin = .round
        apply()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.size, height: Self.size) }

    override func layout() {
        super.layout()
        let b = bounds
        [track, arc, check, bang].forEach { $0.frame = b }
        let ring = CGPath(ellipseIn: b.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        arc.path = ring
        switch status {
        case .idle:    track.path = CGPath(ellipseIn: b.insetBy(dx: 3.5, dy: 3.5), transform: nil)
        case .working: track.path = ring
        case .done, .waiting: track.path = CGPath(ellipseIn: b.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        case .sleeping: track.path = CGPath(ellipseIn: b.insetBy(dx: 2.5, dy: 2.5), transform: nil)
        }
        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: b.midX, y: b.height * 0.40)); bp.addLine(to: CGPoint(x: b.midX, y: b.height * 0.73))
        bp.move(to: CGPoint(x: b.midX, y: b.height * 0.26)); bp.addLine(to: CGPoint(x: b.midX, y: b.height * 0.27))
        bang.path = bp
        let p = CGMutablePath()
        p.move(to: CGPoint(x: b.width * 0.29, y: b.height * 0.50))
        p.addLine(to: CGPoint(x: b.width * 0.44, y: b.height * 0.35))
        p.addLine(to: CGPoint(x: b.width * 0.72, y: b.height * 0.66))
        check.path = p
    }

    private func apply() {
        let c = status.color.cgColor
        toolTip = status.label
        arc.removeAllAnimations()
        arc.isHidden = status != .working
        check.isHidden = status != .done
        bang.isHidden = status != .waiting
        track.removeAllAnimations()
        switch status {
        case .idle:
            track.fillColor = c; track.strokeColor = nil; track.lineWidth = 0
        case .working:
            track.fillColor = nil; track.strokeColor = c.copy(alpha: 0.22); track.lineWidth = 2
            arc.strokeColor = c
            let a = CABasicAnimation(keyPath: "transform.rotation.z")
            a.fromValue = 0
            a.toValue = -2 * Double.pi
            a.duration = 0.85
            a.repeatCount = .infinity
            arc.add(a, forKey: "spin")
        case .done:
            track.fillColor = c; track.strokeColor = nil; track.lineWidth = 0
        case .sleeping:
            track.fillColor = nil; track.strokeColor = c; track.lineWidth = 1.4
        case .waiting:
            track.fillColor = c; track.strokeColor = nil; track.lineWidth = 0
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0; a.toValue = 0.45; a.duration = 0.7
            a.autoreverses = true; a.repeatCount = .infinity
            track.add(a, forKey: "pulse")
        }
        needsLayout = true
    }
}
