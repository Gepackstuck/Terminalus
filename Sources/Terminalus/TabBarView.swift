import AppKit

private func snapshot(of view: NSView) -> NSImage {
    let img = NSImage(size: view.bounds.size)
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        img.addRepresentation(rep)
    }
    return img
}

func symbolButton(_ name: String, tip: String, target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton()
    b.image = NSImage(systemSymbolName: name, accessibilityDescription: tip)
    b.imagePosition = .imageOnly
    b.isBordered = false
    b.contentTintColor = .secondaryLabelColor
    b.toolTip = tip
    b.target = target
    b.action = action
    return b
}

// MARK: - Одна вкладка

final class TabItemView: NSView, NSDraggingSource {
    let sessionID: UUID
    var isSelected = false { didSet { needsDisplay = true; updateChrome() } }
    var onSelect: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: ((UUID) -> NSMenu?)?
    static let pinnedWidth: CGFloat = 46

    private var isPinned = false
    var isPinnedTab: Bool { isPinned }
    private var dimmed = false
    private var tagColor: TagColor?
    private var hasModel = false
    private let modelLabel = NSTextField(labelWithString: "")

    private let badge = FolderBadgeView(frame: NSRect(x: 0, y: 0, width: FolderBadgeView.size, height: FolderBadgeView.size))
    private let dot = StatusDotView(frame: NSRect(x: 0, y: 0, width: StatusDotView.size, height: StatusDotView.size))
    private let label = NSTextField(labelWithString: "")
    private var closeButton: NSButton!
    private var hovering = false { didSet { needsDisplay = true; updateChrome() } }
    private var downEvent: NSEvent?

    init(sessionID: UUID, title: String, status: SessionStatus) {
        self.sessionID = sessionID
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        addSubview(badge)
        addSubview(dot)
        addSubview(label)
        modelLabel.font = .systemFont(ofSize: 10)
        modelLabel.textColor = .tertiaryLabelColor
        addSubview(modelLabel)
        closeButton = symbolButton("xmark", tip: "Закрыть вкладку (⌘W)", target: self, action: #selector(closeClicked))
        addSubview(closeButton)
        update(title: title, status: status, tip: title, folder: nil, model: nil, tag: nil, pinned: false, dimmed: false)
        updateChrome()
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(title: String, status: SessionStatus, tip: String, folder: String?, model: String?,
                tag: TagColor?, pinned: Bool, dimmed: Bool) {
        badge.name = folder
        badge.isHidden = folder == nil
        if label.stringValue != title { label.stringValue = title }
        toolTip = tip
        dot.status = status
        modelLabel.stringValue = model ?? ""
        hasModel = model != nil
        tagColor = tag
        isPinned = pinned
        self.dimmed = dimmed
        alphaValue = dimmed ? 0.5 : 1
        needsLayout = true
        needsDisplay = true
        updateChrome()
    }

    private func updateChrome() {
        closeButton?.isHidden = isPinned || !(hovering || isSelected)
        label.isHidden = isPinned
        modelLabel.isHidden = isPinned || !hasModel || bounds.width < 150
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(sessionID) }

    // В области заголовка AppKit сам тянет окно за любую вьюху с mouseDownCanMoveWindow == true
    // (подписи, значки). Вкладка должна перетаскиваться сама, а не двигать окно.
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let v = super.hitTest(point) else { return nil }
        return v is NSButton ? v : self
    }

    @objc private func closeClicked() { onClose?() }

    override func layout() {
        super.layout()
        let d = StatusDotView.size
        updateChrome()
        let bs = FolderBadgeView.size
        let hasBadge = !badge.isHidden
        let bx: CGFloat = isPinned ? 8 : 10
        badge.frame = NSRect(x: bx, y: (bounds.height - bs) / 2, width: bs, height: bs)
        let dx = hasBadge ? bx + bs + 6 : bx
        dot.frame = NSRect(x: dx, y: (bounds.height - d) / 2, width: d, height: d)
        closeButton.frame = NSRect(x: bounds.width - 24, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let h = label.intrinsicContentSize.height
        let lx = dx + d + 8
        var right = bounds.width - 28
        if !modelLabel.isHidden {
            let mw = ceil(modelLabel.intrinsicContentSize.width) + 2
            modelLabel.frame = NSRect(x: right - mw, y: (bounds.height - modelLabel.intrinsicContentSize.height) / 2,
                                      width: mw, height: modelLabel.intrinsicContentSize.height)
            right -= mw + 6
        }
        label.frame = NSRect(x: lx, y: (bounds.height - h) / 2, width: max(0, right - lx), height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 4)
        let alpha: CGFloat = isSelected ? 0.14 : (hovering ? 0.07 : 0)
        if alpha > 0 {
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
        }
        if let t = tagColor {   // цветная метка — полоска под вкладкой
            t.color.setFill()
            let bar = NSRect(x: r.minX + 10, y: r.minY + 1.5, width: r.width - 20, height: 3)
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { downEvent = nil; onDoubleClick?(); return }
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard hypot(dx, dy) > 4 else { return }
        downEvent = nil
        let pb = NSPasteboardItem()
        pb.setString(sessionID.uuidString, forType: Theme.dragType)
        let item = NSDraggingItem(pasteboardWriter: pb)
        item.setDraggingFrame(bounds, contents: snapshot(of: self))
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) { downEvent = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}

// MARK: - Панель вкладок

final class TabBarView: NSView {
    static let height: CGFloat = 38
    static let maxTabWidth: CGFloat = 220
    var onSelect: ((UUID) -> Void)?
    var onDoubleClick: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onNew: (() -> Void)?
    var onToggleGrid: (() -> Void)?
    var onFilter: ((NSView) -> Void)?
    var onBackToGrid: (() -> Void)?
    var onTogglePlan: (() -> Void)?
    var tabMenuProvider: ((UUID) -> NSMenu?)?
    var onShowPinned: ((NSView) -> Void)?

    /// (перетаскиваемая сессия, позиция вставки в текущем массиве)
    var onMove: ((UUID, Int) -> Void)?

    private var items: [TabItemView] = []
    private var addButton: NSButton!
    private var gridButton: NSButton!
    private var filterButton: NSButton!
    private var planButton: NSButton!
    private let indicator = NSView()
    private var backButton: NSButton!
    let limits = LimitsView(frame: .zero)
    private let pinned = PinnedStackView(frame: .zero)
    private var lastPinnedShown: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.barBG.cgColor
        addButton = symbolButton("plus", tip: "Новая вкладка (⌘T)", target: self, action: #selector(newClicked))
        gridButton = symbolButton("square.grid.2x2", tip: "Сетка (⇧⌘G)", target: self, action: #selector(gridClicked))
        filterButton = symbolButton("line.3.horizontal.decrease.circle", tip: "Какие вкладки показывать в сетке",
                                    target: self, action: #selector(filterClicked))
        planButton = symbolButton("checklist", tip: "Панель плана агента (⌥⌘P)", target: self, action: #selector(planClicked))
        [addButton, gridButton, filterButton, planButton].forEach { addSubview($0!) }
        backButton = NSButton(title: " К сетке", target: self, action: #selector(backClicked))
        backButton.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "К сетке")
        backButton.imagePosition = .imageLeading
        backButton.bezelStyle = .rounded
        backButton.controlSize = .small
        backButton.contentTintColor = Theme.accent
        backButton.toolTip = "Вернуться к сетке"
        backButton.isHidden = true
        addSubview(backButton)
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = Theme.accent.cgColor
        indicator.layer?.cornerRadius = 1
        indicator.isHidden = true
        addSubview(indicator)
        addSubview(limits)
        pinned.isHidden = true
        pinned.onSelect = { [weak self] id in self?.onSelect?(id) }
        pinned.onShowList = { [weak self] v in self?.onShowPinned?(v) }
        pinned.menuProvider = { [weak self] id in self?.tabMenuProvider?(id) }
        addSubview(pinned)
        registerForDraggedTypes([Theme.dragType])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func newClicked() { onNew?() }
    @objc private func gridClicked() { onToggleGrid?() }
    @objc private func filterClicked() { onFilter?(filterButton) }
    @objc private func backClicked() { onBackToGrid?() }
    @objc private func planClicked() { onTogglePlan?() }

    func setPlanActive(_ on: Bool) { planButton.contentTintColor = on ? Theme.accent : .secondaryLabelColor }

    private var returnToGrid = false

    func reload(sessions: [TerminalSession], selected: UUID?, gridMode: Bool, returnToGrid: Bool = false) {
        gridButton.contentTintColor = gridMode ? Theme.accent : .secondaryLabelColor
        filterButton.contentTintColor = gridMode ? Theme.accent : .secondaryLabelColor
        if self.returnToGrid != returnToGrid || backButton.isHidden == returnToGrid {
            self.returnToGrid = returnToGrid
            backButton.isHidden = !returnToGrid
            needsLayout = true
        }

        // закреплённые — в «стопке» слева; в основном ряду только обычные вкладки
        let pinnedSessions = sessions.filter(\.isPinned)
        let normal = sessions.filter { !$0.isPinned }
        pinnedCount = pinnedSessions.count
        if pinnedSessions.isEmpty {
            if !pinned.isHidden { pinned.isHidden = true; needsLayout = true }
        } else {
            let shown: TerminalSession
            if let sel = pinnedSessions.first(where: { $0.id == selected }) { shown = sel }
            else if let last = pinnedSessions.first(where: { $0.id == lastPinnedShown }) { shown = last }
            else { shown = pinnedSessions[0] }
            lastPinnedShown = shown.id
            let others = pinnedSessions.filter { $0.id != shown.id }
            let attention: SessionStatus? = others.contains { $0.status == .waiting } ? .waiting
                                          : (others.contains { $0.status == .done } ? .done : nil)
            let wasHidden = pinned.isHidden
            pinned.update(shown: shown, count: pinnedSessions.count, selected: shown.id == selected,
                          dimmed: gridMode && !shown.inGrid, attention: attention)
            pinned.isHidden = false
            if wasHidden { needsLayout = true }
            needsLayout = true
        }

        func apply(_ it: TabItemView, _ s: TerminalSession) {
            it.update(title: s.displayTitle, status: s.status, tip: s.detailText, folder: s.folder, model: s.modelName ?? s.agentName,
                      tag: s.tag, pinned: false, dimmed: gridMode && !s.inGrid)
            it.isSelected = (s.id == selected)
        }

        // Тот же набор вкладок → обновляем на месте (не ломаем hover и drag).
        if items.map(\.sessionID) == normal.map(\.id) {
            for (it, s) in zip(items, normal) { apply(it, s) }
            needsLayout = true
            return
        }
        items.forEach { $0.removeFromSuperview() }
        items = normal.map { s in
            let v = TabItemView(sessionID: s.id, title: s.displayTitle, status: s.status)
            v.onSelect = { [weak self] in self?.onSelect?(s.id) }
            v.onDoubleClick = { [weak self] in self?.onDoubleClick?(s.id) }
            v.onClose = { [weak self] in self?.onClose?(s.id) }
            v.menuProvider = { [weak self] id in self?.tabMenuProvider?(id) }
            apply(v, s)
            addSubview(v, positioned: .below, relativeTo: indicator)
            return v
        }
        needsLayout = true
    }

    private var leftInset: CGFloat { 12 }   // кнопки окна теперь в отдельной строке заголовка выше

    private var pinnedCount = 0
    private var rightReserved: CGFloat { limits.preferredWidth + 12 + 94 + (returnToGrid ? 96 : 0) }
    private var pinnedBlockWidth: CGFloat { pinned.isHidden ? 0 : pinned.preferredWidth + 10 }

    private var tabWidth: CGFloat {
        let reserved = leftInset + 12 + 34 + rightReserved + 16 + pinnedBlockWidth
        let avail = bounds.width - reserved
        guard !items.isEmpty else { return Self.maxTabWidth }
        return min(Self.maxTabWidth, max(70, avail / CGFloat(items.count)))
    }

    override func layout() {
        super.layout()
        var x = leftInset
        if !pinned.isHidden {
            let w = pinned.preferredWidth
            pinned.frame = NSRect(x: x, y: 6, width: w, height: bounds.height - 12)
            x += w + 10
        }
        let w = tabWidth
        for it in items {
            it.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
            x += w
        }
        let bh: CGFloat = 22
        addButton.frame = NSRect(x: x + 6, y: (bounds.height - bh) / 2, width: 22, height: bh)
        gridButton.frame = NSRect(x: bounds.width - 38, y: (bounds.height - bh) / 2, width: 24, height: bh)
        filterButton.frame = NSRect(x: bounds.width - 66, y: (bounds.height - bh) / 2, width: 24, height: bh)
        planButton.frame = NSRect(x: bounds.width - 94, y: (bounds.height - bh) / 2, width: 24, height: bh)
        let lw = limits.preferredWidth
        limits.frame = NSRect(x: bounds.width - 94 - 12 - lw, y: 0, width: lw, height: bounds.height)
        let bw: CGFloat = 86
        backButton.frame = NSRect(x: limits.frame.minX - 10 - bw, y: (bounds.height - 22) / 2, width: bw, height: 22)
    }

    override var mouseDownCanMoveWindow: Bool { false }   // окно двигаем сами (performDrag) — только за пустое место

    // MARK: Перетаскивание окна и двойной клик по панели
    //
    // Окно начинаем тащить только когда мышь реально сдвинулась. Раньше performDrag вызывался сразу
    // на первом клике двойного клика, и «прилипшее» к краю экрана окно после zoom возвращалось обратно.

    private var downEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 {
            downEvent = nil
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        guard hypot(event.locationInWindow.x - down.locationInWindow.x,
                    event.locationInWindow.y - down.locationInWindow.y) > 3 else { return }
        downEvent = nil
        window?.performDrag(with: down)
    }

    override func mouseUp(with event: NSEvent) { downEvent = nil }

    // MARK: drop

    private func insertionIndex(for info: NSDraggingInfo) -> Int {
        let x = convert(info.draggingLocation, from: nil).x
        return items.filter { $0.frame.midX < x }.count
    }

    private func showIndicator(at index: Int) {
        let x: CGFloat = index < items.count ? items[index].frame.minX
                                             : (items.last?.frame.maxX ?? leftInset)
        indicator.frame = NSRect(x: x - 1, y: 7, width: 2, height: bounds.height - 14)
        indicator.isHidden = false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        showIndicator(at: insertionIndex(for: sender))
        return .move
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        showIndicator(at: insertionIndex(for: sender))
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { indicator.isHidden = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { indicator.isHidden = true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        indicator.isHidden = true
        guard let s = sender.draggingPasteboard.string(forType: Theme.dragType),
              let id = UUID(uuidString: s) else { return false }
        let idx = insertionIndex(for: sender)
        let full = idx + pinnedCount
        DispatchQueue.main.async { [weak self] in self?.onMove?(id, full) }
        return true
    }
}
