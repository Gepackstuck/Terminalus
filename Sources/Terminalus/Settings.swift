import AppKit

/// Настройки внешнего вида (UserDefaults). Любое изменение шлёт `Settings.didChange`.
enum Settings {
    static let didChange = Notification.Name("TerminalusSettingsDidChange")

    static let defaultFontSize: CGFloat = 13

    private static func get(_ key: String, _ def: CGFloat) -> CGFloat {
        (UserDefaults.standard.object(forKey: key) as? Double).map { CGFloat($0) } ?? def
    }
    private static func set(_ key: String, _ v: CGFloat) {
        UserDefaults.standard.set(Double(v), forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static var fontSize: CGFloat {
        get { get("fontSize", defaultFontSize) }
        set { set("fontSize", max(8, min(36, newValue))) }
    }

    static func resetAppearance() {
        ["fontSize", "tabHeight", "tabWidth"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Уведомления и метки папок

    static var notifications: Bool {
        get { UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifications") }
    }

    /// Цвет запоминается за папкой: новая вкладка в этой папке получает тот же цвет.
    static func tag(forFolder path: String) -> TagColor? {
        (UserDefaults.standard.dictionary(forKey: "folderTags") as? [String: String])?[path]
            .flatMap(TagColor.init(rawValue:))
    }
    static func setTag(_ tag: TagColor?, forFolder path: String) {
        var d = (UserDefaults.standard.dictionary(forKey: "folderTags") as? [String: String]) ?? [:]
        d[path] = tag?.rawValue
        UserDefaults.standard.set(d, forKey: "folderTags")
    }

    /// Кот в строке заголовка.
    static var catEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "catEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "catEnabled") }
    }

    /// Папка для новых вкладок (общие задачи, не привязанные к проекту).
    static var defaultFolder: String {
        get { UserDefaults.standard.string(forKey: "defaultFolder") ?? NSHomeDirectory() + "/Documents/vibecode" }
        set { UserDefaults.standard.set(newValue, forKey: "defaultFolder") }
    }

    /// Питомцы в пиксельном стиле (иначе — векторные).
    static var petPixel: Bool {
        get { UserDefaults.standard.object(forKey: "petPixel") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "petPixel") }
    }

    /// Питомцы в экономном режиме: 15 кадров в секунду вместо 30.
    static var petEconomy: Bool {
        get { UserDefaults.standard.object(forKey: "petEconomy") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "petEconomy") }
    }

    /// «Архив»: закреплённые вкладки засыпают после простоя (процессы завершаются, вкладка остаётся).
    static var hibernate: Bool {
        get { UserDefaults.standard.object(forKey: "hibernate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hibernate") }
    }
    static var hibernateMinutes: Double {
        get { UserDefaults.standard.object(forKey: "hibernateMinutes") as? Double ?? 40 }
        set { UserDefaults.standard.set(newValue, forKey: "hibernateMinutes") }
    }

    /// Отрисовка терминалов на GPU (Metal).
    static var useMetal: Bool {
        get { UserDefaults.standard.object(forKey: "useMetal") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useMetal") }
    }

    /// Панель плана агента справа.
    static var planPanel: Bool {
        get { UserDefaults.standard.bool(forKey: "planPanel") }
        set { UserDefaults.standard.set(newValue, forKey: "planPanel") }
    }
}
