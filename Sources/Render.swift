import AppKit

enum Palette {
    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? hex(dark) : hex(light) }
    }
    static let canvas = dyn(0xF2F4F1, 0x151917)
    static let card = dyn(0xFFFFFF, 0x212725)
    static let cardLine = dyn(0xD3D9D5, 0x38413D)
    static let band = dyn(0xE6EBE7, 0x1D2321)
    static let edge = dyn(0x8C9893, 0x6E7A75)
    static let effect = dyn(0x9A5B14, 0xE1A45C)
    static let core = dyn(0x8C1D2A, 0xB23A4B)
    static let cause = dyn(0x1D5964, 0x62B2BD)
    static let goal = dyn(0x2D6A3B, 0x62B376)
    static let goalCore = dyn(0x2D6A3B, 0x37804A)

    static func parse(_ hexString: String?) -> NSColor? {
        guard let h = hexString.flatMap(LevelStyle.normalizedHex), let v = UInt32(h.dropFirst(), radix: 16) else { return nil }
        return hex(v)
    }

    static func hexString(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        func b(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(s.redComponent), b(s.greenComponent), b(s.blueComponent))
    }

    /// Built-in colour of a level, before any user change.
    static func defaultColor(side: Side, goal: Bool) -> NSColor {
        switch side {
        case .core: return goal ? goalCore : core
        case .effect: return goal ? self.goal : effect
        case .cause: return goal ? self.goal : cause
        }
    }

    /// A chosen colour wins in both views, so the user sees the same tree in problem and goal mode.
    static func levelColor(_ st: LevelStyle, side: Side, goal: Bool) -> NSColor {
        parse(st.color) ?? defaultColor(side: side, goal: goal)
    }

    static func color(_ a: Aspek?) -> NSColor {
        switch a {
        case .regulasi: return dyn(0x7A4FB0, 0xA98AE0)
        case .kelembagaan: return dyn(0x1D5964, 0x62B2BD)
        case .anggaran: return dyn(0xB0631A, 0xE1A45C)
        case .sdm: return dyn(0x3F7D3A, 0x7FC17A)
        case .sosbud: return dyn(0xB33A5B, 0xE37A96)
        case .infra: return dyn(0x4A6FA5, 0x86A8DE)
        case nil: return edge
        }
    }
}

/// Wording and drawing shared by the live canvas and by export/print.
enum TreeRenderer {
    private static let metaFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    private static let bodyFont = NSFont.systemFont(ofSize: 13.5)
    private static let bandFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
    private static let coreFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 18, weight: .medium)
        return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 18) } ?? base
    }()

    private static let padX: CGFloat = 11
    private static let padTop: CGFloat = 10
    private static let padBottom: CGFloat = 11
    private static let metaHeight: CGFloat = 19
    private static let corePadX: CGFloat = 16
    private static let corePadY: CGFloat = 14

    static func defaultKindLabel(side: Side, depth: Int, goal: Bool) -> String {
        switch side {
        case .core: return goal ? L("Tujuan utama") : L("Masalah inti")
        case .effect: return L("{0} tingkat {1}", goal ? L("Manfaat") : L("Dampak"), depth)
        case .cause: return L("{0} tingkat {1}", goal ? L("Sarana") : L("Penyebab"), depth)
        }
    }

    static func kindLabel(side: Side, depth: Int, goal: Bool, levels: [String: LevelStyle] = [:]) -> String {
        let st = levels[PolicyTree.levelKey(side: side, depth: depth)] ?? LevelStyle()
        return (goal ? st.goalName : st.name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultKindLabel(side: side, depth: depth, goal: goal)
    }

    /// Extra inner room so text stays clear of slanted or curved edges.
    private static func inset(_ shape: NodeShape) -> (x: CGFloat, y: CGFloat) {
        switch shape {
        case .rounded, .rect: return (0, 0)
        case .pill: return (10, 0)
        case .hexagon: return (16, 0)
        case .ellipse: return (24, 9)
        }
    }

    static func path(_ shape: NodeShape, _ r: CGRect, grow: CGFloat = 0) -> NSBezierPath {
        let f = r.insetBy(dx: -grow, dy: -grow)
        switch shape {
        case .rounded: return NSBezierPath(roundedRect: f, xRadius: 7 + grow, yRadius: 7 + grow)
        case .rect: return NSBezierPath(roundedRect: f, xRadius: 1.5 + grow, yRadius: 1.5 + grow)
        case .pill:
            let rad = min(f.height / 2, 26 + grow)
            return NSBezierPath(roundedRect: f, xRadius: rad, yRadius: rad)
        case .ellipse: return NSBezierPath(ovalIn: f)
        case .hexagon:
            let cut = min(18 + grow, f.height / 2)
            let p = NSBezierPath()
            p.move(to: CGPoint(x: f.minX + cut, y: f.minY))
            p.line(to: CGPoint(x: f.maxX - cut, y: f.minY))
            p.line(to: CGPoint(x: f.maxX, y: f.midY))
            p.line(to: CGPoint(x: f.maxX - cut, y: f.maxY))
            p.line(to: CGPoint(x: f.minX + cut, y: f.maxY))
            p.line(to: CGPoint(x: f.minX, y: f.midY))
            p.close()
            p.lineJoinStyle = .round
            return p
        }
    }

    private static func display(_ n: TreeNode, goal: Bool) -> (text: String, pending: Bool) {
        guard goal else { return (n.text.isEmpty ? L("(kosong)") : n.text, n.text.isEmpty) }
        if n.obj.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (L("Belum dirumuskan: ") + n.text, true) }
        return (n.obj, false)
    }

    static func accessibilityLabel(_ n: TreeNode, side: Side, depth: Int, goal: Bool, levels: [String: LevelStyle] = [:]) -> String {
        let aspek = n.aspekValue.map { ", \($0.label)" } ?? ""
        return kindLabel(side: side, depth: depth, goal: goal, levels: levels) + aspek + ": " + display(n, goal: goal).text
    }

    private static func attributed(_ n: TreeNode, side: Side, goal: Bool) -> NSAttributedString {
        let d = display(n, goal: goal)
        var color: NSColor = side == .core ? .white : .labelColor
        if d.pending { color = side == .core ? NSColor.white.withAlphaComponent(0.78) : .secondaryLabelColor }
        var font = side == .core ? coreFont : bodyFont
        if d.pending { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.lineHeightMultiple = side == .core ? 1.05 : 1.08
        return NSAttributedString(string: d.text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }

    private static func height(_ n: TreeNode, side: Side, goal: Bool, shape: NodeShape) -> CGFloat {
        let s = attributed(n, side: side, goal: goal)
        let ins = inset(shape)
        let width = (side == .core ? TreeLayout.coreWidth - corePadX * 2 : TreeLayout.nodeWidth - padX * 2) - ins.x * 2
        let h = ceil(s.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        return (side == .core ? corePadY * 2 + metaHeight + h : padTop + metaHeight + h + padBottom) + ins.y * 2
    }

    static func layout(tree: PolicyTree, goal: Bool) -> TreeLayout {
        TreeLayout.compute(tree: tree) { n, side, depth in
            height(n, side: side, goal: goal, shape: tree.level(side: side, depth: depth).shapeValue)
        }
    }

    static func addButtons(for item: TreeLayout.Item) -> [(rect: CGRect, side: Side)] {
        let d: CGFloat = 24, gap: CGFloat = 10, f = item.frame
        let up = CGRect(x: f.midX - d / 2, y: f.minY - gap - d, width: d, height: d)
        let down = CGRect(x: f.midX - d / 2, y: f.maxY + gap, width: d, height: d)
        switch item.side {
        case .core: return [(up, .effect), (down, .cause)]
        case .effect: return [(up, .effect)]
        case .cause: return [(down, .cause)]
        }
    }

    static func draw(_ layout: TreeLayout, goal: Bool, selection: String?, focused: Bool = false, dirty: CGRect? = nil) {
        for b in layout.bands { drawBand(b, goal: goal) }
        drawEdges(layout)
        for item in layout.items where dirty == nil || item.frame.insetBy(dx: -40, dy: -40).intersects(dirty!) {
            drawNode(item, goal: goal, levels: layout.levels)
        }
        if let id = selection, let item = layout.item(id: id) {
            drawSelection(item, shape: style(layout, item).shapeValue, focused: focused)
        }
    }

    private static func style(_ layout: TreeLayout, _ item: TreeLayout.Item) -> LevelStyle {
        layout.levels[PolicyTree.levelKey(side: item.side, depth: item.depth)] ?? LevelStyle()
    }

    private static func drawBand(_ b: TreeLayout.Band, goal: Bool) {
        Palette.band.setFill()
        NSBezierPath(roundedRect: b.rect, xRadius: 6, yRadius: 6).fill()
        let label: String
        switch b.side {
        case .effect: label = goal ? L("MANFAAT") : L("DAMPAK")
        case .core: label = goal ? L("TUJUAN") : L("INTI")
        case .cause: label = goal ? L("SARANA") : L("PENYEBAB")
        }
        let s = NSAttributedString(string: label, attributes: [.font: bandFont, .foregroundColor: NSColor.secondaryLabelColor, .kern: 1.4])
        let size = s.size()
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: b.rect.midX, yBy: b.rect.midY)
        t.rotate(byDegrees: -90)
        t.concat()
        s.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawEdges(_ layout: TreeLayout) {
        Palette.edge.set()
        for pts in layout.edges {
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.move(to: pts[0])
            for p in pts.dropFirst().dropLast() { path.line(to: p) }
            let tip = pts[pts.count - 1]
            path.line(to: CGPoint(x: tip.x, y: tip.y + 6))
            path.stroke()
            let head = NSBezierPath()
            head.move(to: tip)
            head.line(to: CGPoint(x: tip.x - 4.5, y: tip.y + 8))
            head.line(to: CGPoint(x: tip.x + 4.5, y: tip.y + 8))
            head.close()
            head.fill()
        }
    }

    private static func drawNode(_ item: TreeLayout.Item, goal: Bool, levels: [String: LevelStyle]) {
        let st = levels[PolicyTree.levelKey(side: item.side, depth: item.depth)] ?? LevelStyle()
        let form = st.shapeValue
        let accent = Palette.levelColor(st, side: item.side, goal: goal)
        let ins = inset(form)
        let f = item.frame
        let shape = path(form, f)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.set()
        (item.side == .core ? accent : Palette.card).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        if item.side == .core {
            let x = f.minX + corePadX + ins.x, y = f.minY + corePadY + ins.y
            let meta = NSAttributedString(string: kindLabel(side: .core, depth: 0, goal: goal, levels: levels).uppercased(),
                                          attributes: [.font: metaFont, .foregroundColor: NSColor.white.withAlphaComponent(0.8), .kern: 0.5])
            meta.draw(with: CGRect(x: x, y: y, width: f.maxX - corePadX - ins.x - x, height: metaHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            drawText(item, goal: goal, in: CGRect(x: x, y: y + metaHeight, width: f.width - (corePadX + ins.x) * 2, height: f.height))
            return
        }

        if st.color != nil {
            // A light wash of a chosen colour makes the level readable at a glance.
            accent.withAlphaComponent(0.09).setFill()
            shape.fill()
        }
        let line = path(form, f.insetBy(dx: 0.5, dy: 0.5))
        if form == .rounded || form == .rect || form == .pill {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            accent.setFill()
            let barY = item.side == .effect ? f.minY : f.maxY - 3
            NSBezierPath(rect: CGRect(x: f.minX, y: barY, width: f.width, height: 3)).fill()
            NSGraphicsContext.restoreGraphicsState()
            Palette.cardLine.setStroke()
            line.lineWidth = 1
        } else {
            // A bar would be clipped to a sliver on slanted or curved edges, so the outline carries the colour.
            accent.setStroke()
            line.lineWidth = 2
        }
        line.stroke()

        var x = f.minX + padX + ins.x
        let right = f.maxX - padX - ins.x
        let metaY = f.minY + padTop + ins.y
        let a = item.node.aspekValue
        if let a {
            Palette.color(a).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: metaY + 3.5, width: 8, height: 8)).fill()
            x += 13
        }
        // A level the user named shows that name; otherwise the aspect, as before.
        let metaText = st.name != nil && !goal || st.goalName != nil && goal
            ? kindLabel(side: item.side, depth: item.depth, goal: goal, levels: levels)
            : a?.label ?? kindLabel(side: item.side, depth: item.depth, goal: goal, levels: levels)
        var badgeSize = CGSize.zero
        var badge: NSAttributedString?
        let badgeColor = accent
        if item.isRootCause {
            let b = NSAttributedString(string: goal ? L("INTERVENSI") : L("AKAR"), attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium), .foregroundColor: badgeColor, .kern: 0.6])
            badge = b
            badgeSize = CGSize(width: b.size().width + 8, height: 14)
        }
        let meta = NSAttributedString(string: metaText, attributes: [.font: metaFont, .foregroundColor: NSColor.secondaryLabelColor])
        let room = right - x - (badge == nil ? 0 : badgeSize.width + 7)
        let metaW = min(meta.size().width, max(room, 20))
        meta.draw(with: CGRect(x: x, y: metaY, width: metaW + 1, height: metaHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        x += metaW + 7
        if let badge {
            let r = CGRect(x: x, y: metaY + 0.5, width: badgeSize.width, height: badgeSize.height)
            badgeColor.setStroke()
            let b = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            b.lineWidth = 1
            b.stroke()
            badge.draw(at: CGPoint(x: r.minX + 4, y: r.midY - badge.size().height / 2))
        }
        drawText(item, goal: goal, in: CGRect(x: f.minX + padX + ins.x, y: metaY + metaHeight, width: f.width - (padX + ins.x) * 2, height: f.height))
    }

    private static func drawText(_ item: TreeLayout.Item, goal: Bool, in rect: CGRect) {
        attributed(item.node, side: item.side, goal: goal).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private static func drawSelection(_ item: TreeLayout.Item, shape: NodeShape, focused: Bool) {
        (focused ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
        let ring = path(shape, item.frame, grow: 3.5)
        ring.lineWidth = 2.5
        ring.stroke()
        for b in addButtons(for: item) {
            let circle = NSBezierPath(ovalIn: b.rect)
            Palette.card.setFill()
            circle.fill()
            Palette.edge.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            NSColor.labelColor.setStroke()
            let plus = NSBezierPath()
            plus.lineWidth = 1.8
            plus.lineCapStyle = .round
            plus.move(to: CGPoint(x: b.rect.midX - 5, y: b.rect.midY))
            plus.line(to: CGPoint(x: b.rect.midX + 5, y: b.rect.midY))
            plus.move(to: CGPoint(x: b.rect.midX, y: b.rect.midY - 5))
            plus.line(to: CGPoint(x: b.rect.midX, y: b.rect.midY + 5))
            plus.stroke()
        }
    }
}

/// The whole tree with a title line, drawn off-screen for PNG, PDF and printing.
final class ExportView: NSView {
    private let tree: PolicyTree
    private let goal: Bool
    private let treeLayout: TreeLayout
    private static let header: CGFloat = 70
    override var isFlipped: Bool { true }

    init(tree: PolicyTree, goal: Bool) {
        self.tree = tree
        self.goal = goal
        treeLayout = TreeRenderer.layout(tree: tree, goal: goal)
        let size = CGSize(width: max(treeLayout.size.width, 560), height: treeLayout.size.height + Self.header)
        super.init(frame: CGRect(origin: .zero, size: size))
        appearance = NSAppearance(named: .aqua)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let eyebrow = NSAttributedString(string: goal ? L("POHON TUJUAN") : L("POHON MASALAH"), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor, .kern: 1.2])
        eyebrow.draw(at: CGPoint(x: 24, y: 18))
        let base = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 22) } ?? base
        NSAttributedString(string: tree.title, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            .draw(with: CGRect(x: 24, y: 34, width: bounds.width - 48, height: 32), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.translateBy(x: (bounds.width - treeLayout.size.width) / 2, y: Self.header)
        TreeRenderer.draw(treeLayout, goal: goal, selection: nil)
        cg.restoreGState()
    }

    func pngData(scale: CGFloat = 2, appearanceName: NSAppearance.Name = .aqua) -> Data? {
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = gc.cgContext
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: bounds.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        (NSAppearance(named: appearanceName) ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance { draw(bounds) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    func pdfData() -> Data { dataWithPDF(inside: bounds) }
}
