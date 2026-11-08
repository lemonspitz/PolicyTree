import AppKit

/// Wrapping label that re-measures itself when its width changes inside a stack.
final class WrapLabel: NSTextField {
    convenience init(_ text: String, size: CGFloat = 12, color: NSColor = .secondaryLabelColor, weight: NSFont.Weight = .regular) {
        self.init(wrappingLabelWithString: text)
        font = .systemFont(ofSize: size, weight: weight)
        textColor = color
        isSelectable = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    override func layout() {
        super.layout()
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}

/// Text box whose edits go only through the document's undo. Letting NSTextView keep its
/// own undo on the same manager makes the two histories fight, so allowsUndo stays false.
final class EditorField: NSView, NSTextViewDelegate {
    private final class Inner: NSTextView {
        weak var owner: EditorField?
        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            if ok { owner?.focusChanged(true) }
            return ok
        }
        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            if ok { owner?.focusChanged(false) }
            return ok
        }
    }

    private let textView = Inner(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
    private let scroll = NSScrollView()
    var onChange: ((String) -> Void)?
    var onBeginEditing: (() -> Void)?
    var onTab: (() -> Void)?
    var onBacktab: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    init(height: CGFloat, font: NSFont = .systemFont(ofSize: 13), label: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        textView.owner = self
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = false
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.minSize = NSSize(width: 0, height: height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.setAccessibilityLabel(label)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
        focusChanged(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var focused = false

    fileprivate func focusChanged(_ focused: Bool) {
        self.focused = focused
        updateBorder()
        if focused { onBeginEditing?() }
    }

    private func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (focused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
        layer?.borderWidth = focused ? 2 : 1
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    var string: String {
        get { textView.string }
        set { if textView.string != newValue { textView.string = newValue } }
    }

    func focus(selectAll: Bool) {
        window?.makeFirstResponder(textView)
        if selectAll { textView.selectAll(nil) }
    }

    func textDidChange(_ notification: Notification) { onChange?(textView.string) }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let handler: (() -> Void)?
        switch selector {
        case #selector(NSResponder.insertTab(_:)): handler = onTab
        case #selector(NSResponder.insertBacktab(_:)): handler = onBacktab
        case #selector(NSResponder.insertNewline(_:)): handler = onReturn
        case #selector(NSResponder.cancelOperation(_:)): handler = onEscape
        default: return false
        }
        guard let handler else { return true }
        handler()
        return true
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Drawn rather than layer-backed so a dynamic colour follows light/dark switches.
private final class Swatch: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }
    var radius: CGFloat = 2
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}

private final class BarRow: NSView {
    private let label: String, count: Int, fraction: CGFloat, color: NSColor
    init(label: String, count: Int, fraction: CGFloat, color: NSColor) {
        self.label = label; self.count = count; self.fraction = fraction; self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(label): \(count)")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let labelW: CGFloat = 104, countW: CGFloat = 22
        NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            .draw(with: CGRect(x: 0, y: 2, width: labelW, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        let track = CGRect(x: labelW + 6, y: 6, width: max(0, bounds.width - labelW - countW - 12), height: 7)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3.5, yRadius: 3.5).fill()
        color.setFill()
        var fill = track; fill.size.width = max(7, track.width * fraction)
        NSBezierPath(roundedRect: fill, xRadius: 3.5, yRadius: 3.5).fill()
        let n = NSAttributedString(string: "\(count)", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
        n.draw(at: CGPoint(x: bounds.width - n.size().width, y: 1))
    }
}

/// One root cause in the summary; clicking selects it on the canvas.
private final class RootRow: NSView {
    private let action: () -> Void
    private let text: String
    init(text: String, color: NSColor, action: @escaping () -> Void) {
        self.action = action
        self.text = text
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let dot = Swatch()
        dot.color = color
        dot.radius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        let label = WrapLabel(text, size: 12.5, color: .labelColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot); addSubview(label)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor), dot.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseUp(with event: NSEvent) { action() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { text }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}

final class InspectorController: NSViewController {
    weak var owner: PolicyWindowController?

    private let stack = NSStackView()
    private let titleEditor = EditorField(height: 44, font: .systemFont(ofSize: 13, weight: .medium), label: L("Judul analisis"))
    private let swatch = Swatch()
    private let kindLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(labelWithString: "")
    private let textEditor = EditorField(height: 84, label: L("Rumusan"))
    private let textHint = WrapLabel("")
    private let objEditor = EditorField(height: 64, label: L("Rumusan tujuan"))
    private let aspekRow = NSStackView()
    private let aspekPopup = NSPopUpButton()
    private let addEffectButton = NSButton(title: "", target: nil, action: nil)
    private let addChildButton = NSButton(title: "", target: nil, action: nil)
    private let addSiblingButton = NSButton(title: L("Sejajar"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L("Hapus"), target: nil, action: nil)
    private let summary = NSStackView()
    private var summarySignature = ""
    private let levelScope = WrapLabel("")
    private let levelNameLabel = NSTextField(labelWithString: "")
    private let levelNameEditor = EditorField(height: 28, label: L("Nama level"))
    private let levelNameHint = WrapLabel("", size: 11)
    private let colorWell = NSColorWell(style: .minimal)
    private let colorDefaultButton = NSButton(title: L("Warna bawaan"), target: nil, action: nil)
    private let shapePopup = NSPopUpButton()
    private let levelResetButton = NSButton(title: L("Kembalikan gaya bawaan level ini"), target: nil, action: nil)
    private var shownLevel: (side: Side, depth: Int) = (.core, 0)
    private var shownLevelKey = ""
    private var shownGoal = false
    private let keyHints = WrapLabel(L("Di kanvas: Tab menambah turunan, Return menambah sejajar, Delete menghapus, tombol panah berpindah simpul. Di kotak teks: Tab dan Return bekerja sama, Esc kembali ke kanvas, Shift-Return membuat baris baru."), size: 11)

    private func heading(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        l.textColor = .secondaryLabelColor
        return l
    }
    private func fieldLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        return l
    }
    private func addFull(_ v: NSView, spacingAfter: CGFloat? = nil) {
        v.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        if let spacingAfter { stack.setCustomSpacing(spacingAfter, after: v) }
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        ])

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
        ])

        addFull(fieldLabel(L("Judul analisis")))
        addFull(titleEditor, spacingAfter: 22)

        addFull(heading(L("Simpul terpilih")), spacingAfter: 8)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: 12).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let serif = NSFont.systemFont(ofSize: 18, weight: .semibold)
        kindLabel.font = serif.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 18) } ?? serif
        let kindRow = NSStackView(views: [swatch, kindLabel])
        kindRow.spacing = 8
        addFull(kindRow, spacingAfter: 12)

        textLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        addFull(textLabel)
        addFull(textEditor)
        addFull(textHint, spacingAfter: 14)

        addFull(fieldLabel(L("Rumusan tujuan (untuk pohon tujuan)")))
        addFull(objEditor)
        let suggest = NSButton(title: L("Usulkan dari rumusan masalah"), target: self, action: #selector(suggestTapped))
        suggest.controlSize = .small
        stack.addArrangedSubview(suggest)
        stack.setCustomSpacing(14, after: suggest)

        aspekPopup.addItem(withTitle: L("Belum ditentukan"))
        aspekPopup.lastItem?.representedObject = ""
        for a in Aspek.allCases {
            aspekPopup.addItem(withTitle: a.label)
            aspekPopup.lastItem?.representedObject = a.rawValue
        }
        aspekPopup.target = self
        aspekPopup.action = #selector(aspekChanged)
        aspekPopup.setAccessibilityLabel(L("Aspek kebijakan"))
        aspekRow.addArrangedSubview(fieldLabel(L("Aspek kebijakan")))
        aspekRow.addArrangedSubview(aspekPopup)
        aspekRow.spacing = 8
        addFull(aspekRow, spacingAfter: 14)

        addEffectButton.target = self; addEffectButton.action = #selector(addEffectTapped); addEffectButton.title = L("+ Dampak")
        addChildButton.target = self; addChildButton.action = #selector(addChildTapped)
        addSiblingButton.target = self; addSiblingButton.action = #selector(addSiblingTapped)
        deleteButton.target = self; deleteButton.action = #selector(deleteTapped)
        deleteButton.contentTintColor = .systemRed
        for b in [addEffectButton, addChildButton, addSiblingButton, deleteButton] { b.controlSize = .small }
        let buttons = NSStackView(views: [addEffectButton, addChildButton, addSiblingButton, deleteButton])
        buttons.spacing = 6
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(8, after: buttons)
        addFull(keyHints, spacingAfter: 22)
        keyHints.isHidden = !Prefs.showKeyHints
        NotificationCenter.default.addObserver(forName: Prefs.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyHints.isHidden = !Prefs.showKeyHints }
        }
        addFull(heading(L("Gaya level")), spacingAfter: 6)
        addFull(levelScope, spacingAfter: 10)
        levelNameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        addFull(levelNameLabel)
        addFull(levelNameEditor)
        addFull(levelNameHint, spacingAfter: 10)

        colorWell.target = self
        colorWell.action = #selector(levelColorChanged)
        colorWell.setAccessibilityLabel(L("Warna level"))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorDefaultButton.target = self
        colorDefaultButton.action = #selector(levelColorDefault)
        colorDefaultButton.controlSize = .small
        let colorLabel = fieldLabel(L("Warna"))
        colorLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let colorRow = NSStackView(views: [colorLabel, colorWell, colorDefaultButton])
        colorRow.spacing = 8
        addFull(colorRow, spacingAfter: 8)

        for sh in NodeShape.allCases {
            shapePopup.addItem(withTitle: sh.label)
            shapePopup.lastItem?.representedObject = sh.rawValue
            shapePopup.lastItem?.image = Self.shapeIcon(sh)
        }
        shapePopup.target = self
        shapePopup.action = #selector(levelShapeChanged)
        shapePopup.setAccessibilityLabel(L("Bentuk level"))
        let shapeLabel = fieldLabel(L("Bentuk"))
        shapeLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let shapeRow = NSStackView(views: [shapeLabel, shapePopup])
        shapeRow.spacing = 8
        addFull(shapeRow, spacingAfter: 8)

        levelResetButton.target = self
        levelResetButton.action = #selector(levelReset)
        levelResetButton.controlSize = .small
        stack.addArrangedSubview(levelResetButton)
        stack.setCustomSpacing(26, after: levelResetButton)


        summary.orientation = .vertical
        summary.alignment = .leading
        summary.spacing = 6
        addFull(summary)

        view = scroll
        wire()
    }

    private func wire() {
        titleEditor.onBeginEditing = { [weak self] in self?.owner?.policyDocument?.endCoalescing() }
        titleEditor.onChange = { [weak self] s in
            self?.owner?.policyDocument?.apply(L("Ubah Judul"), coalesce: "title") { $0.title = s }
        }
        let backToCanvas: () -> Void = { [weak self] in self?.owner?.focusCanvas() }
        titleEditor.onReturn = backToCanvas
        titleEditor.onTab = backToCanvas
        titleEditor.onEscape = backToCanvas

        for (editor, key) in [(textEditor, "text"), (objEditor, "obj")] {
            editor.onBeginEditing = { [weak self] in self?.owner?.policyDocument?.endCoalescing() }
            editor.onChange = { [weak self] s in
                guard let doc = self?.owner?.policyDocument else { return }
                let id = doc.selection
                doc.apply(key == "text" ? L("Ubah Rumusan") : L("Ubah Tujuan"), coalesce: "\(key):\(id)") { t in
                    t.update(id) { if key == "text" { $0.text = s } else { $0.obj = s } }
                }
            }
            editor.onEscape = backToCanvas
            editor.onTab = { [weak self] in
                guard let o = self?.owner, let doc = o.policyDocument else { return }
                o.add(under: doc.selection, coreSide: .cause)
            }
            editor.onBacktab = { [weak self] in
                guard let o = self?.owner, let doc = o.policyDocument, doc.selection == PolicyTree.coreID else { return }
                o.add(under: PolicyTree.coreID, coreSide: .effect)
            }
            editor.onReturn = { [weak self] in
                guard let o = self?.owner, let doc = o.policyDocument else { return }
                if doc.selection == PolicyTree.coreID { o.focusCanvas() } else { o.addSibling(nil) }
            }
        }

        levelNameEditor.onBeginEditing = { [weak self] in self?.owner?.policyDocument?.endCoalescing() }
        levelNameEditor.onChange = { [weak self] s in
            guard let self else { return }
            let goal = self.shownGoal
            self.editLevel(L("Ubah Nama Level"), coalesce: "levelname:\(goal):\(self.shownLevelKey)") {
                if goal { $0.goalName = s } else { $0.name = s }
            }
        }
        levelNameEditor.onReturn = backToCanvas
        levelNameEditor.onTab = backToCanvas
        levelNameEditor.onEscape = backToCanvas
    }

    static func shapeIcon(_ sh: NodeShape) -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 13), flipped: true) { r in
            let f = r.insetBy(dx: 1.5, dy: 1.5)
            let p: NSBezierPath
            switch sh {
            case .rounded: p = NSBezierPath(roundedRect: f, xRadius: 3, yRadius: 3)
            case .rect: p = NSBezierPath(rect: f)
            case .pill: p = NSBezierPath(roundedRect: f, xRadius: f.height / 2, yRadius: f.height / 2)
            case .ellipse: p = NSBezierPath(ovalIn: f)
            case .hexagon: p = TreeRenderer.path(.hexagon, f)
            }
            NSColor.black.setStroke()
            p.lineWidth = 1.3
            p.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    private func editLevel(_ name: String, coalesce: String? = nil, _ body: @escaping (inout LevelStyle) -> Void) {
        guard let doc = owner?.policyDocument else { return }
        let lv = shownLevel
        doc.apply(name, coalesce: coalesce) { $0.updateLevel(side: lv.side, depth: lv.depth, body) }
    }
    @objc private func levelColorChanged() {
        let hex = Palette.hexString(colorWell.color)
        editLevel(L("Ubah Warna Level"), coalesce: "levelcolor:\(shownLevelKey)") { $0.color = hex }
    }
    @objc private func levelColorDefault() {
        colorWell.deactivate()
        editLevel(L("Ubah Warna Level")) { $0.color = nil }
    }
    @objc private func levelShapeChanged() {
        guard let raw = shapePopup.selectedItem?.representedObject as? String else { return }
        editLevel(L("Ubah Bentuk Level")) { $0.shape = raw == NodeShape.rounded.rawValue ? nil : raw }
    }
    @objc private func levelReset() {
        colorWell.deactivate()
        editLevel(L("Kembalikan Gaya Level")) { $0 = LevelStyle() }
    }

    @objc private func suggestTapped() { owner?.suggestObjective(nil) }
    @objc private func aspekChanged() {
        guard let raw = aspekPopup.selectedItem?.representedObject as? String, let doc = owner?.policyDocument else { return }
        let id = doc.selection
        doc.apply(L("Ubah Aspek")) { t in t.update(id) { $0.aspek = raw } }
    }
    @objc private func addEffectTapped() { owner?.add(under: PolicyTree.coreID, coreSide: .effect) }
    @objc private func addChildTapped() { owner?.addChild(nil) }
    @objc private func addSiblingTapped() { owner?.addSibling(nil) }
    @objc private func deleteTapped() { owner?.deleteNode(nil) }

    func focusEditor(goal: Bool, selectAll: Bool) {
        (goal ? objEditor : textEditor).focus(selectAll: selectAll)
    }

    func reload(goal: Bool) {
        _ = view
        guard let doc = owner?.policyDocument, let node = doc.tree.node(doc.selection), let loc = doc.tree.location(of: doc.selection) else { return }
        let tree = doc.tree

        titleEditor.string = tree.title
        textEditor.string = node.text
        objEditor.string = node.obj

        let st = tree.level(side: loc.side, depth: loc.depth)
        let color = Palette.levelColor(st, side: loc.side, goal: goal)
        swatch.color = color
        swatch.radius = st.shapeValue == .ellipse || st.shapeValue == .pill ? 6 : 2
        kindLabel.stringValue = TreeRenderer.kindLabel(side: loc.side, depth: loc.depth, goal: goal, levels: tree.levels)
        reloadLevel(tree, side: loc.side, depth: loc.depth, goal: goal, color: color)

        switch loc.side {
        case .core:
            textLabel.stringValue = L("Rumusan masalah inti")
            textHint.stringValue = L("Satu kondisi negatif yang ingin diatasi kebijakan. Hindari menulis solusi, misalnya \"kurangnya program X\".")
            addChildButton.title = L("+ Penyebab")
        case .effect:
            textLabel.stringValue = L("Rumusan dampak")
            textHint.stringValue = L("Akibat yang muncul bila masalah di bawahnya dibiarkan.")
            addChildButton.title = L("+ Dampak lanjutan")
        case .cause:
            textLabel.stringValue = L("Rumusan penyebab")
            textHint.stringValue = L("Mengapa masalah di atasnya terjadi? Tulis sebagai kondisi negatif.")
            addChildButton.title = L("+ Sub-penyebab")
        }
        let isCore = loc.side == .core
        aspekRow.isHidden = isCore
        addEffectButton.isHidden = !isCore
        addSiblingButton.isHidden = isCore
        deleteButton.isHidden = isCore
        if let i = aspekPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == node.aspek }) {
            aspekPopup.selectItem(at: i)
        } else { aspekPopup.selectItem(at: 0) }

        reloadSummary(tree, goal: goal)
    }

    private func reloadLevel(_ tree: PolicyTree, side: Side, depth: Int, goal: Bool, color: NSColor) {
        let key = PolicyTree.levelKey(side: side, depth: depth)
        if key != shownLevelKey || goal != shownGoal {
            // The colour panel would otherwise keep painting the level that was selected before.
            colorWell.deactivate()
        }
        shownLevel = (side, depth)
        shownLevelKey = key
        shownGoal = goal
        let st = tree.level(side: side, depth: depth)
        let builtIn = TreeRenderer.defaultKindLabel(side: side, depth: depth, goal: goal)
        let count = tree.nodeCount(side: side, depth: depth)
        levelScope.stringValue = side == .core
            ? (goal ? L("Mengatur tampilan kotak tujuan utama.") : L("Mengatur tampilan kotak masalah inti."))
            : L("Berlaku untuk {0} simpul di {1}.", count, builtIn.lowercased())
        levelNameLabel.stringValue = goal ? L("Nama level di pohon tujuan") : L("Nama level di pohon masalah")
        levelNameEditor.string = (goal ? st.goalName : st.name) ?? ""
        levelNameHint.stringValue = L("Kosongkan untuk memakai nama bawaan \"{0}\". Nama ini tampil di setiap kotak pada level ini.", builtIn)
        if !colorWell.isActive { colorWell.color = color }
        colorDefaultButton.isEnabled = st.color != nil
        if let i = shapePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == st.shapeValue.rawValue }) {
            shapePopup.selectItem(at: i)
        }
        levelResetButton.isEnabled = !st.isEmpty
    }

    private func reloadSummary(_ tree: PolicyTree, goal: Bool) {
        let roots = tree.rootCauses
        func rootText(_ n: TreeNode) -> String { goal ? (n.obj.isEmpty ? PolicyTreeApp.suggestObjective(n.text) : n.obj) : n.text }
        let counts = tree.aspekCounts
        let signature = "\(goal)|\(tree.effectCount)|\(tree.causeCount)|\(tree.causeDepth)|" +
            Aspek.allCases.map { "\(counts[$0] ?? 0)" }.joined(separator: ",") + "|\(counts[nil] ?? 0)|" +
            roots.map { $0.id + ":" + $0.aspek + ":" + rootText($0) }.joined(separator: "\u{1F}")
        guard signature != summarySignature else { return }
        summarySignature = signature

        summary.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func add(_ v: NSView, after: CGFloat? = nil) {
            v.translatesAutoresizingMaskIntoConstraints = false
            summary.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: summary.widthAnchor).isActive = true
            if let after { summary.setCustomSpacing(after, after: v) }
        }
        add(heading(L("Ringkasan analisis")), after: 8)

        let stats: [(Int, String)] = [
            (tree.effectCount, goal ? L("Manfaat|jumlah") : L("Dampak|jumlah")),
            (tree.causeCount, goal ? L("Sarana|jumlah") : L("Penyebab|jumlah")),
            (roots.count, goal ? L("Intervensi") : L("Akar masalah")),
            (tree.causeDepth, L("Kedalaman")),
        ]
        let statRow = NSStackView(views: stats.map { value, caption in
            let v = NSTextField(labelWithString: "\(value)")
            let serif = NSFont.systemFont(ofSize: 22, weight: .semibold)
            v.font = serif.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 22) } ?? serif
            let c = WrapLabel(caption, size: 10.5)
            let box = NSStackView(views: [v, c])
            box.orientation = .vertical
            box.alignment = .leading
            box.spacing = 0
            box.setAccessibilityElement(true)
            box.setAccessibilityLabel("\(caption): \(value)")
            return box
        })
        statRow.distribution = .fillEqually
        statRow.alignment = .top
        statRow.spacing = 6
        add(statRow, after: 14)

        if tree.causeCount > 0 {
            add(WrapLabel(goal ? L("Sebaran sarana per aspek kebijakan") : L("Sebaran penyebab per aspek kebijakan")), after: 4)
            let top = CGFloat(counts.values.max() ?? 1)
            let rows: [Aspek?] = Aspek.allCases.map { Optional($0) } + [nil]
            for a in rows {
                guard let n = counts[a], n > 0 else { continue }
                add(BarRow(label: a?.label ?? L("Belum ditentukan"), count: n, fraction: CGFloat(n) / top, color: Palette.color(a)))
            }
            if let last = summary.arrangedSubviews.last { summary.setCustomSpacing(14, after: last) }
        }

        add(WrapLabel(goal ? L("Titik intervensi kebijakan (sarana paling dasar). Klik untuk memilih.") : L("Akar masalah, yaitu penyebab paling dasar yang menjadi titik intervensi. Klik untuk memilih.")), after: 4)
        if roots.isEmpty {
            add(WrapLabel(L("Belum ada penyebab.")))
        }
        for n in roots {
            let id = n.id
            add(RootRow(text: rootText(n), color: Palette.color(n.aspekValue)) { [weak self] in
                self?.owner?.select(id)
                self?.owner?.revealSelection()
            })
        }
    }
}
