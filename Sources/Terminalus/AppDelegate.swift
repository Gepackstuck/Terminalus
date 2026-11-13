import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
        Notifier.shared.setup()
        controller = MainWindowController()
        Notifier.shared.onOpen = { [weak controller] id in
            MainActor.assumeIsolated { controller?.focusSession(id) }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(forName: Agents.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self != nil { NSApp.mainMenu = self?.buildMenu() } }
        }
        DispatchQueue.main.async { [weak self] in
            AgentsWindowController.promptFirstRun(over: self?.controller.window)
            NSApp.mainMenu = self?.buildMenu()          // в заголовках пунктов — выбранный агент
        }
    }

    func applicationWillTerminate(_ notification: Notification) { controller?.flushState() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.window?.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: Actions (target = self, поэтому не зависят от responder chain)

    @objc func newTab() { controller.newSession() }
    @objc func newAgentTab() { controller.newSession(agent: Agents.defaultProfile) }
    @objc func newTabHere() { controller.newSession(inCurrentFolder: true) }
    @objc func newAgentTabHere() { controller.newSession(agent: Agents.defaultProfile, inCurrentFolder: true) }
    @objc func newTabWithAgent(_ sender: NSMenuItem) {
        controller.newSession(agent: Agents.profile(sender.representedObject as? String))
    }
    @objc func showAgents() { AgentsWindowController.shared.present() }
    @objc func closeTab() { controller.closeCurrent() }
    @objc func toggleGrid() { controller.toggleGrid() }
    @objc func nextTab() { controller.selectNext(1) }
    @objc func prevTab() { controller.selectNext(-1) }
    @objc func selectTab(_ sender: NSMenuItem) { controller.selectIndex(sender.tag == 9 ? Int.max : sender.tag - 1) }
    @objc func zoomIn() { controller.zoom(1) }
    @objc func zoomOut() { controller.zoom(-1) }
    @objc func zoomReset() { controller.zoom(nil) }
    @objc func clearScreen() { controller.clearScreen() }
    @objc func connectLimits() { controller.connectLimits() }
    @objc func toggleNotifications(_ sender: NSMenuItem) {
        Settings.notifications.toggle()
        sender.state = Settings.notifications ? .on : .off
    }
    @objc func toggleCat(_ sender: NSMenuItem) {
        Settings.catEnabled.toggle()
        sender.state = Settings.catEnabled ? .on : .off
        controller.layoutCat()
    }
    @objc func togglePetPixel(_ sender: NSMenuItem) {
        Settings.petPixel.toggle()
        sender.state = Settings.petPixel ? .on : .off
    }
    @objc func togglePetEconomy(_ sender: NSMenuItem) {
        Settings.petEconomy.toggle()
        sender.state = Settings.petEconomy ? .on : .off
        controller.petFrameRateChanged()
    }
    @objc func callPets() { controller.callPetsToPlay() }
    @objc func toggleHibernate(_ sender: NSMenuItem) {
        Settings.hibernate.toggle()
        sender.state = Settings.hibernate ? .on : .off
    }
    @objc func toggleMetal(_ sender: NSMenuItem) {
        Settings.useMetal.toggle()
        sender.state = Settings.useMetal ? .on : .off
        controller.applyMetal()
    }
    @objc func showAppearance() { AppearanceWindowController.shared.present() }
    @objc func resetAppearance() { Settings.resetAppearance() }
    @objc func resetGridLayout() { controller.resetGridLayout() }

    /// «О Terminalus» с историей версий (Resources/CHANGELOG.md).
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: Self.changelogText(),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Сделано вместе с Claude",
        ])
    }

    private static func changelogText() -> NSAttributedString {
        let out = NSMutableAttributedString()
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return NSAttributedString(string: "История версий недоступна")
        }
        let body = NSFont.systemFont(ofSize: 11)
        let head = NSFont.systemFont(ofSize: 12, weight: .bold)
        func add(_ s: String, _ f: NSFont, _ c: NSColor = .labelColor) {
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: f, .foregroundColor: c]))
        }
        add("История версий", NSFont.systemFont(ofSize: 13, weight: .bold))
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("# ") { continue }
            if line.hasPrefix("## ") { add("\n" + line.dropFirst(3), head) }
            else if line.hasPrefix("- ") { add("• " + line.dropFirst(2), body, .secondaryLabelColor) }
            else if !line.isEmpty { add(line, body) }
        }
        return out
    }

    private func agentTitle(_ base: String) -> String {
        Agents.defaultProfile.map { "\(base) (\($0.name))" } ?? base
    }

    // MARK: Menu

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                       _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title)
        items.forEach(m.addItem)
        let host = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        host.submenu = m
        return host
    }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        let arrowL = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let arrowR = String(UnicodeScalar(NSRightArrowFunctionKey)!)

        func toggle(_ title: String, _ sel: Selector, on: Bool) -> NSMenuItem {
            let i = item(title, sel, target: self)
            i.state = on ? .on : .off
            return i
        }

        main.addItem(submenu("Terminalus", [
            item("О Terminalus", #selector(showAbout), target: self),
            .separator(),
            item("Шрифт по умолчанию…", #selector(showAppearance), ",", target: self),
            item("Агенты…", #selector(showAgents), target: self),
            item("Показывать лимиты Claude…", #selector(connectLimits), target: self),
            .separator(),
            // отдельный раздел настроек питомцев
            submenu("Питомцы", [
                toggle("Показывать питомцев в заголовке", #selector(toggleCat(_:)), on: Settings.catEnabled),
                toggle("Пиксельный стиль", #selector(togglePetPixel(_:)), on: Settings.petPixel),
                toggle("Экономный режим (15 кадров в секунду)", #selector(togglePetEconomy(_:)), on: Settings.petEconomy),
                .separator(),
                item("Позвать Тян и Бэна поиграть", #selector(callPets), target: self),
            ]),
            toggle("Уведомления о задачах", #selector(toggleNotifications(_:)), on: Settings.notifications),
            .separator(),
            toggle("Архив: усыплять закреплённые вкладки (через \(Int(Settings.hibernateMinutes)) мин)", #selector(toggleHibernate(_:)), on: Settings.hibernate),
            toggle("Отрисовка терминалов на GPU (Metal)", #selector(toggleMetal(_:)), on: Settings.useMetal),
            .separator(),
            item("Скрыть Terminalus", #selector(NSApplication.hide(_:)), "h"),
            item("Скрыть остальные", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Выйти из Terminalus", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("Терминал", [
            item("Новая вкладка", #selector(newTab), "t", target: self),
            item(agentTitle("Новая вкладка с агентом"), #selector(newAgentTab), "t", [.command, .shift], target: self),
            submenu("Новая вкладка с…", Agents.all.map { p in
                let i = item(p.name + (Agents.isInstalled(p) ? "" : "  (не найден)"), #selector(newTabWithAgent(_:)), target: self)
                i.representedObject = p.id
                return i
            }),
            item("Новая вкладка в папке текущей", #selector(newTabHere), "t", [.command, .option], target: self),
            item(agentTitle("Новая вкладка с агентом в папке текущей"), #selector(newAgentTabHere), "t", [.command, .option, .shift], target: self),
            .separator(),
            item("Закрыть вкладку", #selector(closeTab), "w", target: self),
        ]))

        // Для Copy/Paste/Select All target = nil → ответит первый респондер (терминал).
        main.addItem(submenu("Правка", [
            item("Копировать", Selector(("copy:")), "c"),
            item("Вставить", Selector(("paste:")), "v"),
            item("Выделить всё", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Очистить экран", #selector(clearScreen), "k", target: self),
        ]))

        var viewItems: [NSMenuItem] = [
            item("Режим сетки", #selector(toggleGrid), "g", [.command, .shift], target: self),
            .separator(),
            item("Следующая вкладка", #selector(nextTab), "}", [.command], target: self),
            item("Предыдущая вкладка", #selector(prevTab), "{", [.command], target: self),
            item("Следующая вкладка", #selector(nextTab), arrowR, [.command, .option], target: self),
            item("Предыдущая вкладка", #selector(prevTab), arrowL, [.command, .option], target: self),
            item("Следующая вкладка", #selector(nextTab), "\t", [.control], target: self),
            item("Предыдущая вкладка", #selector(prevTab), "\t", [.control, .shift], target: self),
            .separator(),
        ]
        for n in 1...9 {
            let i = item(n == 9 ? "Последняя вкладка" : "Вкладка \(n)", #selector(selectTab(_:)), "\(n)", target: self)
            i.tag = n
            viewItems.append(i)
        }
        viewItems += [
            .separator(),
            item("Увеличить шрифт (эта вкладка)", #selector(zoomIn), "=", target: self),
            item("Увеличить шрифт (эта вкладка)", #selector(zoomIn), "+", target: self),
            item("Уменьшить шрифт (эта вкладка)", #selector(zoomOut), "-", target: self),
            item("Шрифт вкладки по умолчанию", #selector(zoomReset), "0", target: self),
            item("Сбросить размеры окон в сетке", #selector(resetGridLayout), target: self),
            .separator(),
            item("Полный экран", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]
        main.addItem(submenu("Вид", viewItems))

        main.addItem(submenu("Окно", [
            item("Свернуть", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Масштаб", #selector(NSWindow.performZoom(_:))),
        ]))
        return main
    }
}
