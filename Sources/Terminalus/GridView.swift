import AppKit

// MARK: - Ячейка сетки

final class GridCellView: NSView, NSDraggingSource {
    static let headerHeight: CGFloat = 28

    let sessionID: UUID
    let body = NSView()
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onHide: (() -> Void)?
    var menuProvider: ((UUID) -> NSMenu?)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private let tagStrip = NSView()
    private let modelLabel = NSTextField(labelWithString: "")
    private let badge = FolderBadgeView(frame: NSRect(x: 0, y: 0, width: FolderBadgeView.size, height: FolderBadgeView.size))
    private let dot = StatusDotView(frame: NSRect(x: 0, y: 0, width: StatusDotView.size, height: StatusDotView.size))
    private let titleLabel = NSTextField(labelWithString: "")
    private var closeButton: NSButton!
    private var hideButton: NSButton!
    private var downEvent: NSEvent?
    private var isSelected = false { didSet { updateBorder() } }

    init(session: TerminalSession, selected: Bool) {
        sessionID = session.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.terminalBG.cgColor

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(badge)
        addSubview(dot)
        addSubview(titleLabel)
        modelLabel.font = .systemFont(ofSize: 10)
        modelLabel.textColor = .tertiaryLabelColor
        modelLabel.alignment = .right
        addSubview(modelLabel)
        tagStrip.wantsLayer = true
        addSubview(tagStrip)

        closeButton = symbolButton("xmark", tip: "Закрыть вкладку", target: self, action: #selector(closeClicked))
        hideButton = symbolButton("eye.slash", tip: "Убрать из сетки (вкладка останется открытой)",
                                  target: self, action: #selector(hideClicked))
        addSubview(closeButton)
        addSubview(hideButton)

        addSubview(body)
        session.view.removeFromSuperview()
        session.view.autoresizingMask = [.width, .height]
        body.addSubview(session.view)

        update(session)
        isSelected = selected
        updateBorder()
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ s: TerminalSession) {
        if titleLabel.stringValue != s.displayTitle { titleLabel.stringValue = s.displayTitle }
        badge.name = s.folder
        badge.isHidden = s.folder == nil
        dot.status = s.status
        modelLabel.stringValue = [s.plan?.chip, s.modelName ?? s.agentName].compactMap { $0 }.joined(separator: " · ")
        tagStrip.layer?.backgroundColor = s.tag?.color.cgColor
        tagStrip.isHidden = s.tag == nil
        needsLayout = true
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(sessionID) }

    func setSelected(_ v: Bool) { isSelected = v }

    private func updateBorder() {
        layer?.borderWidth = isSelected ? 1.5 : 1
        layer?.borderColor = (isSelected ? Theme.accent : NSColor.white.withAlphaComponent(0.10)).cgColor
    }

    @objc private func closeClicked() { onClose?() }
    @objc private func hideClicked() { onHide?() }

    override func layout() {
        super.layout()
        let h = Self.headerHeight
        let top = bounds.height - h
        let d = StatusDotView.size
        let bs = FolderBadgeView.size
        badge.frame = NSRect(x: 10, y: top + (h - bs) / 2, width: bs, height: bs)
        let dx: CGFloat = badge.isHidden ? 10 : 10 + bs + 6
        dot.frame = NSRect(x: dx, y: top + (h - d) / 2, width: d, height: d)
        let mw = modelLabel.stringValue.isEmpty ? 0 : min(140, ceil(modelLabel.intrinsicContentSize.width) + 2)
        modelLabel.frame = NSRect(x: bounds.width - 52 - mw, y: top + (h - 13) / 2, width: mw, height: 13)
        titleLabel.frame = NSRect(x: dx + d + 7, y: top + (h - 14) / 2,
                                  width: max(0, bounds.width - 62 - mw - (dx + d + 7)), height: 14)
        tagStrip.frame = NSRect(x: 0, y: bounds.height - 3, width: bounds.width, height: 3)
        closeButton.frame = NSRect(x: bounds.width - 24, y: top + (h - 16) / 2, width: 16, height: 16)
        hideButton.frame = NSRect(x: bounds.width - 46, y: top + (h - 16) / 2, width: 18, height: 16)
        body.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - h)
        if let tv = body.subviews.first {
            tv.frame = body.bounds.insetBy(dx: 6, dy: 4)
        }
    }

    // Клик по шапке (терминал и кнопки обрабатывают свои клики сами).
    // Перетаскивать окно можно ТОЛЬКО за шапку — края отданы под изменение размера.
    private func isInHeader(_ event: NSEvent) -> Bool {
        convert(event.locationInWindow, from: nil).y >= bounds.height - Self.headerHeight
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        guard isInHeader(event) else { downEvent = nil; return }
        downEvent = event
        if event.clickCount == 2 { downEvent = nil; onOpen?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        guard hypot(event.locationInWindow.x - down.locationInWindow.x,
                    event.locationInWindow.y - down.locationInWindow.y) > 4 else { return }
        downEvent = nil
        let pb = NSPasteboardItem()
        pb.setString(sessionID.uuidString, forType: Theme.dragType)
        let item = NSDraggingItem(pasteboardWriter: pb)
        let img = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            img.addRepresentation(rep)
        }
        item.setDraggingFrame(bounds, contents: img)
        onDragBegan?()
        beginDraggingSession(with: [item], event: down, source: self)
    }
    override func mouseUp(with event: NSEvent) { downEvent = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?()
    }
}

// MARK: - Сетка

final class GridView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?
    var onHide: ((UUID) -> Void)?
    var menuProvider: ((UUID) -> NSMenu?)?
    var onLayoutChanged: (() -> Void)?

    /// Раскладка окон (дерево разбиений). Меняется перетаскиванием шапок и границ.
    var tree: GNode?

    private var cells: [GridCellView] = []
    private var frames: [UUID: NSRect] = [:]          // положения по сохранённой раскладке
    private var dividers: [GridDivider] = []
    private var preview: GNode?                       // раскладка «как будет, если отпустить сейчас»
    private var activeDragID: UUID?
    private let gap: CGFloat = 10
    private let minCellW: CGFloat = 150
    private let minCellH: CGFloat = 110
    private let ghost = NSView()
    private let placeholder = NSTextField(wrappingLabelWithString:
        "В сетке нет вкладок.\nВыберите, какие показывать, кнопкой ⊜ справа вверху.")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.barBG.cgColor
        placeholder.alignment = .center
        placeholder.textColor = .tertiaryLabelColor
        placeholder.font = .systemFont(ofSize: 14)
        addSubview(placeholder)
        ghost.wantsLayer = true
        ghost.layer?.cornerRadius = 8
        ghost.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.16).cgColor
        ghost.layer?.borderColor = Theme.accent.cgColor
        ghost.layer?.borderWidth = 2
        ghost.isHidden = true
        registerForDraggedTypes([Theme.dragType])
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Данные

    private var autoColumns: Int {
        let n = max(1, cells.count)
        let aspect = bounds.height > 0 ? bounds.width / bounds.height : 1.5
        return min(n, max(1, Int(ceil(sqrt(Double(n) * Double(aspect))))))
    }

    /// Полная пересборка ячеек. Раскладка сохраняется; новые окна встают справа от последнего.
    func reload(sessions: [TerminalSession], selected: UUID?) {
        cells.forEach { $0.removeFromSuperview() }
        cells = sessions.map { s in
            let c = GridCellView(session: s, selected: s.id == selected)
            c.onSelect = { [weak self] in self?.onSelect?(s.id) }
            c.onOpen = { [weak self] in self?.onOpen?(s.id) }
            c.onClose = { [weak self] in self?.onClose?(s.id) }
            c.onHide = { [weak self] in self?.onHide?(s.id) }
            c.menuProvider = { [weak self] id in self?.menuProvider?(id) }
            c.onDragBegan = { [weak self] in self?.beginDrag(s.id) }
            c.onDragEnded = { [weak self] in self?.endDrag() }
            addSubview(c)
            return c
        }
        addSubview(ghost, positioned: .below, relativeTo: cells.first)

        let ids = sessions.map(\.id)
        var t = tree
        for gone in (t?.ids ?? []).filter({ !ids.contains($0) }) { t = t?.removing(gone) }
        let known = Set(t?.ids ?? [])
        let fresh = ids.filter { !known.contains($0) }
        if t == nil {
            t = GNode.auto(ids: fresh, cols: autoColumns)
        } else {
            for id in fresh { t = t!.inserting(id, at: t!.ids.last!, edge: .right) }
        }
        tree = t
        placeholder.isHidden = !cells.isEmpty
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// Обновление заголовков/статусов без пересборки.
    func update(sessions: [TerminalSession]) {
        for s in sessions { cells.first { $0.sessionID == s.id }?.update(s) }
    }

    func setSelected(_ id: UUID?) {
        cells.forEach { $0.setSelected($0.sessionID == id) }
    }

    func resetLayout() {
        tree = GNode.auto(ids: cells.map(\.sessionID), cols: autoColumns)
        needsLayout = true
    }

    // MARK: Раскладка

    private func compute(_ node: GNode) -> ([UUID: NSRect], [GridDivider]) {
        var f: [UUID: NSRect] = [:]
        var d: [GridDivider] = []
        node.layout(in: bounds.insetBy(dx: gap, dy: gap), gap: gap, frames: &f, dividers: &d)
        return (f, d)
    }

    override func layout() {
        super.layout()
        placeholder.frame = NSRect(x: 40, y: bounds.midY - 30, width: max(0, bounds.width - 80), height: 60)
        guard let t = tree, bounds.width > 0, bounds.height > 0 else { return }
        let (f, d) = compute(t)
        frames = f
        dividers = d
        let shown = preview.map { compute($0).0 } ?? f
        for c in cells { if let r = shown[c.sessionID] { c.frame = r } }
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Границы между окнами — тянем мышью (приоритет над перетаскиванием окна)

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if bounds.contains(p), activeDragID == nil, dividers.contains(where: { $0.rect.contains(p) }) { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for d in dividers { addCursorRect(d.rect, cursor: d.axis == .cols ? .resizeLeftRight : .resizeUpDown) }
    }

    private var resize: (div: GridDivider, start: NSPoint)?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let d = dividers.first(where: { $0.rect.contains(p) }) else { return }
        if event.clickCount == 2, let t = tree {          // двойной клик — выровнять
            tree = t.settingWeights(at: ArraySlice(d.path), Array(repeating: 1, count: d.sizes.count))
            needsLayout = true
            onLayoutChanged?()
            return
        }
        resize = (d, event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let r = resize, let t = tree else { return }
        let i = r.div.index
        let sizes = r.div.sizes
        let total = sizes[i] + sizes[i + 1]
        let delta = r.div.axis == .cols ? event.locationInWindow.x - r.start.x
                                        : -(event.locationInWindow.y - r.start.y)
        let minV = r.div.axis == .cols ? minCellW : minCellH
        let a = max(minV, min(total - minV, sizes[i] + delta))
        var ns = sizes
        ns[i] = a
        ns[i + 1] = total - a
        tree = t.settingWeights(at: ArraySlice(r.div.path), ns)
        needsLayout = true          // перекладка не форсируется: AppKit объединит события в один проход за кадр
    }

    override func mouseUp(with event: NSEvent) {
        if resize != nil { resize = nil; layoutSubtreeIfNeeded(); onLayoutChanged?() }
    }

    // MARK: Перестановка окон: перетаскивание шапки с живым предпросмотром

    private enum Drop { case edge(UUID, GridEdge), root(GridEdge), swap(UUID) }

    private func dropTarget(at p: NSPoint, dragging id: UUID) -> Drop? {
        guard let t = tree, t.ids.count > 1 else { return nil }
        let m: CGFloat = 20          // у края всей сетки — колонка/строка на весь размер
        if p.x < m { return .root(.left) }
        if p.x > bounds.width - m { return .root(.right) }
        if p.y > bounds.height - m { return .root(.top) }
        if p.y < m { return .root(.bottom) }

        // окно под курсором (или ближайшее, если курсор в промежутке)
        var target: UUID?
        var best = CGFloat.greatestFiniteMagnitude
        for (tid, r) in frames {
            let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
            let dist = hypot(dx, dy)
            if dist < best { best = dist; target = tid }
        }
        guard let tid = target, tid != id, let r = frames[tid] else { return nil }
        let u = (p.x - r.minX) / r.width - 0.5, v = (p.y - r.minY) / r.height - 0.5
        if abs(u) < 0.16 && abs(v) < 0.16 { return .swap(tid) }        // центр — поменять местами
        if abs(u) > abs(v) { return .edge(tid, u < 0 ? .left : .right) }
        return .edge(tid, v > 0 ? .top : .bottom)
    }

    private func previewTree(_ id: UUID, _ drop: Drop?) -> GNode? {
        guard let t = tree, let drop else { return nil }
        switch drop {
        case .swap(let o): return t.swapping(id, o)
        case .edge(let o, let e): return t.removing(id)?.inserting(id, at: o, edge: e)
        case .root(let e): return t.removing(id)?.insertingAtRoot(id, edge: e)
        }
    }

    private func beginDrag(_ id: UUID) {
        activeDragID = id
        cells.first { $0.sessionID == id }?.alphaValue = 0      // окно «в руке», на его месте — подсветка
        showGhost(for: id, in: tree)
    }

    private func endDrag() {
        activeDragID = nil
        ghost.isHidden = true
        cells.forEach { $0.alphaValue = 1 }
        preview = nil
        needsLayout = true
    }

    private func showGhost(for id: UUID, in node: GNode?) {
        guard let node, let r = compute(node).0[id] else { ghost.isHidden = true; return }
        let wasHidden = ghost.isHidden
        ghost.isHidden = false
        if wasHidden { ghost.frame = r } else { NSAnimationContext.runAnimationGroup { c in c.duration = 0.18; ghost.animator().frame = r } }
    }

    /// Плавно переставляет остальные окна под предпросмотр.
    private func setPreview(_ node: GNode?, dragging id: UUID) {
        guard node != preview else { return }
        preview = node
        guard let base = node ?? tree else { return }
        let target = compute(base).0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            for c in cells { if let r = target[c.sessionID] { c.animator().frame = r } }
        }
        showGhost(for: id, in: base)
    }

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        info.draggingPasteboard.string(forType: Theme.dragType).flatMap(UUID.init(uuidString:))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let id = draggedID(sender), activeDragID == nil, tree?.contains(id) == true { beginDrag(id) }   // перетащили вкладку из списка
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = draggedID(sender), tree?.contains(id) == true else { return [] }
        let drop = dropTarget(at: convert(sender.draggingLocation, from: nil), dragging: id)
        setPreview(previewTree(id, drop), dragging: id)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let id = activeDragID { setPreview(nil, dragging: id) }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = draggedID(sender) else { return false }
        let drop = dropTarget(at: convert(sender.draggingLocation, from: nil), dragging: id)
        guard let newTree = previewTree(id, drop) else { return false }
        tree = newTree
        preview = nil
        needsLayout = true
        onLayoutChanged?()
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { endDrag() }
    override func draggingEnded(_ sender: NSDraggingInfo) { endDrag() }
}
