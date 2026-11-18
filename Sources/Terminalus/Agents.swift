import AppKit
import Darwin

/// Профиль терминального агента (Claude Code, Codex, Gemini CLI, …).
struct AgentProfile: Codable, Equatable {
    var id: String
    var name: String
    /// Команда запуска.
    var command: String
    /// Команда продолжения сеанса; «{session}» заменяется идентификатором сеанса, если он известен.
    var resume: String
    /// Что запускать, если в `resume` есть «{session}», а идентификатор неизвестен.
    var resumeFallback: String
    /// Слова, по которым агент узнаётся среди запущенных процессов.
    var match: [String]
    var builtIn: Bool
    /// Есть ли у нас источник лимитов и модели (сейчас — только Claude Code).
    var hasLimits: Bool

    func resumeCommand(sessionID: String?) -> String {
        if resume.contains("{session}") {
            if let id = sessionID { return resume.replacingOccurrences(of: "{session}", with: id) }
            return resumeFallback.isEmpty ? command : resumeFallback
        }
        return resume.isEmpty ? command : resume
    }

    /// Первое слово команды — имя программы.
    var executable: String { command.split(separator: " ").first.map(String.init) ?? "" }
}

/// Настройки агентов и их автоматическое определение по процессу на переднем плане вкладки.
enum Agents {
    static let didChange = Notification.Name("TerminalusAgentsDidChange")

    static let presets: [AgentProfile] = [
        AgentProfile(id: "claude", name: "Claude Code", command: "claude",
                     resume: "claude --resume {session}", resumeFallback: "claude --continue",
                     match: ["claude"], builtIn: true, hasLimits: true),
        AgentProfile(id: "codex", name: "Codex", command: "codex",
                     resume: "codex resume --last", resumeFallback: "",
                     match: ["codex"], builtIn: true, hasLimits: false),
        AgentProfile(id: "gemini", name: "Gemini CLI", command: "gemini",
                     resume: "gemini --resume", resumeFallback: "",
                     match: ["gemini"], builtIn: true, hasLimits: false),
        AgentProfile(id: "opencode", name: "opencode", command: "opencode",
                     resume: "opencode --continue", resumeFallback: "",
                     match: ["opencode"], builtIn: true, hasLimits: false),
        AgentProfile(id: "qwen", name: "Qwen (Ollama)", command: "ollama run qwen3:30b",
                     resume: "ollama run qwen3:30b", resumeFallback: "",
                     match: ["ollama"], builtIn: true, hasLimits: false),
        AgentProfile(id: "aider", name: "Aider", command: "aider",
                     resume: "aider --restore-chat-history", resumeFallback: "",
                     match: ["aider"], builtIn: true, hasLimits: false),
    ]

    // MARK: Хранение

    private static let key = "agents.v1"
    private static var cache: [AgentProfile]?

    static var all: [AgentProfile] {
        get {
            if let c = cache { return c }
            var list: [AgentProfile] = []
            if let d = UserDefaults.standard.data(forKey: key),
               let l = try? JSONDecoder().decode([AgentProfile].self, from: d) { list = l }
            for p in presets where !list.contains(where: { $0.id == p.id }) { list.append(p) }   // новые пресеты подхватываются сами
            cache = list
            return list
        }
        set {
            cache = newValue
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func profile(_ id: String?) -> AgentProfile? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Агент по умолчанию (⇧⌘T). Пусто — «просто терминал».
    static var defaultID: String {
        get { UserDefaults.standard.string(forKey: "defaultAgent") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "defaultAgent"); NotificationCenter.default.post(name: didChange, object: nil) }
    }
    static var defaultProfile: AgentProfile? { profile(defaultID.isEmpty ? nil : defaultID) }

    static var firstRunDone: Bool {
        get { UserDefaults.standard.bool(forKey: "agentFirstRunDone") }
        set { UserDefaults.standard.set(newValue, forKey: "agentFirstRunDone") }
    }

    static func resetToDefaults() { all = presets }

    // MARK: Установлен ли агент

    private static let searchDirs: [String] = {
        let h = NSHomeDirectory()
        return ["\(h)/.local/bin", "\(h)/.npm-global/bin", "\(h)/.bun/bin", "\(h)/.cargo/bin", "\(h)/go/bin",
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }()

    static func isInstalled(_ p: AgentProfile) -> Bool {
        let exe = p.executable
        guard !exe.isEmpty else { return false }
        if exe.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: exe) }
        return searchDirs.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + exe) }
    }

    // MARK: Определение агента по процессу

    /// Аргументы процесса (KERN_PROCARGS2).
    static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < size && buf[i] != 0 { i += 1 }        // путь к исполняемому файлу
        while i < size && buf[i] == 0 { i += 1 }        // выравнивание
        var args: [String] = []
        var cur: [UInt8] = []
        while i < size && args.count < argc {
            if buf[i] == 0 { args.append(String(decoding: cur, as: UTF8.self)); cur = [] } else { cur.append(buf[i]) }
            i += 1
        }
        return args
    }

    /// Какому агенту принадлежит процесс (по имени программы, скрипта или пути установки).
    static func match(pid: pid_t) -> AgentProfile? {
        guard pid > 0 else { return nil }
        var pathBuf = [CChar](repeating: 0, count: 4096)
        let execPath = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 ? String(cString: pathBuf).lowercased() : ""
        let args = arguments(of: pid).prefix(3).map { $0.lowercased() }
        for p in all {
            for kw in p.match.map({ $0.lowercased() }) where !kw.isEmpty {
                // установщики кладут бинарник в «…/<имя>/versions/<версия>»
                if execPath.contains("/\(kw)/versions/") { return p }
                for token in [execPath] + args {
                    let base = (token as NSString).lastPathComponent
                    if base == kw || base == kw + ".js" || base == kw + ".mjs" || base == kw + ".py" { return p }
                }
            }
        }
        return nil
    }
}
