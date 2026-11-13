// Демо-картинки для README: настоящие вьюхи приложения с вымышленными данными (проекты, текст агентов, лимиты).
// Запуск: ./scripts/make_screenshots.sh   (сначала один раз ./build.sh — нужна собранная библиотека SwiftTerm)
import AppKit
import SwiftTerm

let E = "\u{1b}"
func c(_ n: Int, _ s: String) -> String { "\(E)[38;5;\(n)m\(s)\(E)[0m" }
func bold(_ s: String) -> String { "\(E)[1m\(s)\(E)[0m" }
func dim(_ s: String) -> String { "\(E)[2m\(s)\(E)[0m" }
func green(_ s: String) -> String { c(78, s) }
func red(_ s: String) -> String { c(203, s) }

struct Demo {
    let folder: String
    let agent: String?
    let title: String
    let status: SessionStatus
    let model: String?
    let context: Int?
    let pinned: Bool
    let screen: [String]
}

func claudeHeader(_ f: String, _ model: String) -> [String] {
    ["\(c(209, "✻")) \(bold("Claude Code"))  \(dim("· " + model))", dim("  ~/projects/\(f)"), ""]
}

let demos: [Demo] = [
    Demo(folder: "shop-front", agent: "claude", title: "Корзина", status: .working, model: "Opus 5.5", context: 34, pinned: true,
         screen: claudeHeader("shop-front", "Opus 5.5") + [
            "\(dim(">")) Добавь корзину и посчитай итоговую сумму со скидкой", "",
            "\(c(245, "●")) Читаю \(bold("src/cart/Cart.tsx"))", "\(c(245, "●")) Читаю \(bold("src/cart/pricing.ts"))", "",
            "\(c(245, "●")) Редактирую \(bold("src/cart/total.ts"))", "  \(green("+ export const total = (items, promo) =>"))", "  \(green("+   discount(sum(items), promo))"))",
            "  \(red("- return sum(items)"))", "", "\(c(209, "✻")) \(dim("Думаю… (14s · esc to interrupt)"))"]),
    Demo(folder: "api-gateway", agent: "codex", title: "Пагинация", status: .idle, model: nil, context: nil, pinned: true,
         screen: ["\(bold("▌ Codex"))", dim("  ~/projects/api-gateway"), "",
                  "\(bold("▌")) Реализуй пагинацию списка заказов", "",
                  "• Добавляю параметры \(bold("page")) и \(bold("limit"))", "• Обновляю контроллер \(bold("orders.ts"))", "",
                  "\(green("✓")) Готово: 3 файла изменено, тесты проходят", "", "\(bold("▌")) _"]),
    Demo(folder: "mobile-app", agent: "gemini", title: "Онбординг", status: .waiting, model: nil, context: nil, pinned: false,
         screen: ["\(c(75, "✦")) \(bold("Gemini CLI"))", dim("  ~/projects/mobile-app"), "",
                  "\(dim(">")) Сделай экран онбординга из трёх шагов", "", "\(c(245, "●")) Создаю \(bold("OnboardingScreen.swift"))", "",
                  "  Выполнить команду \(bold("xcodegen generate"))?", "", "  \(c(75, "❯ 1. Да"))", "    2. Нет, объяснить что изменить"]),
    Demo(folder: "data-pipeline", agent: "claude", title: "Миграция", status: .done, model: "Sonnet 5.5", context: 61, pinned: false,
         screen: claudeHeader("data-pipeline", "Sonnet 5.5") + [
            "\(dim(">")) Перенеси загрузку данных на потоковую обработку", "",
            "\(green("✓")) Обновлено 7 файлов, добавлены тесты", "\(green("✓")) \(bold("pytest")) — 42 passed", "", "\(dim(">")) _"]),
    Demo(folder: "docs-site", agent: nil, title: "", status: .working, model: nil, context: nil, pinned: false,
         screen: ["\(dim("~/projects/docs-site")) \(c(78, "$")) npm run dev", "", "  \(green("▲"))  ready on \(bold("http://localhost:3000"))", "  \(dim("compiled / in 412ms"))",
                  "  \(dim("compiled /guide in 96ms"))", "  \(dim("compiled /api in 88ms"))"]),
    Demo(folder: "ml-lab", agent: "claude", title: "Эксперименты", status: .idle, model: "Opus 5.5", context: 12, pinned: false,
         screen: claudeHeader("ml-lab", "Opus 5.5") + ["\(dim(">")) Сравни две модели на валидационной выборке", "",
                  "\(c(245, "●")) Запускаю \(bold("evaluate.py")) для обеих моделей", "", "  модель A  точность \(bold("0.913"))", "  модель B  точность \(bold("0.927"))", "",
                  "\(green("✓")) Модель B лучше на 1.4 п.п."]),
]

MainActor.assumeIsolated {
    let outDir = CommandLine.arguments[1]
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .darkAqua)
    app.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.icns")     // иконка в диалоге
    UserDefaults.standard.set(false, forKey: "useMetal")       // в памяти рисуем на CPU
    UserDefaults.standard.set(true, forKey: "petPixel")

    // вымышленные папки проектов
    let root = NSTemporaryDirectory() + "terminalus-demo/projects"
    for d in demos { try? FileManager.default.createDirectory(atPath: root + "/" + d.folder, withIntermediateDirectories: true) }

    var sessions: [TerminalSession] = []
    for (i, d) in demos.enumerated() {
        let s = TerminalSession(index: i + 1, mode: .shell, directory: root + "/" + d.folder)
        s.isPinned = d.pinned
        if !d.title.isEmpty { s.setTerminalTitle(source: s.view, title: d.title) }
        sessions.append(s)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))          // дать оболочкам стартовать, дальше глушим
    for s in sessions { s.view.terminate() }

    // окно как в приложении
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = Theme.barBG
    window.alphaValue = 0.01                // «показано», но не видно: SwiftTerm рисует по сигналу дисплея
    window.setFrameOrigin(NSPoint(x: 100, y: 100))
    window.orderFrontRegardless()
    let root0 = NSView(frame: window.contentView!.bounds)
    window.contentView = root0
    let tabBar = TabBarView(frame: NSRect(x: 0, y: root0.bounds.height - TabBarView.height, width: root0.bounds.width, height: TabBarView.height))
    let content = NSView(frame: NSRect(x: 0, y: 0, width: root0.bounds.width, height: root0.bounds.height - TabBarView.height))
    content.wantsLayer = true
    content.layer?.backgroundColor = Theme.terminalBG.cgColor
    root0.addSubview(content)
    root0.addSubview(tabBar)
    let grid = GridView(frame: content.bounds)
    let cat = CatView(frame: .zero)
    let frameView = root0.superview!
    let th = frameView.bounds.height - root0.frame.maxY
    cat.frame = NSRect(x: 0, y: frameView.bounds.height - th, width: frameView.bounds.width, height: th)
    cat.leftLimit = 92
    frameView.addSubview(cat)
    var virt = Date(); cat.clockOverride = virt
    @MainActor func advanceCat(_ sec: Double) { var t = 0.0; while t < sec { virt = virt.addingTimeInterval(1.0 / 15); cat.clockOverride = virt; cat.advance(1.0 / 15); t += 1.0 / 15 } }

    @MainActor func applyDemo() {
        for (s, d) in zip(sessions, demos) { s.applyDemo(status: d.status, model: d.model, context: d.context, agent: d.agent) }
    }
    @MainActor func feedScreens() {
        for (s, d) in zip(sessions, demos) {
            s.view.terminal.resetToInitialState()
            s.view.feed(text: "\r\n" + d.screen.joined(separator: "\r\n"))
        }
    }
    @MainActor func limits() {
        tabBar.limits.connected = true
        tabBar.limits.five = LimitsStore.Window(percent: 46, resetsAt: Date().addingTimeInterval(2.4 * 3600))
        tabBar.limits.week = LimitsStore.Window(percent: 23, resetsAt: Date().addingTimeInterval(3.2 * 86400))
        tabBar.limits.isRelevant = true
    }
    /// Снимок вью. Фон терминала — свойство слоя и при cacheDisplay в картинку не попадает,
    /// поэтому под области терминалов подкладываем его вручную.
    @MainActor func snap(_ v: NSView, _ name: String, terminals: [NSView] = [], hidden: [NSView] = [], background: NSColor? = nil) {
        v.layoutSubtreeIfNeeded()
        v.displayIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("нет rep для", name); return }
        // терминалы снимаем отдельно (см. ниже), поэтому в общем снимке прячем — иначе текст дублируется со сдвигом
        (terminals + hidden).forEach { $0.isHidden = true }
        v.cacheDisplay(in: v.bounds, to: rep)
        (terminals + hidden).forEach { $0.isHidden = false }
        let scale = CGFloat(rep.pixelsWide) / v.bounds.width
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: out) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        if let bg = background {
            bg.setFill()
            NSRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)).fill()
        }
        for t in terminals where t.window != nil {
            let r = v.convert(t.bounds, from: t)
            Theme.terminalBG.setFill()
            NSRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).fill()
        }
        // через NSImage с наложением: NSImageRep.draw(in:) заменяет пиксели, а не рисует поверх
        let layer = NSImage(size: NSSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
        layer.addRepresentation(rep)
        layer.draw(in: NSRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)),
                   from: .zero, operation: .sourceOver, fraction: 1)
        // каждый терминал снимаем сам по себе и накладываем поверх (в общем снимке слоёв ячеек текст может не попасть)
        for t in terminals where t.window != nil {
            guard let trep = t.bitmapImageRepForCachingDisplay(in: t.bounds) else { continue }
            t.cacheDisplay(in: t.bounds, to: trep)
            let r = v.convert(t.bounds, from: t)
            let timg = NSImage(size: NSSize(width: CGFloat(trep.pixelsWide), height: CGFloat(trep.pixelsHigh)))
            timg.addRepresentation(trep)
            timg.draw(in: NSRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outDir + "/" + name + ".png"))
        print("✓", name, out.pixelsWide, "×", out.pixelsHigh)
    }
    @MainActor func settle(_ t: Double = 1.2) {
        for s in sessions { s.view.needsDisplay = true }
        RunLoop.main.run(until: Date().addingTimeInterval(t))
    }

    // ---------- 1. сетка 3×2
    applyDemo()
    content.subviews.forEach { $0.removeFromSuperview() }
    grid.frame = content.bounds; grid.autoresizingMask = [.width, .height]
    content.addSubview(grid)
    grid.tree = GNode.auto(ids: sessions.map(\.id), cols: 3)
    grid.reload(sessions: sessions, selected: sessions[0].id)
    limits(); advanceCat(8)
    cat.mood = .play; advanceCat(6)
    tabBar.reload(sessions: sessions, selected: sessions[0].id, gridMode: true)
    settle(); feedScreens(); settle()
    snap(frameView, "grid", terminals: sessions.map(\.view))

    // ---------- 2. своя раскладка: одно высокое окно слева, остальные справа; предпросмотр перетаскивания
    sessions[5].inGrid = false
    let five = Array(sessions.prefix(5))
    grid.tree = GNode.split(.cols, [
        .leaf(five[0].id),
        .split(.rows, [.leaf(five[1].id), .split(.cols, [.leaf(five[2].id), .leaf(five[3].id)], [1, 1]), .leaf(five[4].id)], [1.1, 1.3, 0.9]),
    ], [0.46, 0.54])
    grid.reload(sessions: five, selected: five[2].id)
    tabBar.reload(sessions: sessions, selected: five[2].id, gridMode: true)
    settle(); feedScreens(); settle()
    // подсветка «сюда встанет окно» вокруг перетаскиваемого и приглушённое окно в руке
    if let moving = grid.subviews.compactMap({ $0 as? GridCellView }).first(where: { $0.sessionID == five[4].id }) {
        let ghost = NSView(frame: moving.frame)
        ghost.wantsLayer = true
        ghost.layer?.cornerRadius = 8
        ghost.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.16).cgColor
        ghost.layer?.borderColor = Theme.accent.cgColor
        ghost.layer?.borderWidth = 2
        grid.addSubview(ghost, positioned: .below, relativeTo: moving)
        moving.alphaValue = 0.0
    }
    snap(frameView, "grid-free-layout", terminals: five.filter { $0.id != five[4].id }.map(\.view), hidden: [five[4].view])
    grid.subviews.forEach { $0.alphaValue = 1 }
    sessions[5].inGrid = true

    // ---------- 3. обычный режим: стопка закреплённых + вкладки с агентами
    grid.removeFromSuperview()
    let chosen = sessions[3]
    chosen.view.removeFromSuperview()
    chosen.view.frame = content.bounds.insetBy(dx: 8, dy: 6)
    chosen.view.autoresizingMask = [.width, .height]
    content.addSubview(chosen.view)
    tabBar.reload(sessions: sessions, selected: chosen.id, gridMode: false)
    cat.mood = .alert; advanceCat(5)
    settle()
    chosen.view.terminal.resetToInitialState()
    chosen.view.feed(text: "\r\n" + demos[3].screen.joined(separator: "\r\n"))
    settle()
    snap(frameView, "tabs", terminals: [chosen.view])

    // ---------- 4. настройки агентов и вопрос при первом запуске
    Agents.defaultID = "claude"
    let agents = AgentsWindowController.shared
    agents.window?.appearance = NSAppearance(named: .darkAqua)
    if let v = agents.window?.contentView { snap(v, "agents-settings", background: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)) }
    let (alert, popup, _) = AgentsWindowController.makeFirstRunAlert()
    popup.selectItem(at: 0)
    alert.layout()
    alert.window.appearance = NSAppearance(named: .darkAqua)
    if let v = alert.window.contentView { snap(v, "first-run", background: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)) }

    for s in sessions { s.close() }
}
