import AppKit

@objc(PolicyDocument)
final class PolicyDocument: NSDocument {
    private(set) var tree = PolicyTree.blank
    var selection = PolicyTree.coreID
    private var coalesceKey: String?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(PolicyWindowController(document: self))
    }

    override func data(ofType typeName: String) throws -> Data { try tree.encoded() }

    override func read(from data: Data, ofType typeName: String) throws {
        do {
            tree = try PolicyTree.decoded(from: data)
        } catch {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError, userInfo: [
                NSLocalizedDescriptionKey: L("Berkas ini bukan pohon masalah yang bisa dibaca."),
                NSLocalizedRecoverySuggestionErrorKey: L("Berkas harus berisi JSON dengan \"core\", \"causes\", dan \"effects\". JSON dari versi web aplikasi ini juga bisa dibuka."),
            ])
        }
        if tree.node(selection) == nil { selection = PolicyTree.coreID }
        notifyChange()
    }

    func replaceTreeBeforeDisplay(_ t: PolicyTree) { tree = t }

    /// Every edit passes through here. `coalesce` merges a run of keystrokes in one
    /// field into a single undo step; any other edit, undo or selection change ends the run.
    func apply(_ name: String, coalesce key: String? = nil, _ body: (inout PolicyTree) -> Void) {
        let oldTree = tree, oldSelection = selection
        var new = tree
        body(&new)
        guard new != oldTree else { return }
        if let key, key == coalesceKey {
            tree = new
            updateChangeCount(.changeDone)
            notifyChange()
            return
        }
        coalesceKey = key
        undoManager?.registerUndo(withTarget: self) { $0.restore(oldTree, oldSelection, name) }
        undoManager?.setActionName(name)
        tree = new
        notifyChange()
    }

    private func restore(_ t: PolicyTree, _ sel: String, _ name: String) {
        let currentTree = tree, currentSelection = selection
        undoManager?.registerUndo(withTarget: self) { $0.restore(currentTree, currentSelection, name) }
        undoManager?.setActionName(name)
        tree = t
        selection = t.node(sel) == nil ? PolicyTree.coreID : sel
        coalesceKey = nil
        notifyChange()
    }

    func endCoalescing() { coalesceKey = nil }

    func select(_ id: String) {
        guard id != selection, tree.node(id) != nil else { return }
        selection = id
        coalesceKey = nil
        notifyChange()
    }

    func notifyChange() {
        for case let wc as PolicyWindowController in windowControllers { wc.refresh() }
    }

    // MARK: Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.dictionary().addEntries(from: printSettings)
        let goal = windowControllers.compactMap { ($0 as? PolicyWindowController)?.goalView }.first ?? false
        return NSPrintOperation(view: ExportView(tree: tree, goal: goal), printInfo: info)
    }
}
