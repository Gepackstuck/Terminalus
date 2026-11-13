import AppKit

enum Theme {
    static let terminalBG = NSColor(srgbRed: 0.105, green: 0.110, blue: 0.125, alpha: 1)
    static let terminalFG = NSColor(srgbRed: 0.85, green: 0.86, blue: 0.88, alpha: 1)
    static let barBG = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.09, alpha: 1)
    static let accent = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)   // claude-ish orange
    static let dragType = NSPasteboard.PasteboardType("com.terminalus.session-id")
}
