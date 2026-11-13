import AppKit

/// Раскладка сетки — дерево разбиений (как в тайловых менеджерах окон).
/// cols — окна рядом, rows — окна друг под другом; вложенность даёт любые раскладки:
/// например, одно высокое окно слева и два маленьких справа.
enum GridAxis: String, Codable { case cols, rows }

enum GridEdge {
    case left, right, top, bottom
    var axis: GridAxis { (self == .left || self == .right) ? .cols : .rows }
    var isBefore: Bool { self == .left || self == .top }
}

struct GridDivider {
    var rect: NSRect
    var path: [Int]
    var index: Int
    var axis: GridAxis
    var sizes: [CGFloat]
}

indirect enum GNode: Equatable {
    case leaf(UUID)
    case split(GridAxis, [GNode], [CGFloat])

    var ids: [UUID] {
        switch self {
        case .leaf(let i): return [i]
        case .split(_, let ch, _): return ch.flatMap(\.ids)
        }
    }
    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    // MARK: Построение

    /// Автораскладка: строки по `cols` окон.
    static func auto(ids: [UUID], cols: Int) -> GNode? {
        guard !ids.isEmpty else { return nil }
        let c = max(1, cols)
        let rows: [GNode] = stride(from: 0, to: ids.count, by: c).map { start in
            let chunk = ids[start..<min(start + c, ids.count)].map { GNode.leaf($0) }
            return chunk.count == 1 ? chunk[0] : .split(.cols, chunk, Array(repeating: 1, count: chunk.count))
        }
        return rows.count == 1 ? rows[0] : .split(.rows, rows, Array(repeating: 1, count: rows.count))
    }

    // MARK: Правки

    func removing(_ id: UUID) -> GNode? {
        switch self {
        case .leaf(let i): return i == id ? nil : self
        case .split(let a, let ch, let w):
            var nc: [GNode] = [], nw: [CGFloat] = []
            for (c, wi) in zip(ch, w) { if let r = c.removing(id) { nc.append(r); nw.append(wi) } }
            if nc.isEmpty { return nil }
            if nc.count == 1 { return nc[0] }
            return GNode.split(a, nc, nw).normalized()
        }
    }

    /// Схлопывает вложенные разбиения одного направления.
    func normalized() -> GNode {
        guard case .split(let a, let ch, let w) = self else { return self }
        var nc: [GNode] = [], nw: [CGFloat] = []
        for (c0, wi) in zip(ch, w) {
            let c = c0.normalized()
            if case .split(let ca, let cch, let cw) = c, ca == a {
                let ct = cw.reduce(0, +)
                for (cc, cwi) in zip(cch, cw) { nc.append(cc); nw.append(wi * cwi / ct) }
            } else {
                nc.append(c); nw.append(wi)
            }
        }
        return nc.count == 1 ? nc[0] : .split(a, nc, nw)
    }

    /// Вставить окно `id` с нужной стороны окна `target`.
    func inserting(_ id: UUID, at target: UUID, edge: GridEdge) -> GNode {
        switch self {
        case .leaf(let t):
            guard t == target else { return self }
            let kids: [GNode] = edge.isBefore ? [.leaf(id), self] : [self, .leaf(id)]
            return .split(edge.axis, kids, [1, 1])
        case .split(let a, let ch, let w):
            var nc = ch, nw = w
            for i in ch.indices {
                if case .leaf(let t) = ch[i], t == target {
                    if a == edge.axis {
                        let half = w[i] / 2
                        nw[i] = half
                        let pos = edge.isBefore ? i : i + 1
                        nc.insert(.leaf(id), at: pos)
                        nw.insert(half, at: pos)
                    } else {
                        nc[i] = ch[i].inserting(id, at: target, edge: edge)
                    }
                    return GNode.split(a, nc, nw).normalized()
                } else if ch[i].contains(target) {
                    nc[i] = ch[i].inserting(id, at: target, edge: edge)
                    return GNode.split(a, nc, nw).normalized()
                }
            }
            return self
        }
    }

    /// Вставить окно с края всей сетки: колонка/строка на весь размер.
    func insertingAtRoot(_ id: UUID, edge: GridEdge) -> GNode {
        let axis = edge.axis
        if case .split(let a, let ch, let w) = self, a == axis {
            let avg = w.reduce(0, +) / CGFloat(w.count)
            var nc = ch, nw = w
            let pos = edge.isBefore ? 0 : ch.count
            nc.insert(.leaf(id), at: pos)
            nw.insert(avg, at: pos)
            return .split(a, nc, nw)
        }
        let kids: [GNode] = edge.isBefore ? [.leaf(id), self] : [self, .leaf(id)]
        return GNode.split(axis, kids, edge.isBefore ? [0.3, 0.7] : [0.7, 0.3]).normalized()
    }

    func swapping(_ a: UUID, _ b: UUID) -> GNode {
        switch self {
        case .leaf(let i): return .leaf(i == a ? b : (i == b ? a : i))
        case .split(let ax, let ch, let w): return .split(ax, ch.map { $0.swapping(a, b) }, w)
        }
    }

    func settingWeights(at path: ArraySlice<Int>, _ nw: [CGFloat]) -> GNode {
        guard case .split(let a, let ch, let w) = self else { return self }
        if let first = path.first {
            var nc = ch
            nc[first] = ch[first].settingWeights(at: path.dropFirst(), nw)
            return .split(a, nc, w)
        }
        return .split(a, ch, nw)
    }

    // MARK: Геометрия

    func layout(in rect: NSRect, gap: CGFloat, path: [Int] = [],
                frames: inout [UUID: NSRect], dividers: inout [GridDivider]) {
        switch self {
        case .leaf(let id):
            frames[id] = rect
        case .split(let axis, let ch, let w):
            let n = ch.count
            let total = w.reduce(0, +)
            let length = (axis == .cols ? rect.width : rect.height) - gap * CGFloat(n - 1)
            let sizes = w.map { max(1, length * $0 / total) }
            var pos: CGFloat = axis == .cols ? rect.minX : rect.maxY
            var rects: [NSRect] = []
            for (i, c) in ch.enumerated() {
                let r: NSRect
                if axis == .cols {
                    r = NSRect(x: pos, y: rect.minY, width: sizes[i], height: rect.height)
                    pos += sizes[i] + gap
                } else {
                    r = NSRect(x: rect.minX, y: pos - sizes[i], width: rect.width, height: sizes[i])
                    pos -= sizes[i] + gap
                }
                c.layout(in: r, gap: gap, path: path + [i], frames: &frames, dividers: &dividers)
                rects.append(r)
            }
            for i in 0..<(n - 1) {
                let d: NSRect
                if axis == .cols {
                    d = NSRect(x: rects[i].maxX - 4, y: rect.minY, width: gap + 8, height: rect.height)
                } else {
                    d = NSRect(x: rect.minX, y: rects[i + 1].maxY - 4, width: rect.width, height: gap + 8)
                }
                dividers.append(GridDivider(rect: d, path: path, index: i, axis: axis, sizes: sizes))
            }
        }
    }

    // MARK: Сохранение (по номерам вкладок: UUID меняются при каждом запуске)

    func saved(index: (UUID) -> Int?) -> SavedGridNode? {
        switch self {
        case .leaf(let id):
            return index(id).map { SavedGridNode(axis: nil, index: $0, children: nil, weights: nil) }
        case .split(let a, let ch, let w):
            let kids = ch.compactMap { $0.saved(index: index) }
            guard kids.count == ch.count else { return nil }
            return SavedGridNode(axis: a.rawValue, index: nil, children: kids, weights: w.map { Double($0) })
        }
    }

    static func from(_ s: SavedGridNode, ids: [UUID]) -> GNode? {
        if let i = s.index { return i < ids.count ? .leaf(ids[i]) : nil }
        guard let a = s.axis.flatMap(GridAxis.init(rawValue:)), let kids = s.children, let w = s.weights,
              kids.count == w.count else { return nil }
        let nodes = kids.compactMap { from($0, ids: ids) }
        guard nodes.count == kids.count else { return nil }
        return nodes.count == 1 ? nodes[0] : .split(a, nodes, w.map { CGFloat($0) })
    }
}

struct SavedGridNode: Codable {
    var axis: String?
    var index: Int?
    var children: [SavedGridNode]?
    var weights: [Double]?
}
