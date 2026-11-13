import AppKit

/// Окно «Шрифт»: размер шрифта по умолчанию и сброс.
@MainActor
final class AppearanceWindowController: NSWindowController {
    static let shared = AppearanceWindowController()

    private var sliders: [NSSlider] = []
    private var valueLabels: [NSTextField] = []

    private struct Row {
        let title: String, min: Double, max: Double
        let get: () -> CGFloat
        let set: (CGFloat) -> Void
    }
    private let rows: [Row] = [
        Row(title: "Шрифт по умолчанию", min: 8, max: 36, get: { Settings.fontSize }, set: { Settings.fontSize = $0 }),
    ]

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Шрифт"
        w.isReleasedWhenClosed = false
        super.init(window: w)

        let grid = NSGridView()
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        for (i, r) in rows.enumerated() {
            let name = NSTextField(labelWithString: r.title)
            let slider = NSSlider(value: Double(r.get()), minValue: r.min, maxValue: r.max,
                                  target: self, action: #selector(changed(_:)))
            slider.tag = i
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
            let value = NSTextField(labelWithString: "")
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            value.widthAnchor.constraint(equalToConstant: 40).isActive = true
            sliders.append(slider)
            valueLabels.append(value)
            grid.addRow(with: [name, slider, value])
        }
        let reset = NSButton(title: "Сбросить по умолчанию", target: self, action: #selector(resetDefaults))
        reset.bezelStyle = .rounded

        let stack = NSStackView(views: [grid, reset])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        syncLabels()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        syncFromSettings()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ s: NSSlider) {
        rows[s.tag].set(CGFloat(s.doubleValue.rounded()))
        syncLabels()
    }

    @objc private func resetDefaults() {
        Settings.resetAppearance()
        syncFromSettings()
    }

    private func syncFromSettings() {
        for (i, r) in rows.enumerated() { sliders[i].doubleValue = Double(r.get()) }
        syncLabels()
    }

    private func syncLabels() {
        for (i, r) in rows.enumerated() { valueLabels[i].stringValue = "\(Int(r.get()))" }
    }
}
