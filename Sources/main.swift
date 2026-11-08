import AppKit

/// One place for the credits, shown in the About panel and in Help.
enum Credits {
    static let author = "@lemonspitz"
    static let url = "https://github.com/lemonspitz"

    static func attributed() -> NSAttributedString {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: center]
        let s = NSMutableAttributedString(string: L("Alat penyusun pohon masalah dan pohon tujuan untuk analisis kebijakan.") + "\n\n" + L("Dibuat oleh {0}", author) + "\n", attributes: base)
        var link = base
        link[.link] = URL(string: url)
        s.append(NSAttributedString(string: "github.com/lemonspitz", attributes: link))
        return s
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        Prefs.applyAppearance()
        NSApp.mainMenu = buildMainMenu()
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if UITEST
        return
        #endif
        NSApp.activate()
        // State restoration can finish with nothing to restore and skip the untitled document,
        // or leave a document without a visible window. Either way the app must not sit there windowless.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let dc = NSDocumentController.shared
            if dc.documents.isEmpty {
                dc.newDocument(nil)
            } else if !NSApp.windows.contains(where: { $0.isVisible && $0.windowController?.document != nil }) {
                dc.documents.forEach { $0.showWindows() }
            }
        }
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func newSampleDocument(_ sender: Any?) {
        let dc = NSDocumentController.shared
        do {
            guard let type = dc.defaultType, let doc = try dc.makeUntitledDocument(ofType: type) as? PolicyDocument else { return }
            doc.replaceTreeBeforeDisplay(.sample)
            dc.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: Credits.attributed()])
        NSApp.activate()
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsController.shared.showWindow(nil)
        SettingsController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc func openCreditsLink(_ sender: Any?) {
        if let url = URL(string: Credits.url) { NSWorkspace.shared.open(url) }
    }

    @objc func showGuide(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = L("Cara menyusun pohon masalah")
        a.informativeText = L("""
        1. Rumuskan satu masalah inti sebagai kondisi negatif, bukan sebagai solusi yang belum ada.
        2. Ke bawah, tanyakan "mengapa ini terjadi?" sampai menemukan penyebab yang bisa ditangani kebijakan. Penyebab paling bawah ditandai AKAR.
        3. Ke atas, tanyakan "lalu apa akibatnya?" untuk memetakan dampak.
        4. Tandai aspek kebijakan tiap penyebab untuk melihat di mana masalah menumpuk.
        5. Buka Pohon Tujuan untuk membalik setiap kondisi negatif menjadi kondisi yang diharapkan. Akar masalah berubah menjadi titik intervensi.

        Gunakan Berkas > Contoh Stunting Baru untuk melihat contoh lengkap.
        """)
        a.runModal()
    }

    func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func top(_ title: String) -> NSMenu {
            let m = NSMenu(title: title)
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            it.submenu = m
            main.addItem(it)
            return m
        }
        @discardableResult
        func add(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let it = m.addItem(withTitle: title, action: action, keyEquivalent: key)
            it.keyEquivalentModifierMask = mods
            it.target = target
            return it
        }
        let name = "Policy Tree"

        let app = top(name)
        add(app, L("Tentang {0}", name), #selector(showAbout(_:)), target: self)
        app.addItem(.separator())
        add(app, L("Pengaturan…"), #selector(showSettings(_:)), ",", target: self)
        app.addItem(.separator())
        let services = NSMenu(title: L("Layanan"))
        add(app, L("Layanan"), nil).submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        add(app, L("Sembunyikan {0}", name), #selector(NSApplication.hide(_:)), "h")
        add(app, L("Sembunyikan Lainnya"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, L("Tampilkan Semua"), #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, L("Keluar dari {0}", name), #selector(NSApplication.terminate(_:)), "q")

        let file = top(L("Berkas"))
        add(file, L("Baru"), #selector(NSDocumentController.newDocument(_:)), "n")
        add(file, L("Contoh Stunting Baru"), #selector(newSampleDocument(_:)), target: self)
        add(file, L("Buka…"), #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenu(title: L("Buka Terkini"))
        add(recent, L("Bersihkan Menu"), #selector(NSDocumentController.clearRecentDocuments(_:)))
        add(file, L("Buka Terkini"), nil).submenu = recent
        let setName = NSSelectorFromString("_setMenuName:")
        if recent.responds(to: setName) { recent.perform(setName, with: "NSRecentDocumentsMenu") }
        file.addItem(.separator())
        add(file, L("Tutup"), #selector(NSWindow.performClose(_:)), "w")
        add(file, L("Simpan…"), #selector(NSDocument.save(_:)), "s")
        add(file, L("Duplikat"), #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
        add(file, L("Ubah Nama…"), #selector(NSDocument.rename(_:)))
        add(file, L("Pindahkan ke…"), #selector(NSDocument.move(_:)))
        add(file, L("Kembalikan ke Versi Tersimpan…"), #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        add(file, L("Ekspor sebagai PNG…"), #selector(PolicyWindowController.exportPNG(_:)), "e")
        add(file, L("Ekspor sebagai PDF…"), #selector(PolicyWindowController.exportPDF(_:)), "e", [.command, .shift])
        add(file, L("Salin Kerangka Teks"), #selector(PolicyWindowController.copyOutline(_:)), "c", [.command, .shift])
        file.addItem(.separator())
        add(file, L("Pengaturan Halaman…"), #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        add(file, L("Cetak…"), #selector(NSDocument.printDocument(_:)), "p")

        let edit = top(L("Edit"))
        add(edit, L("Batalkan"), Selector(("undo:")), "z")
        add(edit, L("Ulangi"), Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, L("Potong"), #selector(NSText.cut(_:)), "x")
        add(edit, L("Salin"), #selector(NSText.copy(_:)), "c")
        add(edit, L("Tempel"), #selector(NSText.paste(_:)), "v")
        add(edit, L("Pilih Semua"), #selector(NSText.selectAll(_:)), "a")

        let tree = top(L("Pohon"))
        add(tree, L("Tambah Turunan"), #selector(PolicyWindowController.addChild(_:)), "n", [.command, .shift])
        add(tree, L("Tambah Dampak"), #selector(PolicyWindowController.addEffect(_:)), "d", [.command, .shift])
        add(tree, L("Tambah Simpul Sejajar"), #selector(PolicyWindowController.addSibling(_:)), "n", [.command, .option])
        add(tree, L("Hapus Simpul"), #selector(PolicyWindowController.deleteNode(_:)), "\u{8}", .command)
        tree.addItem(.separator())
        add(tree, L("Geser ke Kiri"), #selector(PolicyWindowController.moveNodeLeft(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option])
        add(tree, L("Geser ke Kanan"), #selector(PolicyWindowController.moveNodeRight(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option])
        tree.addItem(.separator())
        add(tree, L("Usulkan Rumusan Tujuan"), #selector(PolicyWindowController.suggestObjective(_:)), "u", [.command, .shift])
        add(tree, L("Usulkan Semua Tujuan yang Kosong"), #selector(PolicyWindowController.suggestAllObjectives(_:)))
        tree.addItem(.separator())
        add(tree, L("Kembalikan Gaya Semua Level"), #selector(PolicyWindowController.resetAllLevelStyles(_:)))

        let view = top(L("Tampilan"))
        add(view, L("Pohon Masalah"), #selector(PolicyWindowController.showProblemTree(_:)), "1")
        add(view, L("Pohon Tujuan"), #selector(PolicyWindowController.showGoalTree(_:)), "2")
        view.addItem(.separator())
        add(view, L("Perbesar"), #selector(PolicyWindowController.zoomInTree(_:)), "+")
        add(view, L("Perkecil"), #selector(PolicyWindowController.zoomOutTree(_:)), "-")
        add(view, L("Paskan ke Jendela"), #selector(PolicyWindowController.zoomFit(_:)), "0")
        view.addItem(.separator())
        add(view, L("Tampilkan Inspektor"), #selector(NSSplitViewController.toggleInspector(_:)), "i", [.command, .option])
        add(view, L("Tampilkan Bilah Alat"), #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
        add(view, L("Sesuaikan Bilah Alat…"), #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        add(view, L("Masuk Layar Penuh"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let window = top(L("Jendela"))
        add(window, L("Minimalkan"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, L("Zoom"), #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, L("Bawa Semua ke Depan"), #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        let help = top(L("Bantuan"))
        add(help, L("Cara Menyusun Pohon Masalah"), #selector(showGuide(_:)), target: self)
        help.addItem(.separator())
        add(help, L("Situs Pembuat"), #selector(openCreditsLink(_:)), target: self)
        NSApp.helpMenu = help
        return main
    }
}

// Command-line helpers: `--render`, `--resave` and `--write-sample` check drawing and files without a window.
let args = CommandLine.arguments
_ = NSApplication.shared
if args.count >= 3, args[1] == "--write-sample" {
    try! PolicyTree.sample.encoded().write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}
if args.count >= 4, args[1] == "--resave" {
    // Reads a file and writes it back, so other tools can check nothing is lost on the way.
    let t = try! PolicyTree.decoded(from: Data(contentsOf: URL(fileURLWithPath: args[2])))
    try! t.encoded().write(to: URL(fileURLWithPath: args[3]))
    exit(0)
}
if args.count >= 4, args[1] == "--render" {
    let tree: PolicyTree
    if args[2] == "sample" { tree = .sample }
    else if args[2] == "blank" { tree = .blank }
    else { tree = try! PolicyTree.decoded(from: Data(contentsOf: URL(fileURLWithPath: args[2]))) }
    let view = ExportView(tree: tree, goal: args.contains("--goal"))
    let data = args[3].hasSuffix(".pdf") ? view.pdfData() : view.pngData(scale: 1.5, appearanceName: args.contains("--dark") ? .darkAqua : .aqua)!
    try! data.write(to: URL(fileURLWithPath: args[3]))
    exit(0)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
#if UITEST
if args.contains("--uitest") {
    DispatchQueue.main.async { UITest.run() }
}
if args.contains("--dark-window") {
    // Shows a sample window in dark mode for a manual look; kept out of the release build.
    NSApp.appearance = NSAppearance(named: .darkAqua)
    // Same action as Berkas > Contoh Stunting Baru, after launch has finished.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        delegate.newSampleDocument(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for case let wc as PolicyWindowController in NSApp.windows.compactMap({ $0.windowController }) {
                let sv = (wc.window?.contentView).flatMap { root -> NSScrollView? in
                    func find(_ v: NSView) -> TreeView? { (v as? TreeView) ?? v.subviews.lazy.compactMap(find).first }
                    return find(root)?.enclosingScrollView
                }
                print("zoom=\(sv?.magnification ?? -1) tampak=\(sv?.contentView.documentVisibleRect ?? .zero) pohon=\(sv?.documentView?.bounds ?? .zero) kanvas=\(sv?.frame ?? .zero)")
                fflush(stdout)
            }
        }
    }
}
#endif
NSApplication.shared.run()
