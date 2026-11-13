import AppKit

/// «Стопка» закреплённых вкладок слева в панели: показывает одну вкладку (выбранную или последнюю
/// показанную) цветным бейджем с полным названием папки; остальные закреплённые прячутся в список,
/// который открывается по кнопке справа. Так десятки вкладок можно держать открытыми и не занимать место.
final class PinnedStackView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onShowList: ((NSView) -> Void)?
    var menuProvider: ((UUID) -> NSMenu?)?

    private(set) var shownID: UUID?
    private var count = 0
    private var isSelected = false
    private var dimmed = false
    private var folder = ""
    private var attention: SessionStatus?          // у скрытых в списке вкладок есть, на что взглянуть

    private let dotBack = NSView()
    private let dot = StatusDotView(frame: NSRect(x: 0, y: 0, width: StatusDotView.size, height: StatusDotView.size))
    private let label = NSTextField(labelWithString: "")

    private var arrowZone: CGFloat { count > 1 ? 36 : 0 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dotBack.wantsLayer = true
        dotBack.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        dotBack.layer?.cornerRadius = 8
        addSubview(dotBack)
        addSubview(dot)
        label.font = .systemFont(ofSize: 12, weight: .heavy)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    var preferredWidth: CGFloat {
        let text = (label.stringValue as NSString).size(withAttributes: [.font: label.font!]).width
        return min(240, max(96, 10 + 16 + 7 + ceil(text) + 14 + arrowZone))
    }

    func update(shown: TerminalSession?, count: Int, selected: Bool, dimmed: Bool, attention: SessionStatus?) {
        shownID = shown?.id
        configure(folder: shown?.folder ?? shown?.displayTitle ?? "", status: shown?.status ?? .idle,
                  tip: shown?.detailText ?? "", count: count, selected: selected, dimmed: dimmed, attention: attention)
    }

    func configure(folder: String, status: SessionStatus, tip: String, count: Int, selected: Bool,
                   dimmed: Bool, attention: SessionStatus?) {
        self.count = count
        self.isSelected = selected
        self.dimmed = dimmed
        self.attention = attention
        self.folder = folder
        if label.stringValue != folder { label.stringValue = folder }
        dot.status = status
        toolTip = tip + (count > 1 ? "\n\nЗакреплено вкладок: \(count). Стрелка справа — список." : "")
        alphaValue = dimmed ? 0.5 : 1
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let d = StatusDotView.size
        dotBack.frame = NSRect(x: 7, y: (bounds.height - 16) / 2, width: 16, height: 16)
        dot.frame = NSRect(x: 7 + (16 - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 30, y: (bounds.height - h) / 2, width: max(0, bounds.width - 30 - arrowZone - 8), height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let base = FolderBadge.color(for: folder)
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        base.withAlphaComponent(isSelected ? 1 : 0.78).setFill()
        pill.fill()
        if isSelected {
            NSColor.white.withAlphaComponent(0.9).setStroke()
            pill.lineWidth = 1.5
            pill.stroke()
        }
        guard count > 1 else { return }

        // правая часть: счётчик и стрелка списка
        NSGraphicsContext.current?.saveGraphicsState()
        pill.addClip()
        NSColor.black.withAlphaComponent(0.20).setFill()
        NSRect(x: bounds.width - arrowZone, y: 0, width: arrowZone, height: bounds.height).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSRect(x: bounds.width - arrowZone, y: 6, width: 1, height: bounds.height - 12).fill()

        let num = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .heavy), .foregroundColor: NSColor.white])
        let cx = bounds.width - arrowZone / 2
        num.draw(at: NSPoint(x: cx - 9 - num.size().width / 2 + 3, y: bounds.midY - num.size().height / 2))
        let chev = NSBezierPath()
        chev.move(to: NSPoint(x: cx + 4, y: bounds.midY + 1.6))
        chev.line(to: NSPoint(x: cx + 7, y: bounds.midY - 1.6))
        chev.line(to: NSPoint(x: cx + 10, y: bounds.midY + 1.6))
        chev.lineWidth = 1.6
        chev.lineCapStyle = .round
        chev.lineJoinStyle = .round
        NSColor.white.setStroke()
        chev.stroke()

        // на скрытых вкладках есть событие — отмечаем точкой на углу
        if let a = attention {
            let dr = NSRect(x: bounds.width - 11, y: bounds.height - 10.5, width: 7, height: 7)
            Theme.barBG.setFill()
            NSBezierPath(ovalIn: dr.insetBy(dx: -1.5, dy: -1.5)).fill()
            a.color.setFill()
            NSBezierPath(ovalIn: dr).fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if count > 1 && p.x > bounds.width - arrowZone {
            onShowList?(self)
        } else if let id = shownID {
            onSelect?(id)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? { shownID.flatMap { menuProvider?($0) } }
}
