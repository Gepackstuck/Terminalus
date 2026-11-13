import AppKit

// MARK: - План агента

struct PlanItem: Equatable {
    enum Status { case pending, inProgress, completed }
    var text: String
    var active: String?          // «что делаю сейчас» (activeForm у TodoWrite)
    var status: Status
}

struct AgentPlan: Equatable {
    var items: [PlanItem]
    /// Текст плана из режима планирования (ExitPlanMode), если он новее списка дел.
    var planText: String?

    var done: Int { items.filter { $0.status == .completed }.count }
    var isEmpty: Bool { items.isEmpty && (planText ?? "").isEmpty }
    /// «3/7» — для шапки окна в сетке.
    var chip: String? { items.isEmpty ? nil : "\(done)/\(items.count)" }
}

/// Достаёт план из расшифровки сеанса Claude Code (JSONL): последний вызов `TodoWrite`
/// или `ExitPlanMode`. Читается только хвост файла.
enum PlanReader {
    static func read(transcriptPath path: String, tailBytes: Int = 1_500_000) -> AgentPlan? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }          // первая строка могла обрезаться

        // идём с конца: самый свежий TodoWrite / ExitPlanMode
        for line in lines.reversed() {
            guard line.count < 4_000_000,
                  let s = String(data: line, encoding: .utf8),
                  s.contains("\"TodoWrite\"") || s.contains("\"ExitPlanMode\"") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            for block in content.reversed() where block["type"] as? String == "tool_use" {
                let input = block["input"] as? [String: Any] ?? [:]
                switch block["name"] as? String {
                case "TodoWrite":
                    let todos = (input["todos"] as? [[String: Any]]) ?? []
                    let items: [PlanItem] = todos.compactMap { t in
                        guard let text = (t["content"] as? String) ?? (t["subject"] as? String) else { return nil }
                        let st: PlanItem.Status = {
                            switch t["status"] as? String {
                            case "completed": return .completed
                            case "in_progress": return .inProgress
                            default: return .pending
                            }
                        }()
                        return PlanItem(text: text, active: t["activeForm"] as? String, status: st)
                    }
                    return AgentPlan(items: items, planText: nil)
                case "ExitPlanMode":
                    if let plan = input["plan"] as? String, !plan.isEmpty { return AgentPlan(items: [], planText: plan) }
                default: break
                }
            }
        }
        return nil
    }
}

// MARK: - Панель

/// Отдельная панель справа: план выбранной вкладки.
final class PlanPanelView: NSView {
    static let width: CGFloat = 300

    private let title = NSTextField(labelWithString: "План агента")
    private let subtitle = NSTextField(labelWithString: "")
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let bar = ProgressBarView(frame: .zero)
    private let counter = NSTextField(labelWithString: "")
    private var signature = ""
    private var progress: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.barBG.cgColor
        title.font = .systemFont(ofSize: 13, weight: .heavy)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        counter.font = .systemFont(ofSize: 11, weight: .semibold)
        counter.textColor = .secondaryLabelColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -14),
        ])
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        [title, subtitle, bar, counter, scroll].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let w = bounds.width
        title.frame = NSRect(x: 14, y: bounds.height - 30, width: w - 28, height: 18)
        subtitle.frame = NSRect(x: 14, y: bounds.height - 48, width: w - 28, height: 15)
        bar.frame = NSRect(x: 14, y: bounds.height - 66, width: w - 28 - 52, height: 5)
        bar.progress = progress
        counter.frame = NSRect(x: w - 14 - 48, y: bounds.height - 71, width: 48, height: 15)
        counter.alignment = .right
        scroll.frame = NSRect(x: 0, y: 0, width: w, height: max(0, bounds.height - 80))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()       // разделитель слева
    }

    // MARK: Содержимое

    private func label(_ text: String, size: CGFloat = 12, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.preferredMaxLayoutWidth = Self.width - 28
        return l
    }

    private func row(_ item: PlanItem) -> NSView {
        let glyph: String, color: NSColor
        switch item.status {
        case .completed:  glyph = "✓"; color = .systemGreen
        case .inProgress: glyph = "◉"; color = .systemOrange
        case .pending:    glyph = "○"; color = .tertiaryLabelColor
        }
        let g = NSTextField(labelWithString: glyph)
        g.font = .systemFont(ofSize: 12, weight: .bold)
        g.textColor = color
        g.setContentHuggingPriority(.required, for: .horizontal)
        let text = item.status == .inProgress ? (item.active ?? item.text) : item.text
        let t = NSTextField(wrappingLabelWithString: text)
        t.font = .systemFont(ofSize: 12, weight: item.status == .inProgress ? .semibold : .regular)
        t.textColor = item.status == .completed ? .tertiaryLabelColor : (item.status == .inProgress ? .labelColor : .secondaryLabelColor)
        t.preferredMaxLayoutWidth = Self.width - 28 - 22
        let r = NSStackView(views: [g, t])
        r.orientation = .horizontal
        r.alignment = .top
        r.spacing = 8
        return r
    }

    func update(session: TerminalSession?) {
        let agent = session?.agentName
        let plan = session?.plan
        let sig = "\(session?.demoPlanActive == true ? "демо" : "")\(session?.id.uuidString ?? "-")|\(agent ?? "-")|\(session?.folder ?? "-")|\(plan?.items.map { "\($0.status)\($0.text)\($0.active ?? "")" }.joined(separator: "¦") ?? "")|\(plan?.planText ?? "")"
        guard sig != signature else { return }
        signature = sig

        subtitle.stringValue = ([session?.folder, agent] + [session?.demoPlanActive == true ? "пример" : nil]).compactMap { $0 }.joined(separator: " · ")
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        if let plan, !plan.items.isEmpty {
            progress = CGFloat(plan.done) / CGFloat(plan.items.count)
            counter.stringValue = "\(plan.done) из \(plan.items.count)"
            bar.isHidden = false
            plan.items.forEach { stack.addArrangedSubview(row($0)) }
        } else {
            progress = 0
            counter.stringValue = ""
            bar.isHidden = true
        }
        if let text = plan?.planText, !text.isEmpty {
            stack.addArrangedSubview(label("План (режим планирования)", size: 11, color: .secondaryLabelColor, weight: .semibold))
            stack.addArrangedSubview(label(String(text.prefix(2500))))
        }
        if plan == nil || plan!.isEmpty {
            let note: String
            if session == nil { note = "Нет выбранной вкладки." }
            else if session!.agentID == nil { note = "В этой вкладке нет агента. Запустите агента — и здесь появится его план." }
            else if session!.agentID != "claude" { note = "Чтение плана для агента «\(agent ?? "")» пока не поддерживается." }
            else if session!.transcriptPath == nil { note = "Подключите лимиты Claude («Terminalus → Показывать лимиты Claude…») — так приложение узнаёт файл сеанса и сможет читать план." }
            else { note = "План не найден. Он появится, когда агент начнёт вести список дел (инструмент TodoWrite) или выйдет из режима планирования." }
            stack.addArrangedSubview(label(note, size: 12, color: .secondaryLabelColor))
        }
        needsLayout = true
    }
}

/// Полоска прогресса (рисуется сама — без слоёв).
final class ProgressBarView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        guard progress > 0 else { return }
        NSColor.systemGreen.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: max(r.height, r.width * progress), height: r.height),
                     xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }
}

/// Документ прокрутки с началом координат сверху.
final class FlippedView: NSView { override var isFlipped: Bool { true } }
