import AppKit
import SwiftTerm
import Darwin

enum LaunchMode {
    case shell
    case agent(String)         // запустить агента (id профиля)
    case agentResume(String)   // продолжить сеанс агента

    var agentID: String? {
        switch self {
        case .shell: return nil
        case .agent(let id), .agentResume(let id): return id
        }
    }
}

/// Терминальный view с macOS-шорткатами редактирования текста.
///
/// Стандартный TerminalView шлёт для ⌥←, ⌘← и т.п. xterm-последовательности, которые
/// readline/zsh/Claude Code не понимают. Здесь они переводятся в то, что понимает readline.
final class TerminalPaneView: LocalProcessTerminalView {
    var onFocus: (() -> Void)?
    /// Для определения статуса: время последнего ввода и последнего «настоящего» вывода
    /// (эхо набираемых символов не считается).
    private(set) var lastInput = Date.distantPast
    private(set) var lastActivity = Date.distantPast

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let now = Date()
        if now.timeIntervalSince(lastInput) > 0.7 { lastActivity = now }
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        lastInput = Date()
        super.send(source: source, data: data)
    }

    private func sendBytes(_ bytes: [UInt8]) {
        lastInput = Date()
        process.send(data: bytes[...])
    }

    /// ⌘V: если в буфере картинка (скриншот), а не текст — шлём ^V: так Claude Code забирает изображение из буфера.
    override func paste(_ sender: Any) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == nil, pb.canReadObject(forClasses: [NSImage.self], options: nil) {
            sendBytes([0x16])
            return
        }
        super.paste(sender)
    }

    // MARK: Drag & drop файлов/папок → путь в командной строке

    private func droppedText(_ info: NSDraggingInfo) -> String? {
        let pb = info.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map { Self.shellEscape($0.path) }.joined(separator: " ") + " "
        }
        return pb.string(forType: .string)
    }

    static func shellEscape(_ path: String) -> String {
        var out = ""
        for ch in path {
            if !(ch.isLetter || ch.isNumber || "/._-+,:@%~=".contains(ch)) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedText(sender) == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = droppedText(sender) else { return false }
        window?.makeFirstResponder(self)
        onFocus?()
        sendBytes(Array(text.utf8))
        return true
    }

    // MARK: macOS-шорткаты

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let ESC: UInt8 = 0x1b

        var out: [UInt8]?
        switch (event.keyCode, mods) {
        case (123, [.option]):  out = [ESC, UInt8(ascii: "b")]   // ⌥←  слово назад
        case (124, [.option]):  out = [ESC, UInt8(ascii: "f")]   // ⌥→  слово вперёд
        case (123, [.command]): out = [0x01]                      // ⌘←  начало строки (^A)
        case (124, [.command]): out = [0x05]                      // ⌘→  конец строки (^E)
        case (115, []):         out = [0x01]                      // Home
        case (119, []):         out = [0x05]                      // End
        case (51, [.option]):   out = [ESC, 0x7f]                 // ⌥⌫  слово назад
        case (51, [.command]):  out = [0x15]                      // ⌘⌫  до начала строки (^U)
        case (117, [.option]):  out = [ESC, UInt8(ascii: "d")]    // ⌥⌦  слово вперёд
        case (117, [.command]): out = [0x0b]                      // ⌘⌦  до конца строки (^K)
        case (36, [.shift]), (76, [.shift]): out = [ESC, 0x0d]    // ⇧↩  новая строка в Claude Code
        case (6, [.command]):   out = [0x1f]                      // ⌘Z  undo (^_)
        default: break
        }
        if let out {
            sendBytes(out)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class TerminalSession: LocalProcessTerminalViewDelegate {
    let id = UUID()
    let view: TerminalPaneView
    private let fallbackName: String

    private(set) var rawTitle: String?
    private(set) var cwd: String?
    private(set) var folder: String?
    private(set) var status: SessionStatus = .idle
    /// Сессия когда-либо запускала Claude (для восстановления через `claude --continue`).
    /// Агент, которого запускали в этой вкладке (определяется по процессу и запоминается).
    private(set) var agentID: String?
    private var lastForegroundPID: pid_t = 0
    var sawClaude: Bool { agentID == "claude" }
    var agentName: String? { Agents.profile(agentID)?.name }
    /// Показывать ли вкладку в режиме сетки.
    var inGrid = true
    var isPinned = false
    var tag: TagColor?
    /// Свой размер шрифта вкладки (nil — общий из настроек).
    var fontSize: CGFloat?
    private(set) var modelName: String?
    private(set) var contextPercent: Int?
    /// Идентификатор сеанса Claude (из statusLine) — чтобы будить вкладку точным `claude --resume`.
    private(set) var claudeSessionID: String?
    /// Вкладка в архиве: процессы остановлены, вкладка и её бейдж остаются.
    private(set) var isSleeping = false
    private var selectedAt = Date()

    enum Event { case finished, needsInput }
    var onEvent: ((Event) -> Void)?
    var onExit: (() -> Void)?
    var onFocus: (() -> Void)?

    init(index: Int, mode: LaunchMode, directory: String?, inGrid: Bool = true,
         pinned: Bool = false, tag: TagColor? = nil, fontSize: CGFloat? = nil,
         sleeping: Bool = false, claudeSession: String? = nil) {
        fallbackName = "Terminal \(index)"
        self.inGrid = inGrid
        self.isPinned = pinned
        self.fontSize = fontSize
        agentID = mode.agentID
        view = TerminalPaneView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize ?? Settings.fontSize, weight: .regular)
        view.nativeBackgroundColor = Theme.terminalBG
        view.nativeForegroundColor = Theme.terminalFG
        view.optionAsMetaKey = true
        // Metal-рендерер: отрисовка на GPU вместо CoreGraphics — заметно плавнее скролл и вывод.
        if Settings.useMetal {
            try? view.setUseMetal(true)
        }
        view.onFocus = { [weak self] in self?.onFocus?() }

        var dir = directory ?? NSHomeDirectory()
        if !FileManager.default.fileExists(atPath: dir) { dir = NSHomeDirectory() }
        cwd = dir
        folder = Self.folderName(dir)
        self.tag = tag ?? Settings.tag(forFolder: dir)
        claudeSessionID = claudeSession
        if sleeping {
            // Закреплённая вкладка при восстановлении: процессы не запускаем, пока на неё не нажмут.
            isSleeping = true
            status = .sleeping
            showSleepNote()
        } else {
            launch(mode: mode, resumeID: claudeSession, directory: dir)
        }
    }

    private func launch(mode: LaunchMode, resumeID: String?, directory dir: String) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var args = ["-l"]
        switch mode {
        case .shell: break
        case .agent(let id):
            if let p = Agents.profile(id), !p.command.isEmpty { args += ["-i", "-c", "\(p.command); exec '\(shell)' -l"] }
        case .agentResume(let id):
            if let p = Agents.profile(id), !p.command.isEmpty {
                args += ["-i", "-c", "\(p.resumeCommand(sessionID: resumeID)); exec '\(shell)' -l"]
            }
        }
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        env.append("TERM_PROGRAM=Terminalus")
        env.append("TERMINALUS_TAB_ID=\(id.uuidString)")   // чтобы statusLine-скрипт знал, из какой вкладки данные
        view.startProcess(executable: shell, args: args, environment: env,
                          execName: "-" + (shell as NSString).lastPathComponent,
                          currentDirectory: dir)
    }

    // MARK: Архив (сон закреплённых вкладок)

    private func showSleepNote() {
        view.feed(text: "\r\n  \u{1b}[2m☾ Вкладка в архиве — нажмите на неё, чтобы разбудить\u{1b}[0m\r\n")
    }

    /// Процесс на переднем плане — оболочка или известный агент (а не dev-сервер, npm и т. п.): тогда можно спать без потерь.
    private var foregroundIsShellOrAgent: Bool {
        let fg = tcgetpgrp(view.process.childfd)
        guard fg > 0 else { return false }
        if fg == view.process.shellPid { return true }
        return Agents.match(pid: fg) != nil
    }

    func canHibernate(minutes: Double, isSelected: Bool) -> Bool {
        guard isPinned, !isSleeping, !isSelected, status == .idle, foregroundIsShellOrAgent else { return false }
        let lastTouch = max(view.lastActivity, view.lastInput, selectedAt)
        return Date().timeIntervalSince(lastTouch) >= minutes * 60
    }

    /// Завершает процессы вкладки (закрытие pty завершает и claude), освобождает память буфера.
    func hibernate() {
        guard !isSleeping else { return }
        isSleeping = true
        status = .sleeping
        let pid = view.process.shellPid
        view.terminate()
        // terminate() отменяет слежение за процессом — забираем завершившийся шелл сами, чтобы не оставлять зомби
        if pid > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { var st: Int32 = 0; waitpid(pid, &st, WNOHANG) }
        }
        view.terminal.resetToInitialState()
        showSleepNote()
        view.needsDisplay = true
    }

    /// Поднимает вкладку: шелл в той же папке и `claude --resume <id>` (или --continue).
    func wake() {
        guard isSleeping else { return }
        isSleeping = false
        status = .idle
        selectedAt = Date()
        lastWorking = .distantPast
        view.terminal.resetToInitialState()
        view.feed(text: "\r\n  \u{1b}[2m☾ Поднимаю вкладку из архива…\u{1b}[0m\r\n")
        var dir = cwd ?? NSHomeDirectory()
        if !FileManager.default.fileExists(atPath: dir) { dir = NSHomeDirectory() }
        launch(mode: agentID.map { LaunchMode.agentResume($0) } ?? LaunchMode.shell, resumeID: claudeSessionID, directory: dir)
    }

    func touch() { selectedAt = Date() }

    /// Для демонстрационных скриншотов: задать вымышленное состояние.
    func applyDemo(status: SessionStatus, model: String?, context: Int?, agent: String?) {
        self.status = status
        modelName = model
        contextPercent = context
        agentID = agent
    }

    func close() {
        onExit = nil
        onEvent = nil
        let pid = view.process.shellPid
        if !isSleeping { view.terminate() }
        if pid > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { var st: Int32 = 0; waitpid(pid, &st, WNOHANG) } }
        try? FileManager.default.removeItem(at: tabFileURL)
    }

    // MARK: Шрифт

    func applyFont() {
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize ?? Settings.fontSize, weight: .regular)
    }

    // MARK: Модель (из statusLine-данных этой вкладки)

    private var tabFileURL: URL { LimitsStore.tabsDir.appendingPathComponent("\(id.uuidString).json") }
    private var modelMTime: Date?

    private func refreshModel() {
        guard let m = (try? FileManager.default.attributesOfItem(atPath: tabFileURL.path))?[.modificationDate] as? Date,
              m != modelMTime else { return }
        modelMTime = m
        guard let data = try? Data(contentsOf: tabFileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let sid = obj["session_id"] as? String, !sid.isEmpty { claudeSessionID = sid }
        if let model = obj["model"] as? [String: Any], let n = model["display_name"] as? String { modelName = n }
        if let cw = obj["context_window"] as? [String: Any],
           let p = (cw["used_percentage"] as? NSNumber)?.intValue { contextPercent = p }
    }

    /// Подпись для подсказки.
    var detailText: String {
        var t = displayTitle
        if let a = agentName { t += "\nАгент: \(a)" }
        if let m = modelName { t += "\nМодель: \(m)" }
        if let c = contextPercent { t += "\nКонтекст: \(c)%" }
        return t
    }

    // MARK: Название и статус

    /// Claude Code сам ставит в начало заголовка символ-индикатор: спиннер (⠂ ⠐ ◐ ◑ ◒ ◓ …)
    /// пока работает, и ✳ в простое. Мы рисуем свой индикатор, поэтому символ вырезаем.
    private static func isSpinnerGlyph(_ s: Unicode.Scalar) -> Bool {
        (0x2800...0x28FF).contains(s.value) ||   // braille
        (0x25A0...0x25FF).contains(s.value)      // геометрические фигуры, в т.ч. ◐◑◒◓
    }
    private static func isDecoration(_ s: Unicode.Scalar) -> Bool {
        isSpinnerGlyph(s) || (0x2700...0x27BF).contains(s.value) || "*·•●○ ".unicodeScalars.contains(s)
    }

    /// «<папка> · <заголовок терминала>»
    var displayTitle: String {
        var clean = Substring(rawTitle ?? "")
        while let f = clean.unicodeScalars.first, Self.isDecoration(f) {
            clean = clean.dropFirst()
        }
        let base = clean.trimmingCharacters(in: .whitespaces)
        switch (folder, base.isEmpty ? nil : base) {
        case let (f?, b?) where b != f: return "\(f) · \(b)"
        case let (f?, _): return f
        case let (nil, b?): return b
        default: return fallbackName
        }
    }

    private static func folderName(_ path: String) -> String {
        path == NSHomeDirectory() ? "~" : (path as NSString).lastPathComponent
    }

    private static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// В шелле сейчас выполняется команда (claude, npm, ssh …), а не просто висит приглашение.
    var hasRunningCommand: Bool {
        let fg = tcgetpgrp(view.process.childfd)
        return fg > 0 && fg != view.process.shellPid
    }

    private var lastWorking = Date.distantPast

    func markSeen() { if status == .done { status = .idle } }

    private var workingSince = Date.distantPast

    /// Claude ждёт ответа: на экране запрос разрешения / выбор варианта.
    private func screenWantsInput() -> Bool {
        guard let t = view.terminal else { return false }
        var text = ""
        for r in 0..<t.rows {
            if let l = t.getLine(row: r) { text += l.translateToString(trimRight: true) + "\n" }
        }
        if text.contains("Do you want to proceed") || text.contains("Would you like to proceed") { return true }
        return text.contains("1. Yes") && text.localizedCaseInsensitiveContains("esc")
    }

    /// Раз в секунду: обновляет папку, модель и статус. Возвращает true, если что-то изменилось.
    func tick(isSelected: Bool) -> Bool {
        if isSleeping { return false }
        let before = (displayTitle, status, cwd, modelName, contextPercent, agentID)
        refreshModel()

        let pid = view.process.shellPid
        if pid > 0, let d = Self.cwd(of: pid), d != cwd {
            cwd = d
            folder = Self.folderName(d)
        }

        let commandRunning = hasRunningCommand            // в шелле запущена команда (агент, npm …)
        if commandRunning {
            // Агент, запущенный вручную, подхватывается и запоминается за вкладкой.
            let fg = tcgetpgrp(view.process.childfd)
            if fg != lastForegroundPID {
                lastForegroundPID = fg
                if let p = Agents.match(pid: fg) { agentID = p.id }
            }
        } else {
            lastForegroundPID = 0
        }
        let spinner = rawTitle?.unicodeScalars.first.map(Self.isSpinnerGlyph) ?? false
        let active = Date().timeIntervalSince(view.lastActivity) < 1.5
        if spinner || (commandRunning && active) { lastWorking = Date() }
        let working = Date().timeIntervalSince(lastWorking) < 2.0

        let prev = status
        if working {
            if status != .working { workingSince = Date() }
            status = .working
        } else if commandRunning && screenWantsInput() {
            status = .waiting
        } else if status == .working {
            status = isSelected ? .idle : .done
        } else if status == .waiting {
            status = .idle
        } else if status == .done && isSelected {
            status = .idle
        }

        if prev != status {
            if status == .waiting {
                onEvent?(.needsInput)
            } else if prev == .working, Date().timeIntervalSince(workingSince) >= 4 {
                onEvent?(.finished)
            }
        }
        return before != (displayTitle, status, cwd, modelName, contextPercent, agentID)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        rawTitle = title
        if title.localizedCaseInsensitiveContains("claude"), agentID == nil { agentID = "claude" }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if isSleeping { return }
        onExit?()
    }
}
