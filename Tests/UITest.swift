#if UITEST
import AppKit

/// Drives a real document window with real key and mouse events, inside the app process,
/// so it never touches the user's cursor or needs Accessibility permission.
enum UITest {
    static var failures = 0
    static var sampleUnderTest: PolicyDocument?
    static func check(_ c: Bool, _ msg: String, line: Int = #line) {
        if !c { failures += 1; print("GAGAL (UITest:\(line)): \(msg)") }
    }
    static weak var um: UndoManager?
    /// A nested run loop never closes the automatic undo group the way a real event does,
    /// so each step closes its own group: one step here equals one user event.
    static func spin() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if let um {
            if um.groupingLevel > 0 { um.endUndoGrouping() }
            um.beginUndoGrouping()
        }
    }
    static weak var doc: PolicyDocument?
    /// Skips the empty groups spin() leaves behind; a group holding an edit always changes the tree.
    private static func step(_ op: (UndoManager) -> Void, _ can: (UndoManager) -> Bool) {
        guard let um, let doc else { return }
        if um.groupingLevel > 0 { um.endUndoGrouping() }
        let before = doc.tree
        while doc.tree == before && can(um) { op(um) }
        // Opening a group here would clear the redo stack, so the next edit's spin() opens it.
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    static func undo() { step({ $0.undo() }, { $0.canUndo }) }
    static func redo() { step({ $0.redo() }, { $0.canRedo }) }

    private static func ensureGroup() {
        if let um, um.groupingLevel == 0 { um.beginUndoGrouping() }
    }
    static func key(_ w: NSWindow, _ code: UInt16, _ chars: String = "", mods: NSEvent.ModifierFlags = []) {
        ensureGroup()
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                 characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        w.firstResponder?.keyDown(with: e)
        spin()
    }
    static func click(_ w: NSWindow, _ v: TreeView, at p: CGPoint, count: Int = 1) {
        ensureGroup()
        let loc = v.convert(p, to: nil)
        let d = NSEvent.mouseEvent(with: .leftMouseDown, location: loc, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        v.mouseDown(with: d)
        spin()
    }
    static func type(_ w: NSWindow, _ s: String) {
        ensureGroup()
        guard let tv = w.firstResponder as? NSTextView else { check(false, "kotak teks tidak fokus"); return }
        for ch in s { tv.insertText(String(ch), replacementRange: tv.selectedRange()); }
        spin()
    }
    static func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

    static func run() {
        setbuf(stdout, nil)
        let doc = PolicyDocument()
        doc.fileType = "com.lemonspitz.policytree.document"
        doc.makeWindowControllers()
        doc.showWindows()
        spin()
        let wc = doc.windowControllers[0] as! PolicyWindowController
        let w = wc.window!
        check(w.isVisible, "jendela tampil")
        check(wc.document === doc, "controller terikat ke dokumen")
        let views = allViews(w.contentView!)
        let tree = views.compactMap { $0 as? TreeView }.first!
        spin(); spin()
        wc.focusCanvas(); spin()
        doc.undoManager!.groupsByEvent = false
        um = doc.undoManager
        Self.doc = doc
        spin()
        check(w.firstResponder === tree, "kanvas fokus")

        // Keyboard on the canvas: Tab adds a cause under the core and moves into its text box.
        let before = doc.tree.causeCount
        key(w, 48, "\t")
        check(doc.tree.causeCount == before + 1, "Tab menambah penyebab")
        check(w.firstResponder is NSTextView, "fokus pindah ke kotak teks")
        let newID = doc.selection
        check(doc.tree.location(of: newID)?.side == .cause, "simpul baru terpilih")

        // Typing replaces the selected placeholder, and the whole run is one undo step.
        type(w, "Anggaran kurang")
        check(doc.tree.node(newID)?.text == "Anggaran kurang", "teks: \(doc.tree.node(newID)?.text ?? "-")")
        spin()
        undo()
        check(doc.tree.node(newID)?.text == "Penyebab baru", "batalkan ketikan sebagai satu langkah: \(doc.tree.node(newID)?.text ?? "nil")")
        undo()
        check(doc.tree.causeCount == before, "batalkan penambahan")
        check(doc.selection == PolicyTree.coreID, "seleksi kembali")
        redo()
        check(doc.tree.causeCount == before + 1, "ulangi penambahan")
        redo()
        check(doc.tree.node(newID)?.text == "Anggaran kurang", "ulangi ketikan")

        // Return/Tab/Esc inside the text box.
        doc.select(newID); spin()
        wc.focusEditor(selectAll: true); spin()
        (w.firstResponder as! NSTextView).doCommand(by: #selector(NSResponder.insertTab(_:))); spin()
        let sub = doc.selection
        check(doc.tree.location(of: sub)?.parentID == newID, "Tab di kotak teks menambah turunan")
        (w.firstResponder as! NSTextView).doCommand(by: #selector(NSResponder.insertNewline(_:))); spin()
        check(doc.tree.location(of: doc.selection)?.parentID == newID && doc.selection != sub, "Return di kotak teks menambah sejajar")
        (w.firstResponder as! NSTextView).doCommand(by: #selector(NSResponder.cancelOperation(_:))); spin()
        check(w.firstResponder === tree, "Esc kembali ke kanvas")

        // Arrows and Delete on the canvas.
        let second = doc.selection
        key(w, 123); check(doc.selection == sub, "panah kiri ke saudara")
        key(w, 126); check(doc.selection == newID, "panah atas ke induk")
        key(w, 125); check(doc.selection == sub, "panah bawah ke anak")
        key(w, 51, "\u{7F}")
        check(doc.tree.node(sub) == nil && doc.selection == second, "Delete menghapus dan memilih saudara")
        undo()
        check(doc.tree.node(sub) != nil && doc.selection == sub, "batalkan hapus")
        doc.select(PolicyTree.coreID); spin()
        wc.focusCanvas(); spin()
        let total = doc.tree.causeCount
        key(w, 51, "\u{7F}")
        check(doc.tree.causeCount == total, "masalah inti tak bisa dihapus")

        // Mouse: click selects, the + button adds, double click opens the editor.
        let core = tree.treeLayout.item(id: PolicyTree.coreID)!
        let target = tree.treeLayout.item(id: newID)!
        click(w, tree, at: CGPoint(x: target.frame.midX, y: target.frame.midY))
        check(doc.selection == newID, "klik memilih simpul")
        let plus = TreeRenderer.addButtons(for: tree.treeLayout.item(id: newID)!)[0]
        let n0 = doc.tree.causeCount
        click(w, tree, at: CGPoint(x: plus.rect.midX, y: plus.rect.midY))
        check(doc.tree.causeCount == n0 + 1, "tombol + menambah")
        click(w, tree, at: CGPoint(x: core.frame.midX, y: tree.treeLayout.item(id: PolicyTree.coreID)!.frame.midY), count: 2)
        check(doc.selection == PolicyTree.coreID && w.firstResponder is NSTextView, "klik ganda membuka penyunting")
        wc.focusCanvas(); spin()
        let up = TreeRenderer.addButtons(for: tree.treeLayout.item(id: PolicyTree.coreID)!).first { $0.side == .effect }!
        let e0 = doc.tree.effectCount
        click(w, tree, at: CGPoint(x: up.rect.midX, y: up.rect.midY))
        check(doc.tree.effectCount == e0 + 1, "tombol + atas menambah dampak")
        check(wc.contextMenu(for: .cause).items.contains { $0.submenu != nil }, "menu konteks punya submenu aspek")

        // Goal view edits the objective, not the problem statement.
        wc.showGoalTree(nil); spin()
        doc.select(newID); spin()
        wc.focusEditor(selectAll: true); spin()
        let textBefore = doc.tree.node(newID)!.text
        type(w, "Anggaran cukup")
        check(doc.tree.node(newID)?.obj == "Anggaran cukup" && doc.tree.node(newID)?.text == textBefore, "tujuan tersunting terpisah")
        wc.showProblemTree(nil); spin()
        doc.update_for_test_suggest(newID)
        wc.suggestObjective(nil); spin()
        check(doc.tree.node(newID)?.obj == "Anggaran cukup", "usulan: \(doc.tree.node(newID)?.obj ?? "-")")
        wc.suggestAllObjectives(nil); spin()
        check(doc.tree.core.obj.isEmpty == false, "isi semua tujuan")

        // Level style from the inspector: name, shape and colour apply to the whole level.
        doc.select(newID); spin()
        let lvKey = "cause.1"
        let nameBox = allViews(w.contentView!).compactMap { $0 as? NSTextView }.first { $0.accessibilityLabel() == "Nama level" }!
        w.makeFirstResponder(nameBox); spin()
        type(w, "Penyebab langsung")
        check(doc.tree.levels[lvKey]?.name == "Penyebab langsung", "nama level: \(doc.tree.levels[lvKey]?.name ?? "-")")
        check(tree.accessibilityChildren()?.contains { ($0 as? NSAccessibilityElement)?.accessibilityLabel()?.hasPrefix("Penyebab langsung") == true } == true, "nama level tampil di kanvas")
        spin()
        undo()
        check(doc.tree.levels[lvKey] == nil, "nama level dibatalkan sebagai satu langkah")
        redo()
        check(doc.tree.levels[lvKey]?.name == "Penyebab langsung", "ulangi nama level")
        wc.focusCanvas(); spin()
        let shapes = allViews(w.contentView!).compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "Bentuk level" }!
        shapes.selectItem(withTitle: NodeShape.hexagon.label)
        shapes.sendAction(shapes.action, to: shapes.target); spin()
        check(doc.tree.levels[lvKey]?.shape == "hexagon", "bentuk level")
        let well = allViews(w.contentView!).compactMap { $0 as? NSColorWell }.first { $0.accessibilityLabel() == "Warna level" }!
        well.color = NSColor(srgbRed: 0.75, green: 0.22, blue: 0.17, alpha: 1)
        well.sendAction(well.action, to: well.target); spin()
        check(doc.tree.levels[lvKey]?.color == "#BF382B", "warna level: \(doc.tree.levels[lvKey]?.color ?? "-")")
        let siblingsStyled = doc.tree.causes.allSatisfy { doc.tree.level(side: .cause, depth: 1) == doc.tree.levels[lvKey] && $0.id != "" }
        check(siblingsStyled, "gaya berlaku untuk seluruh level")
        // Inspector order: buttons, keyboard hint, then the level section, each below the last.
        func y(_ match: (NSView) -> Bool) -> CGFloat? {
            allViews(w.contentView!).first(where: match).map { $0.convert($0.bounds, to: nil).maxY }
        }
        let yHint = y { ($0 as? NSTextField)?.stringValue.hasPrefix("Di kanvas") == true }
        let yHead = y { ($0 as? NSTextField)?.stringValue == "GAYA LEVEL" }
        let yName = y { $0.accessibilityLabel() == "Nama level" }
        let yShape = y { $0 === shapes }
        let yReset = y { ($0 as? NSButton)?.title.hasPrefix("Kembalikan gaya") == true }
        // Window coordinates grow upward, so each later item has a smaller y.
        if let a = yHint, let b = yHead, let c = yName, let d = yShape, let e = yReset {
            check(a > b && b > c && c > d && d > e, "urutan inspektor: \([a, b, c, d, e])")
        } else { check(false, "bagian gaya level lengkap di inspektor") }
        if ProcessInfo.processInfo.environment["POLICYTREE_HOLD"] != nil {
            // Lets the shell take a real capture (screencapture -l) of this state.
            allViews(w.contentView!).compactMap { $0 as? NSButton }.first { $0.title.hasPrefix("Kembalikan gaya") }?.scrollToVisible(.zero)
            spin()
            if let shot = ProcessInfo.processInfo.environment["POLICYTREE_SHOT"],
               let v = allViews(w.contentView!).first(where: { $0.accessibilityLabel() == "Nama level" })?.enclosingScrollView?.superview?.enclosingScrollView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot))
            }
            print("JENDELA \(w.windowNumber)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        wc.showGoalTree(nil); spin()
        w.makeFirstResponder(nameBox); spin()
        check(nameBox.string.isEmpty, "pohon tujuan punya nama level sendiri")
        type(w, "Sarana langsung")
        check(doc.tree.levels[lvKey]?.goalName == "Sarana langsung" && doc.tree.levels[lvKey]?.name == "Penyebab langsung", "nama tujuan terpisah")
        wc.showProblemTree(nil); spin()
        let resetAll = NSMenuItem(title: "", action: #selector(PolicyWindowController.resetAllLevelStyles(_:)), keyEquivalent: "")
        check(wc.validateMenuItem(resetAll), "kembalikan semua aktif saat ada gaya")
        wc.resetAllLevelStyles(nil); spin()
        check(doc.tree.levels.isEmpty && !wc.validateMenuItem(resetAll), "kembalikan semua gaya")
        undo()
        check(doc.tree.levels[lvKey]?.shape == "hexagon", "batalkan pengembalian gaya")
        spin()
        wc.resetAllLevelStyles(nil); spin()

        // Settings window: every control writes its preference and takes effect.
        let d = UserDefaults.standard
        let savedPrefs = [Lang.defaultsKey, "AppleLanguages", Prefs.appearanceKey, Prefs.pngScaleKey, Prefs.keyHintsKey].map { ($0, d.object(forKey: $0)) }
        let sc = SettingsController.shared
        sc.showWindow(nil); spin()
        check(sc.window?.isVisible == true, "jendela pengaturan tampil")
        check(sc.languagePopup.selectedItem?.representedObject as? String == Lang.preference, "bahasa terpilih sesuai")
        sc.appearancePopup.selectItem(withTitle: L("Gelap")); sc.appearanceChanged(); spin()
        check(NSApp.appearance?.name == .darkAqua && Prefs.appearance == "dark", "tema gelap")
        sc.appearancePopup.selectItem(withTitle: L("Ikuti sistem")); sc.appearanceChanged(); spin()
        check(NSApp.appearance == nil, "tema ikuti sistem")
        sc.scalePopup.selectItem(at: 2); sc.scaleChanged()
        check(Prefs.pngScale == 3, "resolusi PNG")
        let hints = allViews(w.contentView!).compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix(L("Di kanvas")) }!
        sc.hintsCheck.state = .off; sc.hintsChanged(); spin()
        check(hints.isHidden, "petunjuk keyboard disembunyikan")
        sc.hintsCheck.state = .on; sc.hintsChanged(); spin()
        check(!hints.isHidden, "petunjuk keyboard tampil lagi")
        let other = Lang.code == "en" ? "id" : "en"
        sc.languagePopup.selectItem(at: sc.languagePopup.indexOfItem(withRepresentedObject: other)); sc.languageChanged(); spin()
        check(Lang.preference == other && d.stringArray(forKey: "AppleLanguages") == [other], "bahasa tersimpan untuk AppKit")
        check(!sc.restartButton.isHidden, "tombol buka ulang muncul saat bahasa berubah")
        if let shot = ProcessInfo.processInfo.environment["POLICYTREE_SETTINGS_SHOT"], let v = sc.window?.contentView,
           let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot))
        }
        sc.languagePopup.selectItem(at: sc.languagePopup.indexOfItem(withRepresentedObject: Lang.code)); sc.languageChanged(); spin()
        check(sc.restartButton.isHidden, "tombol buka ulang hilang lagi")
        sc.close()
        for (k, v) in savedPrefs { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
        Prefs.applyAppearance()

        // Menu state.
        let del = NSMenuItem(title: "", action: #selector(PolicyWindowController.deleteNode(_:)), keyEquivalent: "")
        doc.select(PolicyTree.coreID); spin()
        check(!wc.validateMenuItem(del), "hapus nonaktif pada inti")
        let sib = NSMenuItem(title: "", action: #selector(PolicyWindowController.addSibling(_:)), keyEquivalent: "")
        check(!wc.validateMenuItem(sib), "sejajar nonaktif pada inti")
        let child = NSMenuItem(title: "x", action: #selector(PolicyWindowController.addChild(_:)), keyEquivalent: "")
        _ = wc.validateMenuItem(child)
        check(child.title == "Tambah Penyebab", "judul menu mengikuti simpul")

        // Every action in the menu bar must be something the app can respond to.
        let delegate = NSApp.delegate as! AppDelegate
        func walk(_ m: NSMenu) {
            for it in m.items {
                if let s = it.submenu { walk(s) }
                guard it.submenu == nil, let a = it.action else { continue }
                let owners: [AnyObject] = [wc, doc, w, NSApp, delegate, NSDocumentController.shared, NSTextView(), wc.window!.contentViewController!]
                check(owners.contains { $0.responds(to: a) }, "menu '\(it.title)' tanpa penerima: \(a)")
            }
        }
        let built = delegate.buildMainMenu()
        walk(built)
        check(built.items.first?.submenu?.items.contains { $0.keyEquivalent == "," && $0.action == #selector(AppDelegate.showSettings(_:)) } == true, "menu Pengaturan… dengan Command-koma")

        // Credits
        let credits = Credits.attributed().string
        check(credits.contains("@lemonspitz") && credits.contains("github.com/lemonspitz"), "kredit tampil")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        check(version == "1.0", "versi 1.0: \(version ?? "nil")")

        // Zoom
        wc.zoomFit(nil); spin()
        let sv = tree.enclosingScrollView!
        check(sv.magnification > 0.29 && sv.magnification <= 1.0, "paskan: \(sv.magnification)")

        // Export
        let ev = ExportView(tree: doc.tree, goal: false)
        let png = ev.pngData()
        check(png != nil && png!.starts(with: [0x89, 0x50, 0x4E, 0x47]), "PNG valid")
        check(ev.pdfData().starts(with: Array("%PDF".utf8)), "PDF valid")
        let op = try? doc.printOperation(withSettings: [:])
        check(op != nil, "operasi cetak terbentuk")
        wc.copyOutline(nil)
        check(NSPasteboard.general.string(forType: .string)?.hasPrefix("POHON MASALAH") == true, "salin kerangka")

        // File round trip, including a corrupt file.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("uji-\(UUID().uuidString).policytree")
        do {
            try doc.data(ofType: "x").write(to: url)
            let d2 = PolicyDocument()
            try d2.read(from: url, ofType: "com.lemonspitz.policytree.document")
            check(d2.tree == doc.tree, "simpan lalu buka sama")
            do {
                try d2.read(from: "bukan json".data(using: .utf8)!, ofType: "x")
                check(false, "berkas rusak harus ditolak")
            } catch { check((error as NSError).localizedDescription.contains("bukan pohon masalah"), "pesan error jelas") }
            check(d2.tree == doc.tree, "berkas rusak tidak mengubah pohon")
            try? FileManager.default.removeItem(at: url)
        } catch { check(false, "berkas: \(error)") }

        // A very long statement must still lay out without overlap.
        doc.select(newID)
        doc.apply("x") { $0.update(newID) { $0.text = String(repeating: "kata panjang ", count: 60) } }
        spin()
        let items = tree.treeLayout.items
        for (i, a) in items.enumerated() { for b in items[(i + 1)...] { check(!a.frame.intersects(b.frame), "teks panjang tumpang tindih") } }

        // Needs the document types in Info.plist, which test.sh provides through a throwaway bundle.
        if NSDocumentController.shared.defaultType != nil {
            let n = NSDocumentController.shared.documents.count
            (NSApp.delegate as! AppDelegate).newSampleDocument(nil)
            spin()
            let docs = NSDocumentController.shared.documents.compactMap { $0 as? PolicyDocument }
            check(NSDocumentController.shared.documents.count == n + 1, "dokumen contoh terbuka")
            let sample = docs.first { $0.tree.title.contains("(contoh)") }
            check(sample?.tree.causeCount == 10, "isi dokumen contoh")
            check(sample?.windowControllers.first?.window?.isVisible == true, "jendela contoh tampil")
            sampleUnderTest = sample
        } else {
            check(false, "jenis dokumen tidak terbaca; jalankan dari bundel")
        }

        doc.updateChangeCount(.changeCleared)
        // The initial fit is queued on the main queue, which can't drain inside this block.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let v = sampleUnderTest?.windowControllers.first?.window.flatMap { allViews($0.contentView!).compactMap { $0 as? TreeView }.first }
            let sv = v?.enclosingScrollView
            let mag = sv?.magnification ?? 1
            check(mag < 0.99, "pohon contoh dipaskan saat dibuka: \(mag)")
            if let sv, let v {
                let visible = sv.contentView.documentVisibleRect
                check(visible.contains(v.bounds.insetBy(dx: 1, dy: 1)), "seluruh pohon terlihat: \(visible) dari \(v.bounds)")
            }
            print(failures == 0 ? "Uji UI lulus." : "\(failures) uji UI gagal.")
            exit(failures == 0 ? 0 : 1)
        }
    }
}

extension PolicyDocument {
    /// Sets the statement the suggestion test expects to flip.
    func update_for_test_suggest(_ id: String) { apply("x") { $0.update(id) { $0.text = "Anggaran kurang" } } }
}
#endif
