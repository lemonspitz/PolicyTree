import AppKit

/// Keeps a tree smaller than the window centred instead of pinned to a corner.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if doc.frame.width < r.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if doc.frame.height < r.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

final class TreeView: NSView {
    weak var controller: PolicyWindowController?
    private(set) var treeLayout = TreeLayout()
    private var tree = PolicyTree.blank
    private var selection = PolicyTree.coreID
    private var goal = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    func reload(tree: PolicyTree, selection: String, goal: Bool) {
        self.tree = tree
        self.selection = selection
        self.goal = goal
        treeLayout = TreeRenderer.layout(tree: tree, goal: goal)
        setFrameSize(treeLayout.size)
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func scrollSelectionIntoView() {
        guard let item = treeLayout.item(id: selection) else { return }
        scrollToVisible(item.frame.insetBy(dx: -30, dy: -44))
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.canvas.setFill()
        dirtyRect.fill()
        TreeRenderer.draw(treeLayout, goal: goal, selection: selection, focused: window?.firstResponder === self && window?.isKeyWindow == true, dirty: dirtyRect)
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if let sel = treeLayout.item(id: selection) {
            for b in TreeRenderer.addButtons(for: sel) where b.rect.contains(p) {
                controller?.add(under: sel.node.id, coreSide: b.side)
                return
            }
        }
        if let item = treeLayout.item(at: p) {
            controller?.select(item.node.id)
            if event.clickCount == 2 { controller?.focusEditor() }
            return
        }
        if let clip = enclosingScrollView?.contentView {
            dragStart = (event.locationInWindow, clip.bounds.origin)
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragStart, let sv = enclosingScrollView else { return }
        let m = sv.magnification
        let dx = (event.locationInWindow.x - d.mouse.x) / m, dy = (event.locationInWindow.y - d.mouse.y) / m
        sv.contentView.scroll(to: sv.contentView.constrainBoundsRect(NSRect(origin: NSPoint(x: d.origin.x - dx, y: d.origin.y + dy), size: sv.contentView.bounds.size)).origin)
        sv.reflectScrolledClipView(sv.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { NSCursor.pop() }
        dragStart = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let item = treeLayout.item(at: p) else { return nil }
        window?.makeFirstResponder(self)
        controller?.select(item.node.id)
        return controller?.contextMenu(for: item.side)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let plainMods = event.modifierFlags.intersection([.command, .option, .control])
        guard plainMods.isEmpty, let c = controller else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 48: // Tab
            c.add(under: selection, coreSide: event.modifierFlags.contains(.shift) ? .effect : .cause)
        case 36, 76: // Return, Enter
            if selection == PolicyTree.coreID { c.focusEditor() } else { c.addSibling(nil) }
        case 51, 117: // Delete, Forward Delete
            if selection == PolicyTree.coreID { NSSound.beep() } else { c.deleteNode(nil) }
        case 120: // F2
            c.focusEditor()
        case 123: navigateSideways(-1)
        case 124: navigateSideways(1)
        case 125: navigateVertically(down: true)
        case 126: navigateVertically(down: false)
        default: super.keyDown(with: event)
        }
    }

    private func navigateSideways(_ delta: Int) {
        guard let loc = tree.location(of: selection), loc.side != .core, let pid = loc.parentID else { return }
        let siblings: [TreeNode]
        if pid == PolicyTree.coreID { siblings = loc.side == .effect ? tree.effects : tree.causes }
        else { siblings = tree.node(pid)?.children ?? [] }
        let i = loc.index + delta
        if siblings.indices.contains(i) { controller?.select(siblings[i].id); scrollSelectionIntoView() }
    }

    private func navigateVertically(down: Bool) {
        guard let loc = tree.location(of: selection), let node = tree.node(selection) else { return }
        var target: String?
        switch loc.side {
        case .core: target = (down ? tree.causes : tree.effects).first?.id
        case .cause: target = down ? node.children.first?.id : loc.parentID
        case .effect: target = down ? loc.parentID : node.children.first?.id
        }
        if let target { controller?.select(target); scrollSelectionIntoView() }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { goal ? L("Pohon tujuan") : L("Pohon masalah") }
    override func accessibilityChildren() -> [Any]? {
        guard let window else { return [] }
        return treeLayout.items.map { item in
            let rect = window.convertToScreen(convert(item.frame, to: nil))
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.button)
            e.setAccessibilityFrame(rect)
            e.setAccessibilityLabel(TreeRenderer.accessibilityLabel(item.node, side: item.side, depth: item.depth, goal: goal, levels: treeLayout.levels))
            e.setAccessibilityParent(self)
            return e
        }
    }
}
