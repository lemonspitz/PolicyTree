import AppKit
import UniformTypeIdentifiers

private extension NSToolbarItem.Identifier {
    static let viewMode = Self("viewMode")
    static let addChild = Self("addChild")
    static let addSibling = Self("addSibling")
    static let deleteNode = Self("deleteNode")
    static let zoomFit = Self("zoomFit")
    static let export = Self("export")
}

final class PolicyWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    private let treeView = TreeView()
    private let scrollView = NSScrollView()
    private let inspector = InspectorController()
    private weak var modeGroup: NSToolbarItemGroup?
    private static let goalKey = "tampilanPohonTujuan"
    private(set) var goalView = UserDefaults.standard.bool(forKey: goalKey)

    private(set) weak var policyDocument: PolicyDocument?

    init(document: PolicyDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 480)
        // NSDocument matches restored window state by this identifier; without it a relaunch
        // reopens the document but never shows its window.
        window.identifier = NSUserInterfaceItemIdentifier("PolicyDocumentWindow")
        policyDocument = document
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true

        let clip = CenteringClipView()
        clip.drawsBackground = true
        clip.backgroundColor = Palette.canvas
        scrollView.contentView = clip
        scrollView.documentView = treeView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.3
        scrollView.maxMagnification = 2
        scrollView.backgroundColor = Palette.canvas
        treeView.controller = self
        inspector.owner = self

        let canvasVC = NSViewController()
        canvasVC.view = scrollView
        let split = NSSplitViewController()
        let canvasItem = NSSplitViewItem(viewController: canvasVC)
        canvasItem.minimumThickness = 360
        split.addSplitViewItem(canvasItem)
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 300
        inspectorItem.maximumThickness = 440
        inspectorItem.preferredThicknessFraction = 0.27
        split.addSplitViewItem(inspectorItem)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1240, height: 780))
        window.center()

        let toolbar = NSToolbar(identifier: "PolicyTreeToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // NSDocument.addWindowController assigns `document`; setting it here makes AppKit drop this controller.
        refresh()
    }

    /// Fits once, when the window is really on screen: before that the split view has no final
    /// size. Showing the window again later must not undo the user's own zoom.
    private var didInitialFit = false
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !didInitialFit else { return }
        didInitialFit = true
        window?.layoutIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.window?.layoutIfNeeded()
            self?.zoomFit(nil)
            self?.focusCanvas()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { policyDocument?.undoManager }
    func windowDidBecomeKey(_ notification: Notification) { treeView.needsDisplay = true }
    func windowDidResignKey(_ notification: Notification) { treeView.needsDisplay = true }

    func refresh() {
        guard let doc = policyDocument else { return }
        treeView.reload(tree: doc.tree, selection: doc.selection, goal: goalView)
        inspector.reload(goal: goalView)
        modeGroup?.selectedIndex = goalView ? 1 : 0
    }

    // MARK: Selection and focus

    func select(_ id: String) { policyDocument?.select(id) }
    func revealSelection() { treeView.scrollSelectionIntoView() }
    func focusCanvas() { window?.makeFirstResponder(treeView) }
    func focusEditor(selectAll: Bool = false) { inspector.focusEditor(goal: goalView, selectAll: selectAll) }

    private var editingText: Bool { window?.firstResponder is NSTextView }

    // MARK: Editing actions

    func add(under id: String, coreSide: Side) {
        guard let doc = policyDocument else { return }
        let name = id == PolicyTree.coreID ? (coreSide == .effect ? L("Tambah Dampak") : L("Tambah Penyebab")) : L("Tambah Simpul")
        doc.apply(name) { t in
            if let new = t.addChild(of: id, coreSide: coreSide) { doc.selection = new }
        }
        revealSelection()
        focusEditor(selectAll: true)
    }

    @objc func addChild(_ sender: Any?) {
        guard let doc = policyDocument else { return }
        add(under: doc.selection, coreSide: .cause)
    }

    @objc func addEffect(_ sender: Any?) { add(under: PolicyTree.coreID, coreSide: .effect) }

    @objc func addSibling(_ sender: Any?) {
        guard let doc = policyDocument, doc.selection != PolicyTree.coreID else { return }
        let id = doc.selection
        doc.apply(L("Tambah Simpul Sejajar")) { t in
            if let new = t.addSibling(after: id) { doc.selection = new }
        }
        revealSelection()
        focusEditor(selectAll: true)
    }

    @objc func deleteNode(_ sender: Any?) {
        guard let doc = policyDocument, doc.selection != PolicyTree.coreID else { return }
        let id = doc.selection
        doc.apply(L("Hapus Simpul")) { t in
            if let next = t.remove(id) { doc.selection = next }
        }
        focusCanvas()
    }

    @objc func moveNodeLeft(_ sender: Any?) { moveNode(-1) }
    @objc func moveNodeRight(_ sender: Any?) { moveNode(1) }
    private func moveNode(_ delta: Int) {
        guard let doc = policyDocument else { return }
        let id = doc.selection
        doc.apply(L("Geser Simpul")) { $0.move(id, by: delta) }
        revealSelection()
    }

    @objc func suggestObjective(_ sender: Any?) {
        guard let doc = policyDocument else { return }
        let id = doc.selection
        doc.apply(L("Usulkan Tujuan")) { t in
            let text = t.node(id)?.text ?? ""
            t.update(id) { $0.obj = PolicyTreeApp.suggestObjective(text) }
        }
    }

    @objc func suggestAllObjectives(_ sender: Any?) {
        policyDocument?.apply(L("Usulkan Semua Tujuan")) { $0.suggestAllObjectives() }
    }

    @objc func resetAllLevelStyles(_ sender: Any?) {
        policyDocument?.apply(L("Kembalikan Gaya Level")) { $0.levels = [:] }
    }

    @objc func setAspek(_ sender: NSMenuItem) {
        guard let doc = policyDocument, let raw = sender.representedObject as? String else { return }
        let id = doc.selection
        doc.apply(L("Ubah Aspek")) { t in t.update(id) { $0.aspek = raw } }
    }

    func contextMenu(for side: Side) -> NSMenu {
        let m = NSMenu()
        func item(_ t: String, _ a: Selector) { m.addItem(withTitle: t, action: a, keyEquivalent: "") }
        switch side {
        case .core:
            item(L("Tambah Penyebab"), #selector(addChild(_:)))
            item(L("Tambah Dampak"), #selector(addEffect(_:)))
        case .effect:
            item(L("Tambah Dampak Lanjutan"), #selector(addChild(_:)))
            item(L("Tambah Simpul Sejajar"), #selector(addSibling(_:)))
        case .cause:
            item(L("Tambah Sub-penyebab"), #selector(addChild(_:)))
            item(L("Tambah Simpul Sejajar"), #selector(addSibling(_:)))
        }
        m.addItem(.separator())
        item(L("Usulkan Rumusan Tujuan"), #selector(suggestObjective(_:)))
        if side != .core {
            let sub = NSMenu()
            let current = policyDocument.flatMap { $0.tree.node($0.selection)?.aspek } ?? ""
            let entries: [(String, String)] = [(L("Belum ditentukan"), "")] + Aspek.allCases.map { ($0.label, $0.rawValue) }
            for (label, raw) in entries {
                let it = sub.addItem(withTitle: label, action: #selector(setAspek(_:)), keyEquivalent: "")
                it.representedObject = raw
                it.state = raw == current ? .on : .off
            }
            let parent = m.addItem(withTitle: L("Aspek Kebijakan"), action: nil, keyEquivalent: "")
            parent.submenu = sub
            m.addItem(.separator())
            item(L("Geser ke Kiri"), #selector(moveNodeLeft(_:)))
            item(L("Geser ke Kanan"), #selector(moveNodeRight(_:)))
            m.addItem(.separator())
            item(L("Hapus Simpul"), #selector(deleteNode(_:)))
        }
        return m
    }

    // MARK: View actions

    private func setGoal(_ goal: Bool) {
        goalView = goal
        UserDefaults.standard.set(goal, forKey: Self.goalKey)
        refresh()
    }
    @objc func showProblemTree(_ sender: Any?) { setGoal(false) }
    @objc func showGoalTree(_ sender: Any?) { setGoal(true) }
    @objc private func modeChanged(_ sender: NSToolbarItemGroup) { setGoal(sender.selectedIndex == 1) }

    @objc func zoomInTree(_ sender: Any?) { scrollView.animator().magnification = min(2, scrollView.magnification * 1.2) }
    @objc func zoomOutTree(_ sender: Any?) { scrollView.animator().magnification = max(0.3, scrollView.magnification / 1.2) }
    @objc func zoomFit(_ sender: Any?) {
        let size = treeView.treeLayout.size
        guard size.width > 0, size.height > 0 else { return }
        scrollView.layoutSubtreeIfNeeded()
        let visible = scrollView.frame.size
        scrollView.magnification = max(0.3, min(1, (visible.width - 8) / size.width, (visible.height - 60) / size.height))
    }

    // MARK: Export

    private var exportBaseName: String {
        let t = policyDocument?.tree.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = t.isEmpty ? L("Pohon Masalah") : t
        return (goalView ? L("Pohon Tujuan - ") : L("Pohon Masalah - ")) + name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private func export(type: UTType, data: @escaping () -> Data?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = exportBaseName
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let d = data() else { throw CocoaError(.fileWriteUnknown) }
                try d.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    @objc func exportPNG(_ sender: Any?) {
        guard let doc = policyDocument else { return }
        let tree = doc.tree, goal = goalView
        export(type: .png) { ExportView(tree: tree, goal: goal).pngData(scale: Prefs.pngScale) }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let doc = policyDocument else { return }
        let tree = doc.tree, goal = goalView
        export(type: .pdf) { ExportView(tree: tree, goal: goal).pdfData() }
    }

    @objc func copyOutline(_ sender: Any?) {
        guard let doc = policyDocument else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(doc.tree.outline(goal: goalView), forType: .string)
    }

    // MARK: Validation

    private func validate(_ action: Selector?, item: NSMenuItem? = nil) -> Bool {
        guard let doc = policyDocument, let loc = doc.tree.location(of: doc.selection) else { return false }
        switch action {
        case #selector(addChild(_:)):
            switch loc.side {
            case .core: item?.title = L("Tambah Penyebab")
            case .effect: item?.title = L("Tambah Dampak Lanjutan")
            case .cause: item?.title = L("Tambah Sub-penyebab")
            }
            return true
        case #selector(addEffect(_:)): return loc.side == .core
        case #selector(addSibling(_:)): return loc.side != .core
        case #selector(deleteNode(_:)):
            // Falling through while typing leaves Command-Delete to the text box.
            return loc.side != .core && (item == nil || item?.menu?.supermenu == nil || !editingText)
        case #selector(moveNodeLeft(_:)): return loc.side != .core && loc.index > 0
        case #selector(moveNodeRight(_:)): return loc.side != .core && loc.index < loc.siblingCount - 1
        case #selector(resetAllLevelStyles(_:)): return !doc.tree.levels.isEmpty
        case #selector(showProblemTree(_:)): item?.state = goalView ? .off : .on; return true
        case #selector(showGoalTree(_:)): item?.state = goalView ? .on : .off; return true
        default: return true
        }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { validate(menuItem.action, item: menuItem) }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { validate(item.action) }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.viewMode, .flexibleSpace, .addChild, .addSibling, .deleteNode, .space, .zoomFit, .export, .inspectorTrackingSeparator, .flexibleSpace, .toggleInspector]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ label: String, _ symbol: String, _ action: Selector, tip: String) -> NSToolbarItem {
            let it = NSToolbarItem(itemIdentifier: id)
            it.label = label
            it.paletteLabel = label
            it.toolTip = tip
            it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            it.action = action
            it.isBordered = true
            return it
        }
        switch id {
        case .viewMode:
            let g = NSToolbarItemGroup(itemIdentifier: id, titles: [L("Pohon Masalah"), L("Pohon Tujuan")], selectionMode: .selectOne, labels: [L("Pohon Masalah"), L("Pohon Tujuan")], target: self, action: #selector(modeChanged(_:)))
            g.label = L("Tampilan")
            g.paletteLabel = L("Tampilan")
            g.selectedIndex = goalView ? 1 : 0
            modeGroup = g
            return g
        case .addChild:
            return button(L("Tambah Turunan"), "arrow.turn.down.right", #selector(addChild(_:)), tip: L("Tambah turunan pada simpul terpilih (Tab)"))
        case .addSibling:
            return button(L("Tambah Sejajar"), "plus.rectangle.on.rectangle", #selector(addSibling(_:)), tip: L("Tambah simpul sejajar (Return)"))
        case .deleteNode:
            return button(L("Hapus"), "trash", #selector(deleteNode(_:)), tip: L("Hapus simpul dan turunannya (Delete)"))
        case .zoomFit:
            return button(L("Paskan"), "arrow.up.left.and.down.right.magnifyingglass", #selector(zoomFit(_:)), tip: L("Paskan seluruh pohon ke jendela"))
        case .export:
            let it = NSMenuToolbarItem(itemIdentifier: id)
            it.label = L("Ekspor")
            it.paletteLabel = L("Ekspor")
            it.toolTip = L("Ekspor atau salin pohon")
            it.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: L("Ekspor"))
            let m = NSMenu()
            m.addItem(withTitle: L("Ekspor sebagai PNG…"), action: #selector(exportPNG(_:)), keyEquivalent: "")
            m.addItem(withTitle: L("Ekspor sebagai PDF…"), action: #selector(exportPDF(_:)), keyEquivalent: "")
            m.addItem(withTitle: L("Salin Kerangka Teks"), action: #selector(copyOutline(_:)), keyEquivalent: "")
            it.menu = m
            return it
        default:
            return nil
        }
    }
}
