import AppKit

/// Окно «Агенты…»: какие агенты известны, как их запускать и продолжать, какой — по умолчанию.
/// Плюс вопрос при первом запуске.
@MainActor
final class AgentsWindowController: NSWindowController, NSTextFieldDelegate {
    static let shared = AgentsWindowController()

    private var profiles: [AgentProfile] = []
    private let stack = NSStackView()
    private var defaultPopup: NSPopUpButton!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Агенты"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        w.contentView = stack
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        rebuild()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Интерфейс

    private func label(_ s: String, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: bold ? 13 : 12, weight: bold ? .semibold : .regular)
        if secondary { l.textColor = .secondaryLabelColor }
        return l
    }

    private func field(_ value: String, width: CGFloat, tag: Int, column: Int, placeholder: String = "") -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        f.delegate = self
        f.tag = tag * 10 + column
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    private func rebuild() {
        profiles = Agents.all
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        stack.addArrangedSubview(label("Terminalus работает с любым терминальным агентом. Агента, которого вы запустили вручную в любой вкладке, приложение определяет само и запоминает за этой вкладкой. Здесь можно настроить команды запуска и продолжения сеанса.", secondary: true))
        stack.arrangedSubviews.last?.widthAnchor.constraint(equalToConstant: 716).isActive = true

        // агент по умолчанию
        defaultPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        defaultPopup.addItem(withTitle: "Никакого — просто терминал")
        for p in profiles { defaultPopup.addItem(withTitle: p.name + (Agents.isInstalled(p) ? "  ✓ установлен" : "")) }
        if let i = profiles.firstIndex(where: { $0.id == Agents.defaultID }) { defaultPopup.selectItem(at: i + 1) } else { defaultPopup.selectItem(at: 0) }
        defaultPopup.target = self
        defaultPopup.action = #selector(defaultChanged)
        let defRow = NSStackView(views: [label("Агент по умолчанию (⇧⌘T):", bold: true), defaultPopup])
        defRow.spacing = 10
        stack.addArrangedSubview(defRow)

        // таблица агентов
        let grid = NSGridView()
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.addRow(with: [label("Название", bold: true), label("Запуск", bold: true), label("Продолжение сеанса", bold: true), NSView()])
        for (i, p) in profiles.enumerated() {
            let name: NSView = p.builtIn ? label(p.name) : field(p.name, width: 130, tag: i, column: 0)
            let del: NSView
            if p.builtIn { del = NSView() } else {
                let b = NSButton(title: "Удалить", target: self, action: #selector(deleteProfile(_:)))
                b.tag = i
                b.bezelStyle = .rounded
                b.controlSize = .small
                del = b
            }
            grid.addRow(with: [name, field(p.command, width: 190, tag: i, column: 1),
                               field(p.resume, width: 320, tag: i, column: 2, placeholder: "как запуск"), del])
        }
        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(label("«{session}» в команде продолжения заменяется идентификатором сеанса, если он известен (сейчас — для Claude Code). Команды продолжения для других агентов взяты из их документации; если у вашей версии флаги другие — поправьте здесь.", secondary: true))
        stack.arrangedSubviews.last?.widthAnchor.constraint(equalToConstant: 716).isActive = true

        let add = NSButton(title: "Добавить своего агента", target: self, action: #selector(addProfile))
        let reset = NSButton(title: "Вернуть настройки по умолчанию", target: self, action: #selector(resetProfiles))
        let row = NSStackView(views: [add, reset])
        row.spacing = 10
        stack.addArrangedSubview(row)
        window?.setContentSize(stack.fittingSize)
    }

    // MARK: Действия

    @objc private func defaultChanged() {
        let i = defaultPopup.indexOfSelectedItem
        Agents.defaultID = i <= 0 ? "" : profiles[i - 1].id
    }

    @objc private func addProfile() {
        var list = Agents.all
        list.append(AgentProfile(id: "custom-" + String(UUID().uuidString.prefix(6)).lowercased(), name: "Свой агент",
                                 command: "", resume: "", resumeFallback: "", match: [], builtIn: false, hasLimits: false))
        Agents.all = list
        rebuild()
    }

    @objc private func deleteProfile(_ sender: NSButton) {
        var list = Agents.all
        guard sender.tag < list.count, !list[sender.tag].builtIn else { return }
        let removed = list.remove(at: sender.tag)
        if Agents.defaultID == removed.id { Agents.defaultID = "" }
        Agents.all = list
        rebuild()
    }

    @objc private func resetProfiles() {
        Agents.resetToDefaults()
        rebuild()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        let row = f.tag / 10, col = f.tag % 10
        var list = Agents.all
        guard row < list.count else { return }
        switch col {
        case 0: list[row].name = f.stringValue
        case 1:
            list[row].command = f.stringValue
            if !list[row].builtIn { list[row].match = [list[row].executable] }      // свой агент узнаётся по имени программы
        default: list[row].resume = f.stringValue
        }
        Agents.all = list
    }

    // MARK: Вопрос при первом запуске

    /// Спрашивает, каким агентом пользуется человек. Однократно.
    static func promptFirstRun(over window: NSWindow?) {
        guard !Agents.firstRunDone else { return }
        // Кто уже пользовался приложением (есть сохранённые вкладки) — молча оставляем Claude Code.
        if UserDefaults.standard.data(forKey: "terminalus.state.v1") != nil {
            Agents.defaultID = "claude"
            Agents.firstRunDone = true
            return
        }
        let (alert, popup, profiles) = makeFirstRunAlert()
        let done: (NSApplication.ModalResponse) -> Void = { _ in
            let i = popup.indexOfSelectedItem
            Agents.defaultID = i <= 0 ? "" : profiles[i - 1].id
            Agents.firstRunDone = true
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: done) } else { done(alert.runModal()) }
    }

    /// Диалог первого запуска (вынесен, чтобы его можно было показать и в демо-картинках).
    static func makeFirstRunAlert() -> (NSAlert, NSPopUpButton, [AgentProfile]) {
        let profiles = Agents.all
        let alert = NSAlert()
        alert.messageText = "Каким агентом вы пользуетесь?"
        alert.informativeText = """
        Terminalus работает с любым терминальным агентом. Выбранный запускается по ⇧⌘T. \
        А если вы запустите другого агента вручную в любой вкладке — приложение само это заметит и запомнит агента за этой вкладкой.

        Всё можно поменять позже: «Terminalus → Агенты…».
        """
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        popup.addItem(withTitle: "Никакого — просто терминал")
        for p in profiles { popup.addItem(withTitle: p.name + (Agents.isInstalled(p) ? "  ✓ установлен" : "")) }
        if let i = profiles.firstIndex(where: { Agents.isInstalled($0) }) { popup.selectItem(at: i + 1) }   // предвыбираем установленного
        alert.accessoryView = popup
        alert.addButton(withTitle: "Продолжить")
        return (alert, popup, profiles)
    }
}
