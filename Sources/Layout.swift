import CoreGraphics

/// Geometry of a tree: effects stack upward from the core, causes downward, and every
/// arrow points up (cause -> problem -> effect). Knows nothing about drawing; text
/// height comes in through a closure so this stays testable without AppKit.
struct TreeLayout {
    struct Item {
        let node: TreeNode
        let side: Side
        let depth: Int
        let parentID: String?
        let isRootCause: Bool
        var frame: CGRect
    }
    struct Band {
        let side: Side
        let rect: CGRect
    }

    static let nodeWidth: CGFloat = 200
    static let coreWidth: CGFloat = 280
    static let gapX: CGFloat = 22
    static let gapY: CGFloat = 64
    static let padding: CGFloat = 56
    static let labelGutter: CGFloat = 30

    var items: [Item] = []
    var edges: [[CGPoint]] = []   // polylines; the last point is the arrow tip
    var bands: [Band] = []
    var size: CGSize = .zero
    var levels: [String: LevelStyle] = [:]

    func item(id: String) -> Item? { items.first { $0.node.id == id } }
    func item(at p: CGPoint) -> Item? { items.last { $0.frame.contains(p) } }

    static func compute(tree: PolicyTree, height: (TreeNode, Side, Int) -> CGFloat) -> TreeLayout {
        struct Raw { let node: TreeNode; let side: Side; let depth: Int; let parent: String?; let isRoot: Bool; let h: CGFloat; var x: CGFloat = 0 }
        var raw: [String: Raw] = [:]
        var order: [String] = [PolicyTree.coreID]
        var levelE: [Int: CGFloat] = [:], levelC: [Int: CGFloat] = [:]
        var widths: [String: CGFloat] = [:]

        raw[PolicyTree.coreID] = Raw(node: tree.core, side: .core, depth: 0, parent: nil, isRoot: false, h: height(tree.core, .core, 0))

        func collect(_ arr: [TreeNode], _ side: Side, _ depth: Int, _ parent: String) {
            for n in arr {
                let h = height(n, side, depth)
                raw[n.id] = Raw(node: n, side: side, depth: depth, parent: parent,
                                isRoot: side == .cause && n.children.isEmpty, h: h)
                order.append(n.id)
                if side == .effect { levelE[depth] = max(levelE[depth] ?? 0, h) } else { levelC[depth] = max(levelC[depth] ?? 0, h) }
                collect(n.children, side, depth + 1, n.id)
            }
        }
        collect(tree.effects, .effect, 1, PolicyTree.coreID)
        collect(tree.causes, .cause, 1, PolicyTree.coreID)

        func rowWidth(_ arr: [TreeNode]) -> CGFloat {
            arr.isEmpty ? 0 : arr.reduce(0) { $0 + subtreeWidth($1) } + gapX * CGFloat(arr.count - 1)
        }
        func subtreeWidth(_ n: TreeNode) -> CGFloat {
            let w = max(nodeWidth, rowWidth(n.children))
            widths[n.id] = w
            return w
        }
        let eTotal = rowWidth(tree.effects), cTotal = rowWidth(tree.causes)
        let inner = max(eTotal, cTotal, coreWidth)
        let x0 = padding + labelGutter

        func place(_ arr: [TreeNode], _ startLeft: CGFloat) {
            var left = startLeft
            for n in arr {
                let w = widths[n.id]!
                raw[n.id]!.x = left + w / 2
                if !n.children.isEmpty {
                    let cw = n.children.reduce(0) { $0 + widths[$1.id]! } + gapX * CGFloat(n.children.count - 1)
                    place(n.children, left + (w - cw) / 2)
                }
                left += w + gapX
            }
        }
        place(tree.effects, x0 + (inner - eTotal) / 2)
        place(tree.causes, x0 + (inner - cTotal) / 2)
        raw[PolicyTree.coreID]!.x = x0 + inner / 2

        var topE: [Int: CGFloat] = [:], topC: [Int: CGFloat] = [:]
        var y = padding
        let maxE = levelE.keys.max() ?? 0, maxC = levelC.keys.max() ?? 0
        if maxE > 0 {
            for d in stride(from: maxE, through: 1, by: -1) { topE[d] = y; y += levelE[d]! + gapY }
        }
        let coreTop = y, coreH = raw[PolicyTree.coreID]!.h
        y += coreH
        if maxC > 0 {
            for d in 1...maxC { y += gapY; topC[d] = y; y += levelC[d]! }
        }

        var out = TreeLayout()
        out.levels = tree.levels
        out.size = CGSize(width: inner + x0 + padding, height: y + padding)
        var frames: [String: CGRect] = [:]
        for id in order {
            let r = raw[id]!
            let w = r.side == .core ? coreWidth : nodeWidth
            let top: CGFloat
            switch r.side {
            case .core: top = coreTop
            case .effect: top = topE[r.depth]! + levelE[r.depth]! - r.h   // sit on the row edge nearest the core
            case .cause: top = topC[r.depth]!
            }
            let f = CGRect(x: r.x - w / 2, y: top, width: w, height: r.h)
            frames[id] = f
            out.items.append(Item(node: r.node, side: r.side, depth: r.depth, parentID: r.parent, isRootCause: r.isRoot, frame: f))
        }
        for item in out.items {
            guard let pid = item.parentID, let p = frames[pid] else { continue }
            let f = item.frame
            if item.side == .cause {
                let mid = p.maxY + gapY / 2
                out.edges.append([CGPoint(x: f.midX, y: f.minY), CGPoint(x: f.midX, y: mid), CGPoint(x: p.midX, y: mid), CGPoint(x: p.midX, y: p.maxY)])
            } else {
                let mid = p.minY - gapY / 2
                out.edges.append([CGPoint(x: p.midX, y: p.minY), CGPoint(x: p.midX, y: mid), CGPoint(x: f.midX, y: mid), CGPoint(x: f.midX, y: f.maxY)])
            }
        }
        let bandX: CGFloat = 8, bandW = labelGutter + 20
        if maxE > 0 { out.bands.append(Band(side: .effect, rect: CGRect(x: bandX, y: padding - 24, width: bandW, height: coreTop - gapY / 2 - (padding - 24)))) }
        out.bands.append(Band(side: .core, rect: CGRect(x: bandX, y: coreTop - 10, width: bandW, height: coreH + 20)))
        if maxC > 0 {
            let top = coreTop + coreH + gapY / 2
            out.bands.append(Band(side: .cause, rect: CGRect(x: bandX, y: top, width: bandW, height: y + 24 - top)))
        }
        return out
    }
}
