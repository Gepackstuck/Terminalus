import AppKit

/// Лимиты подписки Claude (5 часов / неделя).
///
/// Откуда данные: Claude Code передаёт `rate_limits` в statusLine-скрипт. Наш скрипт
/// (ставится в «Application Support/Terminalus») сохраняет этот JSON в файл, а мы его читаем.
/// Работает для любых сеансов claude, не только запущенных в этом приложении.
@MainActor
final class LimitsStore {
    static let shared = LimitsStore()

    struct Window: Equatable {
        var percent: Double
        var resetsAt: Date
        var isLive: Bool { resetsAt > Date() }
    }

    private(set) var five: Window?
    private(set) var week: Window?
    private(set) var updatedAt: Date?
    private var lastMTime: Date?

    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Terminalus")
    static let scriptURL = dir.appendingPathComponent("statusline.sh")
    static let tabsDir = dir.appendingPathComponent("tabs")
    static let dataURL = dir.appendingPathComponent("statusline.json")
    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    enum SetupError: LocalizedError {
        case foreignStatusLine
        case badSettings
        var errorDescription: String? {
            switch self {
            case .foreignStatusLine:
                return "В ~/.claude/settings.json уже настроен другой statusLine — я его не трогаю. Уберите его или добавьте вызов \(LimitsStore.scriptURL.path) в свой скрипт."
            case .badSettings:
                return "Не удалось разобрать ~/.claude/settings.json (не валидный JSON?)."
            }
        }
    }

    // MARK: Подключение

    var isConnected: Bool {
        guard let data = try? Data(contentsOf: Self.settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sl = obj["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd.contains(Self.scriptURL.path)
    }

    private static let script = #"""
    #!/bin/sh
    # Terminalus: сохраняет данные statusLine Claude Code (в т.ч. лимиты) для приложения.
    dir="$HOME/Library/Application Support/Terminalus"
    mkdir -p "$dir/tabs"
    input=$(cat)
    tmp="$dir/statusline.json.$$"
    printf '%s' "$input" > "$tmp" || exit 0
    # отдельный файл для каждой вкладки Terminalus (нужно, чтобы показывать модель именно этой вкладки)
    if [ -n "$TERMINALUS_TAB_ID" ]; then
      cp "$tmp" "$dir/tabs/$TERMINALUS_TAB_ID.json.tmp" && mv "$dir/tabs/$TERMINALUS_TAB_ID.json.tmp" "$dir/tabs/$TERMINALUS_TAB_ID.json"
    fi
    mv "$tmp" "$dir/statusline.json"
    # ничего не печатаем: иначе текст появится в интерфейсе Claude Code
    """#

    /// Обновляет установленный скрипт до актуальной версии (если уже подключено).
    func refreshInstalledScript() {
        guard isConnected else { return }
        try? writeScript()
    }

    private func writeScript() throws {
        try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let text = Self.script.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }.joined(separator: "\n") + "\n"
        try text.write(to: Self.scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.scriptURL.path)
    }

    /// Пишет скрипт и добавляет statusLine в ~/.claude/settings.json (с бэкапом).
    func connect() throws {
        let fm = FileManager.default
        try writeScript()

        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: Self.settingsURL) {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SetupError.badSettings
            }
            obj = parsed
            if let sl = obj["statusLine"] as? [String: Any],
               !((sl["command"] as? String) ?? "").contains(Self.scriptURL.path) {
                throw SetupError.foreignStatusLine
            }
            let backup = Self.settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.terminalus-backup")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: Self.settingsURL, to: backup)
        } else {
            try fm.createDirectory(at: Self.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        // путь содержит пробел («Application Support») — команду обязательно в кавычки
        obj["statusLine"] = ["type": "command", "command": "'\(Self.scriptURL.path)'"]
        let out = try JSONSerialization.data(withJSONObject: obj,
                                             options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: Self.settingsURL, options: .atomic)
    }

    // MARK: Чтение

    /// Возвращает true, если данные изменились (или истёк срок окна).
    @discardableResult
    func refresh() -> Bool {
        let before = (five, week)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: Self.dataURL.path),
           let m = attrs[.modificationDate] as? Date, m != lastMTime {
            lastMTime = m
            if let data = try? Data(contentsOf: Self.dataURL),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rl = obj["rate_limits"] as? [String: Any] {
                // Сеанс без rate_limits (до первого ответа API) не затирает известные значения.
                five = Self.window(rl["five_hour"]) ?? five
                week = Self.window(rl["seven_day"]) ?? week
                updatedAt = m
            }
        }
        if let f = five, !f.isLive { five = nil }
        if let w = week, !w.isLive { week = nil }
        return before.0 != five || before.1 != week
    }

    private static func window(_ any: Any?) -> Window? {
        guard let d = any as? [String: Any],
              let p = (d["used_percentage"] as? NSNumber)?.doubleValue,
              let r = (d["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        return Window(percent: p, resetsAt: Date(timeIntervalSince1970: r))
    }
}

// MARK: - Виджет в панели вкладок

final class LimitsView: NSView {
    var connected = false { didSet { refreshLayout() } }
    var five: LimitsStore.Window? { didSet { needsDisplay = true; updateTip() } }
    var week: LimitsStore.Window? { didSet { needsDisplay = true; updateTip() } }
    var updatedAt: Date?
    var onClick: (() -> Void)?

    private let segW: CGFloat = 96

    var preferredWidth: CGFloat { connected ? segW * 2 + 10 : 132 }

    private func refreshLayout() {
        needsDisplay = true
        superview?.needsLayout = true
        updateTip()
    }

    private func color(_ p: Double) -> NSColor {
        p < 60 ? NSColor(srgbRed: 0.30, green: 0.80, blue: 0.48, alpha: 1)
               : (p < 85 ? NSColor(srgbRed: 1.0, green: 0.62, blue: 0.25, alpha: 1)
                         : NSColor(srgbRed: 0.95, green: 0.33, blue: 0.33, alpha: 1))
    }

    private func remaining(_ w: LimitsStore.Window?) -> String {
        guard let w else { return "нет данных" }
        let s = Int(w.resetsAt.timeIntervalSinceNow)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? "\(d) д \(h) ч" : (h > 0 ? "\(h) ч \(m) мин" : "\(m) мин")
    }

    private func updateTip() {
        guard connected else {
            toolTip = "Нажмите, чтобы показывать лимиты Claude (5 часов и неделя)"
            return
        }
        var t = "Лимит 5 часов: \(five.map { "\(Int($0.percent))%" } ?? "—"), сброс через \(remaining(five))\n"
        t += "Недельный лимит: \(week.map { "\(Int($0.percent))%" } ?? "—"), сброс через \(remaining(week))"
        if let u = updatedAt {
            t += "\nОбновлено: \(DateFormatter.localizedString(from: u, dateStyle: .none, timeStyle: .short))"
        } else {
            t += "\nДанные появятся после первого ответа Claude"
        }
        toolTip = t
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        func text(_ s: String, _ c: NSColor, x: CGFloat) {
            let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c])
            a.draw(at: NSPoint(x: x, y: (bounds.height - a.size().height) / 2))
        }
        guard connected else {
            text("◔ Лимиты: подключить", .secondaryLabelColor, x: 0)
            return
        }
        for (i, item) in [("5ч", five), ("7д", week)].enumerated() {
            let x0 = CGFloat(i) * (segW + 10)
            text(item.0, .tertiaryLabelColor, x: x0)
            let bar = NSRect(x: x0 + 20, y: bounds.midY - 2.5, width: 36, height: 5)
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
            if let w = item.1 {
                let p = max(0, min(100, w.percent))
                var fill = bar
                fill.size.width = max(5, bar.width * p / 100)
                color(p).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
                text("\(Int(p.rounded()))%", color(p), x: x0 + 62)
            } else {
                text("—", .tertiaryLabelColor, x: x0 + 62)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !connected { onClick?() }
    }
}
