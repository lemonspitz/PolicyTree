import AppKit

/// Stored preferences. Language lives in `Lang`; everything here applies right away.
enum Prefs {
    static let appearanceKey = "appearance"   // "system", "light", "dark"
    static let pngScaleKey = "pngScale"       // 1, 2, 3
    static let keyHintsKey = "showKeyHints"

    static var appearance: String { UserDefaults.standard.string(forKey: appearanceKey) ?? "system" }
    static var pngScale: CGFloat {
        let v = UserDefaults.standard.integer(forKey: pngScaleKey)
        return CGFloat((1...3).contains(v) ? v : 2)
    }
    static var showKeyHints: Bool { UserDefaults.standard.object(forKey: keyHintsKey) as? Bool ?? true }

    static func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static let changed = Notification.Name("PolicyTreePrefsChanged")
}

final class SettingsController: NSWindowController {
    static let shared = SettingsController()

    let languagePopup = NSPopUpButton()
    let appearancePopup = NSPopUpButton()
    let scalePopup = NSPopUpButton()
    let hintsCheck = NSButton(checkboxWithTitle: L("Tampilkan petunjuk keyboard di panel kanan"), target: nil, action: nil)
    let restartNote = NSTextField(wrappingLabelWithString: "")
    let restartButton = NSButton(title: L("Buka Ulang Sekarang"), target: nil, action: nil)

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 260), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.title = L("Pengaturan")
        w.identifier = NSUserInterfaceItemIdentifier("PolicyTreeSettings")
        w.isReleasedWhenClosed = false
        super.init(window: w)
        build()
        w.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        return l
    }

    private func fill(_ p: NSPopUpButton, _ items: [(String, String)], selected: String, _ action: Selector, _ name: String) {
        for (title, value) in items {
            p.addItem(withTitle: title)
            p.lastItem?.representedObject = value
        }
        if let i = p.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) { p.selectItem(at: i) }
        p.target = self
        p.action = action
        p.setAccessibilityLabel(name)
    }

    private func build() {
        fill(languagePopup, Lang.choices.map { ($0.code == "system" ? L($0.label) : $0.label, $0.code) },
             selected: Lang.preference, #selector(languageChanged), L("Bahasa"))
        fill(appearancePopup, [(L("Ikuti sistem"), "system"), (L("Terang"), "light"), (L("Gelap"), "dark")],
             selected: Prefs.appearance, #selector(appearanceChanged), L("Tema"))
        fill(scalePopup, [(L("Standar (1×)"), "1"), (L("Tajam (2×)"), "2"), (L("Sangat tajam (3×)"), "3")],
             selected: "\(Int(Prefs.pngScale))", #selector(scaleChanged), L("Resolusi PNG"))
        hintsCheck.target = self
        hintsCheck.action = #selector(hintsChanged)
        hintsCheck.state = Prefs.showKeyHints ? .on : .off

        restartNote.font = .systemFont(ofSize: 11)
        restartNote.textColor = .secondaryLabelColor
        restartNote.preferredMaxLayoutWidth = 300
        restartButton.target = self
        restartButton.action = #selector(relaunch)
        restartButton.controlSize = .small
        let restartRow = NSStackView(views: [restartNote, restartButton])
        restartRow.orientation = .vertical
        restartRow.alignment = .leading
        restartRow.spacing = 6

        let grid = NSGridView(views: [
            [label(L("Bahasa")), languagePopup],
            [NSGridCell.emptyContentView, restartRow],
            [label(L("Tema")), appearancePopup],
            [label(L("Resolusi PNG")), scalePopup],
            [NSGridCell.emptyContentView, hintsCheck],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.row(at: 1).rowAlignment = .none
        grid.row(at: 1).topPadding = -4
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -28),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalToConstant: 480),
        ])
        window?.contentView = content
        updateRestartNote()
    }

    /// The language in use is fixed until relaunch, so the note says what will happen.
    private func updateRestartNote() {
        let pending = Lang.resolve(Lang.preference) != Lang.code
        restartNote.stringValue = pending
            ? L("Bahasa baru dipakai setelah Policy Tree dibuka ulang. Dokumen yang terbuka disimpan otomatis.")
            : L("Mengganti bahasa memerlukan membuka ulang aplikasi.")
        restartButton.isHidden = !pending
        // The window hugs its content, so it grows and shrinks with the restart row.
        if let content = window?.contentView {
            content.layoutSubtreeIfNeeded()
            window?.setContentSize(content.fittingSize)
        }
    }

    @objc func languageChanged() {
        guard let code = languagePopup.selectedItem?.representedObject as? String else { return }
        Lang.save(code)
        updateRestartNote()
    }
    @objc func appearanceChanged() {
        UserDefaults.standard.set(appearancePopup.selectedItem?.representedObject as? String ?? "system", forKey: Prefs.appearanceKey)
        Prefs.applyAppearance()
    }
    @objc func scaleChanged() {
        UserDefaults.standard.set(Int(scalePopup.selectedItem?.representedObject as? String ?? "2") ?? 2, forKey: Prefs.pngScaleKey)
    }
    @objc func hintsChanged() {
        UserDefaults.standard.set(hintsCheck.state == .on, forKey: Prefs.keyHintsKey)
        NotificationCenter.default.post(name: Prefs.changed, object: nil)
    }

    /// Quits normally (documents autosave and come back through state restoration), then opens the app again.
    @objc func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
