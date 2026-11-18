import AppKit

private struct SavedTab: Codable {
    var cwd: String?
    var claude: Bool
    var inGrid: Bool
    var pinned: Bool?
    var tag: String?
    var fontSize: Double?
    var claudeSession: String?
    var agent: String?
}
private struct SavedState: Codable {
    var tabs: [SavedTab]
    var selected: Int
    var grid: Bool
    var gridTree: SavedGridNode?   // раскладка сетки (дерево разбиений, листья — номера вкладок)
}

/// Данные пункта контекстного меню вкладки.
private final class MenuPayload: NSObject {
    let id: UUID
    let tag: TagColor?
    init(_ id: UUID, tag: TagColor? = nil) { self.id = id; self.tag = tag }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private static let stateKey = "terminalus.state.v1"

    private(set) var sessions: [TerminalSession] = []
    private var selectedID: UUID?
    private var gridMode = false
    /// Скрытая из сетки вкладка открыта отдельно → показываем кнопку «К сетке».
    private var returnToGrid = false
    private var counter = 0
    private var timer: Timer?

    private let tabBar = TabBarView(frame: .zero)
    private let content = NSView()
    private let grid = GridView(frame: .zero)
    private let catView = CatView(frame: .zero)

    private var selected: TerminalSession? { sessions.first { $0.id == selectedID } }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],   // панель вкладок — НЕ в области заголовка
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.barBG
        window.minSize = NSSize(width: 480, height: 320)
        window.title = "Terminalus"
        window.setFrameAutosaveName("TerminalusMainWindow")
        super.init(window: window)
        window.delegate = self

        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.terminalBG.cgColor
        tabBar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(content)
        root.addSubview(tabBar)
        layoutRoot()

        // Кот живёт в строке заголовка (поверх, прозрачный для мыши везде, кроме себя и клубка)
        if let frameView = root.superview {
            catView.autoresizingMask = [.width, .minYMargin]
            frameView.addSubview(catView)
            layoutCat()
        }

        tabBar.onSelect = { [weak self] in self?.select($0) }
        tabBar.onDoubleClick = { [weak self] in self?.revealInGrid($0) }
        tabBar.onClose = { [weak self] in self?.requestClose($0) }
        tabBar.onNew = { [weak self] in self?.chooseNewSession() }
        tabBar.onToggleGrid = { [weak self] in self?.toggleGrid() }
        tabBar.onFilter = { [weak self] in self?.showGridFilterMenu(from: $0) }
        tabBar.onMove = { [weak self] id, idx in self?.move(id, toInsertionIndex: idx) }
        tabBar.onBackToGrid = { [weak self] in self?.setGrid(true) }
        tabBar.tabMenuProvider = { [weak self] id in self?.tabMenu(for: id) }
        tabBar.onShowPinned = { [weak self] in self?.showPinnedMenu(from: $0) }

        grid.autoresizingMask = [.width, .height]
        grid.onSelect = { [weak self] in self?.select($0) }
        grid.onOpen = { [weak self] id in self?.select(id); self?.setGrid(false) }
        grid.onClose = { [weak self] in self?.requestClose($0) }
        grid.onHide = { [weak self] in self?.setInGrid($0, false) }
        grid.menuProvider = { [weak self] id in self?.tabMenu(for: id) }
        grid.onLayoutChanged = { [weak self] in self?.saveState() }

        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }

        LimitsStore.shared.refreshInstalledScript()
        tabBar.limits.onClick = { [weak self] in self?.connectLimits() }
        updateLimits(force: true)

        restoreOrStart()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.3
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Состояние (сохранение/восстановление)

    private func restoreOrStart() {
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let st = try? JSONDecoder().decode(SavedState.self, from: data), !st.tabs.isEmpty {
            for t in st.tabs {
                let agent = t.agent ?? (t.claude ? "claude" : nil)
                addSession(mode: agent.map { LaunchMode.agentResume($0) } ?? LaunchMode.shell, directory: t.cwd, inGrid: t.inGrid,
                           pinned: t.pinned ?? false, tag: t.tag.flatMap(TagColor.init(rawValue:)),
                           fontSize: t.fontSize.map { CGFloat($0) }, select: false,
                           sleeping: t.pinned ?? false, claudeSession: t.claudeSession)   // закреплённые не поднимаем, пока не откроют
            }
            selectedID = sessions[min(max(0, st.selected), sessions.count - 1)].id
            selected?.wake()
            gridMode = st.grid
            grid.tree = st.gridTree.flatMap { GNode.from($0, ids: sessions.map(\.id)) }
            refresh()
        } else {
            newSession()
        }
    }

    private var saveWork: DispatchWorkItem?

    /// События приходят пачками (выбор вкладки, смена статуса, перестановка) — записываем состояние один раз.
    func saveState() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.writeState() } }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    /// Немедленная запись (закрытие окна, выход из приложения).
    func flushState() {
        saveWork?.cancel()
        writeState()
    }

    private func writeState() {
        guard !sessions.isEmpty else { return }
        let st = SavedState(
            tabs: sessions.map {
                SavedTab(cwd: $0.cwd, claude: $0.sawClaude, inGrid: $0.inGrid, pinned: $0.isPinned,
                         tag: $0.tag?.rawValue, fontSize: $0.fontSize.map { Double($0) },
                         claudeSession: $0.claudeSessionID, agent: $0.agentID)
            },
            selected: sessions.firstIndex { $0.id == selectedID } ?? 0,
            grid: gridMode,
            gridTree: grid.tree?.saved(index: { id in sessions.firstIndex { $0.id == id } }))
        if let data = try? JSONEncoder().encode(st) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }

    // MARK: Сессии

    private func addSession(mode: LaunchMode, directory: String?, inGrid: Bool = true, pinned: Bool = false,
                            tag: TagColor? = nil, fontSize: CGFloat? = nil, select: Bool = true,
                            sleeping: Bool = false, claudeSession: String? = nil) {
        counter += 1
        let s = TerminalSession(index: counter, mode: mode, directory: directory, inGrid: inGrid,
                                pinned: pinned, tag: tag, fontSize: fontSize,
                                sleeping: sleeping, claudeSession: claudeSession)
        s.onExit = { [weak self, id = s.id] in self?.closeSession(id) }
        s.onFocus = { [weak self, id = s.id] in self?.select(id) }
        s.onEvent = { [weak self, id = s.id] ev in MainActor.assumeIsolated { self?.handle(ev, id) } }
        if select, let cur = sessions.firstIndex(where: { $0.id == selectedID }) {
            sessions.insert(s, at: cur + 1)       // новая вкладка — справа от текущей
        } else {
            sessions.append(s)
        }
        if select { selectedID = s.id }
        normalizePins()
    }

    /// По умолчанию новая вкладка открывается в общей папке (Settings.defaultFolder);
    /// `inCurrentFolder` — в папке текущей вкладки (для задач внутри проекта).
    func newSession(agent: AgentProfile? = nil, inCurrentFolder: Bool = false) {
        let dir = inCurrentFolder ? (selected?.cwd ?? Settings.defaultFolder) : Settings.defaultFolder
        addSession(mode: agent.map { LaunchMode.agent($0.id) } ?? LaunchMode.shell, directory: dir)
        returnToGrid = false
        refresh()
    }

    func chooseNewSession() {
        let menu = NSMenu()
        let choices = ["claude", "qwen"].compactMap { Agents.profile($0) }
        for p in choices {
            let item = NSMenuItem(title: p.name + (Agents.isInstalled(p) ? "" : "  (не найден)"), action: #selector(newSessionChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.id
            menu.addItem(item)
        }
        let plain = NSMenuItem(title: "Просто терминал", action: #selector(newSessionChoice(_:)), keyEquivalent: "")
        plain.target = self
        plain.representedObject = ""
        menu.addItem(plain)
        tabBar.popUpNewMenu(menu)
    }

    @objc private func newSessionChoice(_ sender: NSMenuItem) {
        newSession(agent: Agents.profile(sender.representedObject as? String))
    }

    func closeSession(_ id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let s = sessions.remove(at: idx)
        s.close()
        s.view.removeFromSuperview()
        if sessions.isEmpty {
            window?.close()
            return
        }
        if selectedID == id {
            selectedID = sessions[min(idx, sessions.count - 1)].id
        }
        refresh()
    }

    func closeCurrent() { if let id = selectedID { requestClose(id) } }

    /// Закрытие по действию пользователя (×, ⌘W): спрашиваем, если во вкладке что-то выполняется
    /// или она закреплена. Завершение шелла самим процессом идёт напрямую через closeSession.
    func requestClose(_ id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        guard s.hasRunningCommand || s.isPinned, let window else { closeSession(id); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Закрыть вкладку «\(s.displayTitle)»?"
        if s.hasRunningCommand {
            alert.informativeText = s.agentName != nil
                ? "В ней запущен агент (\(s.agentName ?? "")) или другая команда. Сеанс будет завершён, несохранённая работа может потеряться."
                : "В ней выполняется команда. Она будет завершена."
        } else {
            alert.informativeText = "Вкладка закреплена."
        }
        alert.addButton(withTitle: "Отмена")
        let close = alert.addButton(withTitle: "Закрыть")
        close.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertSecondButtonReturn else { return }
            MainActor.assumeIsolated { self?.closeSession(id) }
        }
    }

    func select(_ id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }) else { return }
        selectedID = id
        s.markSeen()
        s.touch()
        s.wake()                       // вкладка из архива поднимается при открытии
        if returnToGrid && !gridMode && s.inGrid {
            // Были на скрытой вкладке, открытой из сетки; клик по вкладке из сетки возвращает в сетку.
            gridMode = true
            returnToGrid = false
            refresh()
            return
        }
        if gridMode {
            if !s.inGrid {
                // Вкладка скрыта из сетки: открываем её отдельно, с кнопкой «К сетке».
                gridMode = false
                returnToGrid = true
                refresh()
                return
            }
            // без пересборки сетки — иначе собьются клик и выделение текста
            grid.setSelected(id)
            reloadTabBar()
            if s.view.window != nil { window?.makeFirstResponder(s.view) }
            updateBadge()
            saveState()
        } else if s.view.superview === content {
            reloadTabBar()
            if s.view.window != nil { window?.makeFirstResponder(s.view) }
            updateBadge()
            saveState()
        } else {
            refresh()
        }
    }

    /// Двойной клик по скрытой вкладке: возвращаем её в сетку и открываем сетку с этой вкладкой.
    private func revealInGrid(_ id: UUID) {
        guard let s = sessions.first(where: { $0.id == id }), !s.inGrid else { return }
        s.inGrid = true
        selectedID = id
        s.markSeen()
        gridMode = true
        returnToGrid = false
        refresh()
    }

    /// Клик по уведомлению.
    func focusSession(_ id: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        select(id)
    }

    func selectNext(_ delta: Int) {
        guard sessions.count > 1, let cur = sessions.firstIndex(where: { $0.id == selectedID }) else { return }
        let n = sessions.count
        select(sessions[((cur + delta) % n + n) % n].id)
    }

    func selectIndex(_ i: Int) {
        guard !sessions.isEmpty else { return }
        select(sessions[min(i, sessions.count - 1)].id)
    }

    // MARK: Перестановка

    private func normalizePins() {
        sessions = sessions.filter(\.isPinned) + sessions.filter { !$0.isPinned }
    }

    func move(_ id: UUID, toInsertionIndex idx: Int) {
        guard let from = sessions.firstIndex(where: { $0.id == id }) else { return }
        let s = sessions.remove(at: from)
        sessions.insert(s, at: min(sessions.count, idx > from ? idx - 1 : idx))
        normalizePins()
        refresh()
    }

    func move(_ id: UUID, onto target: UUID) {
        guard let from = sessions.firstIndex(where: { $0.id == id }),
              let to = sessions.firstIndex(where: { $0.id == target }) else { return }
        let s = sessions.remove(at: from)
        sessions.insert(s, at: to)
        normalizePins()
        refresh()
    }

    // MARK: Список закреплённых вкладок («стопка»)

    private func showPinnedMenu(from view: NSView) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Закреплённые вкладки", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for s in sessions where s.isPinned {
            let it = NSMenuItem(title: "", action: #selector(pickPinned(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s.id
            let title = NSMutableAttributedString(string: s.isSleeping ? "☾ " : "● ", attributes: [.foregroundColor: s.status.color])
            let name = s.folder ?? s.displayTitle
            title.append(NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]))
            let rest = s.displayTitle.hasPrefix(name + " · ") ? String(s.displayTitle.dropFirst(name.count + 3)) : ""
            if !rest.isEmpty {
                title.append(NSAttributedString(string: "  \(rest)", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            }
            if s.status != .idle {
                title.append(NSAttributedString(string: "  — \(s.status.label.lowercased())",
                                                attributes: [.foregroundColor: s.status.color, .font: NSFont.systemFont(ofSize: 11)]))
            }
            it.attributedTitle = title
            it.image = FolderBadge.image(for: name, size: 16)
            it.state = s.id == selectedID ? .on : .off
            menu.addItem(it)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    @objc private func pickPinned(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        select(id)
    }

    // MARK: Контекстное меню вкладки (закрепить / цвет / сетка)

    private func tabMenu(for id: UUID) -> NSMenu? {
        guard let s = sessions.first(where: { $0.id == id }) else { return nil }
        func item(_ title: String, _ sel: Selector, tag: TagColor? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.representedObject = MenuPayload(id, tag: tag)
            return i
        }
        let m = NSMenu()
        m.addItem(item(s.isPinned ? "Открепить" : "Закрепить", #selector(menuPin(_:))))
        if s.isSleeping {
            m.addItem(item("Разбудить", #selector(menuWake(_:))))
        } else if s.isPinned && s.id != selectedID {
            m.addItem(item("Отправить в архив сейчас", #selector(menuHibernate(_:))))
        }

        let colors = NSMenu()
        for c in TagColor.allCases {
            let i = item(c.title, #selector(menuTag(_:)), tag: c)
            i.image = c.swatch
            i.state = s.tag == c ? .on : .off
            colors.addItem(i)
        }
        colors.addItem(.separator())
        let none = item("Без цвета", #selector(menuTag(_:)))
        none.state = s.tag == nil ? .on : .off
        colors.addItem(none)
        let ci = NSMenuItem(title: "Цвет метки", action: nil, keyEquivalent: "")
        ci.submenu = colors
        m.addItem(ci)

        m.addItem(item(s.inGrid ? "Скрыть из сетки" : "Показывать в сетке", #selector(menuToggleGrid(_:))))
        m.addItem(.separator())
        m.addItem(item("Закрыть вкладку", #selector(menuClose(_:))))
        return m
    }

    private func payload(_ item: NSMenuItem) -> (TerminalSession, MenuPayload)? {
        guard let p = item.representedObject as? MenuPayload,
              let s = sessions.first(where: { $0.id == p.id }) else { return nil }
        return (s, p)
    }

    @objc private func menuPin(_ item: NSMenuItem) {
        guard let (s, _) = payload(item) else { return }
        s.isPinned.toggle()
        normalizePins()
        refresh()
    }
    @objc private func menuWake(_ item: NSMenuItem) {
        guard let (s, _) = payload(item) else { return }
        s.wake()
        refresh()
    }
    @objc private func menuHibernate(_ item: NSMenuItem) {
        guard let (s, _) = payload(item), s.isPinned, s.id != selectedID else { return }
        s.hibernate()
        refresh()
    }
    @objc private func menuTag(_ item: NSMenuItem) {
        guard let (s, p) = payload(item) else { return }
        s.tag = p.tag
        if let cwd = s.cwd { Settings.setTag(p.tag, forFolder: cwd) }   // запоминаем за папкой
        reloadTabBar()
        grid.update(sessions: sessions)
        saveState()
    }
    @objc private func menuToggleGrid(_ item: NSMenuItem) {
        guard let (s, _) = payload(item) else { return }
        setInGrid(s.id, !s.inGrid)
    }
    @objc private func menuClose(_ item: NSMenuItem) {
        guard let (s, _) = payload(item) else { return }
        requestClose(s.id)
    }

    // MARK: Сетка

    func toggleGrid() { setGrid(!gridMode) }

    func setGrid(_ on: Bool) {
        gridMode = on
        returnToGrid = false
        refresh()
    }

    private func setInGrid(_ id: UUID, _ value: Bool) {
        sessions.first { $0.id == id }?.inGrid = value
        refresh()
    }

    private func showGridFilterMenu(from view: NSView) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Вкладки в сетке", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for s in sessions {
            let it = NSMenuItem(title: s.displayTitle, action: #selector(toggleInGrid(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s.id
            it.state = s.inGrid ? .on : .off
            menu.addItem(it)
        }
        menu.addItem(.separator())
        let all = NSMenuItem(title: "Показать все", action: #selector(showAllInGrid), keyEquivalent: "")
        all.target = self
        let none = NSMenuItem(title: "Скрыть все", action: #selector(hideAllInGrid), keyEquivalent: "")
        none.target = self
        menu.addItem(all)
        menu.addItem(none)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    @objc private func toggleInGrid(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID, let s = sessions.first(where: { $0.id == id }) else { return }
        s.inGrid.toggle()
        refresh()
    }
    @objc private func showAllInGrid() { sessions.forEach { $0.inGrid = true }; refresh() }
    @objc private func hideAllInGrid() { sessions.forEach { $0.inGrid = false }; refresh() }

    /// Вернуть всем окнам в сетке одинаковый размер.
    func resetGridLayout() {
        grid.resetLayout()
        saveState()
    }

    // MARK: Внешний вид и шрифт


    private func layoutRoot() {
        guard let root = window?.contentView else { return }
        let h = TabBarView.height
        tabBar.frame = NSRect(x: 0, y: root.bounds.height - h, width: root.bounds.width, height: h)
        content.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: root.bounds.height - h)
    }


    private var appliedFontSize = Settings.fontSize

    private func applyAppearance() {
        layoutRoot()
        tabBar.needsLayout = true
        // Шрифт переприменяем только если он реально изменился (а не на каждый пиксель перетаскивания края вкладки).
        if Settings.fontSize != appliedFontSize {
            appliedFontSize = Settings.fontSize
            sessions.forEach { $0.applyFont() }   // у вкладок со своим размером он сохраняется
        }
    }

    /// ⌘+ / ⌘− / ⌘0 меняют шрифт только выбранной вкладки.
    func zoom(_ delta: CGFloat?) {
        guard let s = selected else { return }
        if let delta {
            s.fontSize = max(8, min(36, (s.fontSize ?? Settings.fontSize) + delta))
        } else {
            s.fontSize = nil
        }
        s.applyFont()
        saveState()
    }

    func clearScreen() {
        selected?.view.process.send(data: [0x0c][...])  // ^L
    }

    // MARK: Питомцы и производительность

    func petFrameRateChanged() { catView.applyFrameRate() }
    func callPetsToPlay() { catView.callToPlay() }
    func applyMetal() { sessions.forEach { try? $0.view.setUseMetal(Settings.useMetal) } }

    // MARK: Кот

    func layoutCat() {
        guard let w = window, let cv = w.contentView, let fv = cv.superview else { return }
        let th = fv.bounds.height - cv.frame.maxY          // высота строки заголовка
        let hideDecor = th < 12 || w.styleMask.contains(.fullScreen)
        catView.leftLimit = 92                                   // правее кнопок окна
        catView.frame = NSRect(x: 0, y: fv.bounds.height - th, width: fv.bounds.width, height: max(0, th))
        catView.isHidden = !Settings.catEnabled || hideDecor
    }

    private func updateCatMood() {
        let lim = LimitsStore.shared
        let tired = (lim.five?.percent ?? 0) >= 85 || (lim.week?.percent ?? 0) >= 90
        if sessions.contains(where: { $0.status == .waiting }) { catView.mood = .alert }
        else if sessions.contains(where: { $0.status == .working }) { catView.mood = .play }
        else if tired { catView.mood = .sad }
        else { catView.mood = .sleep }
    }

    // MARK: Уведомления и бейдж

    private func handle(_ ev: TerminalSession.Event, _ id: UUID) {
        if ev == .finished { catView.celebrate() }
        guard Settings.notifications, let s = sessions.first(where: { $0.id == id }) else { return }
        let focused = NSApp.isActive && window?.isKeyWindow == true && selectedID == id
        guard !focused else { return }
        switch ev {
        case .finished:   Notifier.shared.post(tab: id, title: s.displayTitle, body: "Задача завершена")
        case .needsInput: Notifier.shared.post(tab: id, title: s.displayTitle, body: "Ждёт вашего ответа")
        }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    private func updateBadge() {
        let n = sessions.filter { $0.status == .done || $0.status == .waiting }.count
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
    }

    // MARK: Лимиты

    private func updateLimits(force: Bool = false) {
        let store = LimitsStore.shared
        let changed = store.refresh()
        let connected = store.isConnected
        // Виджет лимитов нужен, только если пользуются Claude Code (у друга без Claude он скрыт).
        let relevant = Agents.defaultID == "claude" || connected || sessions.contains { $0.agentID == "claude" }
        if tabBar.limits.isRelevant != relevant { tabBar.limits.isRelevant = relevant }
        guard changed || force || tabBar.limits.connected != connected else { return }
        tabBar.limits.connected = connected
        tabBar.limits.five = store.five
        tabBar.limits.week = store.week
        tabBar.limits.updatedAt = store.updatedAt
    }

    func connectLimits() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Показывать лимиты Claude?"
        alert.informativeText = """
        Claude Code умеет передавать данные о лимитах (5 часов и неделя) и о текущей модели в statusLine-скрипт. \
        Terminalus добавит в ~/.claude/settings.json строку statusLine со скриптом \
        «\(LimitsStore.scriptURL.path)», который просто сохраняет эти данные в файлы для приложения.

        Копия текущего файла настроек будет сохранена как settings.json.terminalus-backup. \
        Работает для любых сеансов claude. Запущенные сеансы подхватят настройку после перезапуска.
        """
        alert.addButton(withTitle: "Подключить")
        alert.addButton(withTitle: "Отмена")
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn else { return }
            do {
                try LimitsStore.shared.connect()
                MainActor.assumeIsolated { self?.updateLimits(force: true) }
            } catch {
                let e = NSAlert(error: error)
                e.beginSheetModal(for: window)
            }
        }
    }

    // MARK: Обновление

    private func reloadTabBar() {
        tabBar.reload(sessions: sessions, selected: selectedID, gridMode: gridMode, returnToGrid: returnToGrid)
    }

    private func tick() {
        updateLimits()
        var changed = false
        let active = NSApp.isActive
        for s in sessions where s.tick(isSelected: s.id == selectedID && active) { changed = true }
        if Settings.hibernate {
            for s in sessions where s.canHibernate(minutes: Settings.hibernateMinutes, isSelected: s.id == selectedID) {
                s.hibernate()
                changed = true
            }
        }
        updateCatMood()
        guard changed else { return }
        reloadTabBar()
        grid.update(sessions: sessions)
        updateBadge()
        saveState()
    }

    private func refresh() {
        reloadTabBar()
        guard let current = selected else { return }

        if gridMode {
            content.subviews.forEach { if $0 !== grid { $0.removeFromSuperview() } }
            if grid.superview == nil {
                grid.frame = content.bounds
                content.addSubview(grid)
            }
            grid.reload(sessions: sessions.filter(\.inGrid), selected: selectedID)
        } else {
            grid.removeFromSuperview()
            content.subviews.forEach { $0.removeFromSuperview() }
            let v = current.view
            v.autoresizingMask = [.width, .height]
            v.frame = content.bounds.insetBy(dx: 8, dy: 6)
            content.addSubview(v)
        }
        if current.view.window != nil { window?.makeFirstResponder(current.view) }
        updateBadge()
        saveState()
    }

    func windowWillClose(_ notification: Notification) {
        flushState()
        timer?.invalidate()
        sessions.forEach { $0.close() }
        sessions.removeAll()
    }

    func windowDidEnterFullScreen(_ notification: Notification) { tabBar.needsLayout = true; layoutCat() }
    func windowDidExitFullScreen(_ notification: Notification) { tabBar.needsLayout = true; layoutCat() }
}
