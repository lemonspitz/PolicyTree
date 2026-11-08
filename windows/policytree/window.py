from __future__ import annotations

import os

from PySide6.QtCore import QMarginsF, QRectF, QSettings, QSizeF, Qt, QTimer, QUrl
from PySide6.QtGui import (QAction, QActionGroup, QColor, QDesktopServices, QGuiApplication, QIcon, QImage, QKeySequence, QPageLayout,
                           QPageSize, QPainter, QPalette, QPdfWriter)
from PySide6.QtPrintSupport import QPrintDialog, QPrinter
from PySide6.QtWidgets import (QApplication, QDialog, QDialogButtonBox, QFileDialog, QLabel, QMainWindow, QMenu, QMessageBox,
                               QScrollArea, QSplitter, QToolBar, QToolButton, QVBoxLayout)

from . import APP_NAME, AUTHOR, AUTHOR_URL, FILE_EXT, VERSION, document, render
from .canvas import TreeCanvas
from .i18n import L
from .document import Document
from .inspector import Inspector
from .model import ASPEK, CAUSE, CORE, CORE_ID, EFFECT, FileFormatError, Tree, suggest_objective

def file_filter():
    return f"Policy Tree (*.{FILE_EXT} *.pohon);;JSON (*.json);;" + L("Semua berkas") + " (*)"
AUTOSAVE_MS = 20000
_windows = []


def settings():
    return QSettings("lemonspitz", APP_NAME)


def resource(name):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), name)


def app_icon():
    return QIcon(resource("icon.png"))


def is_dark():
    # A choice in Settings wins; "system" follows Windows.
    pref = settings().value("appearance", "system")
    if pref in ("light", "dark"):
        return pref == "dark"
    return QGuiApplication.styleHints().colorScheme() == Qt.ColorScheme.Dark


def open_window(doc=None):
    w = MainWindow(doc or Document())
    _windows.append(w)
    w.show()
    QTimer.singleShot(0, w.zoom_fit)
    return w


def open_path(path, parent=None):
    """Brings up a file: focuses it if already open, reuses an empty window, else opens a new one."""
    full = os.path.abspath(path)
    for w in _windows:
        if w.doc.path and os.path.normcase(os.path.abspath(w.doc.path)) == os.path.normcase(full):
            w.raise_()
            w.activateWindow()
            return w
    try:
        doc = Document.load(full)
    except FileFormatError:
        _error(parent, L("Berkas ini bukan pohon masalah yang bisa dibaca."),
               L('Berkas harus berisi JSON dengan "core", "causes", dan "effects". Berkas dari aplikasi Mac dan JSON dari versi web bisa dibuka.'))
        return None
    except (OSError, UnicodeDecodeError) as e:
        _error(parent, L("Berkas tidak bisa dibuka."), str(e))
        _forget_recent(full)
        return None
    _remember_recent(full)
    if parent and parent.doc.pristine:
        parent.set_document(doc)
        return parent
    return open_window(doc)


def _error(parent, text, detail):
    box = QMessageBox(QMessageBox.Warning, APP_NAME, text, QMessageBox.Ok, parent)
    box.setInformativeText(detail)
    box.exec()


def recent_files():
    return [p for p in (settings().value("recent") or []) if isinstance(p, str)]


def _remember_recent(path):
    items = [path] + [p for p in recent_files() if p != path]
    settings().setValue("recent", items[:10])


def _forget_recent(path):
    settings().setValue("recent", [p for p in recent_files() if p != path])


class MainWindow(QMainWindow):
    def __init__(self, doc):
        super().__init__()
        self.goal = bool(settings().value("goal", False, type=bool))
        self.setWindowIcon(app_icon())
        self.resize(1240, 780)
        self.setMinimumSize(760, 480)
        self.canvas = TreeCanvas(self)
        self.area = QScrollArea()
        self.area.setWidget(self.canvas)
        self.area.setAlignment(Qt.AlignCenter)
        self.area.setFrameShape(QScrollArea.NoFrame)
        self.inspector = Inspector(self)
        self.split = QSplitter(Qt.Horizontal)
        self.split.addWidget(self.area)
        self.split.addWidget(self.inspector)
        self.split.setStretchFactor(0, 1)
        self.split.setStretchFactor(1, 0)
        self.split.setSizes([900, 340])
        self.split.setCollapsible(0, False)
        self.setCentralWidget(self.split)
        self.doc = None
        self._build_actions()
        self._build_menus()
        self._build_toolbar()
        self.set_document(doc)
        self._autosave = QTimer(self)
        self._autosave.setInterval(AUTOSAVE_MS)
        self._autosave.timeout.connect(self.write_recovery)
        self._autosave.start()
        QGuiApplication.styleHints().colorSchemeChanged.connect(self._theme_changed)
        QApplication.instance().focusChanged.connect(self._focus_changed)

    def colors(self):
        return render.DARK if is_dark() else render.LIGHT

    def _theme_changed(self, *_):
        self.inspector._signature = None
        self.refresh()

    def _focus_changed(self, *_):
        self.update_actions()

    # ---- document

    def set_document(self, doc):
        if self.doc is not None:
            self.doc.changed.disconnect(self.refresh)
            document.clear_recovery(self.doc)
        self.doc = doc
        doc.changed.connect(self.refresh)
        self.refresh()

    def refresh(self):
        if self.doc is None:
            return
        doc = self.doc
        self.canvas.reload(doc.tree, doc.selection, self.goal)
        # Around a tree smaller than the window, the empty space must match the canvas.
        pal = self.area.viewport().palette()
        pal.setColor(QPalette.Window, QColor(self.colors()["canvas"]))
        self.area.viewport().setPalette(pal)
        self.area.viewport().setAutoFillBackground(True)
        self.inspector.reload(self.goal)
        name = os.path.basename(doc.path) if doc.path else L("Tanpa Judul")
        self.setWindowTitle(f"{name}[*] - {APP_NAME}")
        self.setWindowModified(doc.dirty)
        self.update_actions()

    def write_recovery(self):
        try:
            if self.doc.dirty:
                document.write_recovery(self.doc)
            else:
                document.clear_recovery(self.doc)
        except OSError:
            pass  # recovery is a safety net; never interrupt the user over it

    def closeEvent(self, e):
        if self.doc.dirty and not self.confirm_discard():
            e.ignore()
            return
        document.clear_recovery(self.doc)
        self._autosave.stop()
        QApplication.instance().focusChanged.disconnect(self._focus_changed)
        QGuiApplication.styleHints().colorSchemeChanged.disconnect(self._theme_changed)
        if self in _windows:
            _windows.remove(self)
        e.accept()

    def confirm_discard(self):
        """True when it's safe to close: saved, or the user chose to discard."""
        box = QMessageBox(QMessageBox.Warning, APP_NAME, L("Simpan perubahan pada pohon ini?"), parent=self)
        box.setInformativeText(L("Perubahan akan hilang jika tidak disimpan."))
        save = box.addButton(L("Simpan"), QMessageBox.AcceptRole)
        discard = box.addButton(L("Jangan Simpan"), QMessageBox.DestructiveRole)
        box.addButton(L("Batal"), QMessageBox.RejectRole)
        box.setDefaultButton(save)
        box.exec()
        if box.clickedButton() is save:
            return self.save()
        return box.clickedButton() is discard

    # ---- file actions

    def new_document(self):
        open_window()

    def new_sample(self):
        doc = Document(Tree.sample())
        if self.doc.pristine:
            self.set_document(doc)
            self.zoom_fit()
        else:
            open_window(doc)

    def open_dialog(self):
        path, _ = QFileDialog.getOpenFileName(self, L("Buka pohon"), "", file_filter())
        if path:
            w = open_path(path, self)
            if w is self:
                self.zoom_fit()

    def save(self):
        return self._save_to(self.doc.path) if self.doc.path else self.save_as()

    def save_as(self):
        suggestion = self.doc.path or (_safe_name(self.doc.tree.title) + "." + FILE_EXT)
        path, _ = QFileDialog.getSaveFileName(self, L("Simpan pohon"), suggestion, file_filter())
        return self._save_to(path) if path else False

    def _save_to(self, path):
        try:
            self.doc.save(path)
        except OSError as e:
            _error(self, L("Pohon tidak bisa disimpan."), f"{e}\n\n" + L("Coba simpan di folder lain."))
            return False
        document.clear_recovery(self.doc)
        _remember_recent(os.path.abspath(path))
        return True

    def export_name(self):
        return (L("Pohon Tujuan") if self.goal else L("Pohon Masalah")) + " - " + _safe_name(self.doc.tree.title)

    def export_png(self):
        path, _ = QFileDialog.getSaveFileName(self, L("Ekspor PNG"), self.export_name() + ".png", "PNG (*.png)")
        if path:
            from .settings_dialog import png_scale
            self._report(render_png(self.doc.tree, self.goal, path, png_scale()))

    def export_pdf(self):
        path, _ = QFileDialog.getSaveFileName(self, L("Ekspor PDF"), self.export_name() + ".pdf", "PDF (*.pdf)")
        if path:
            self._report(render_pdf(self.doc.tree, self.goal, path))

    def _report(self, ok):
        if not ok:
            _error(self, L("Berkas tidak bisa ditulis."), L("Periksa apakah berkas sedang dibuka aplikasi lain, atau coba folder lain."))

    def copy_outline(self):
        QApplication.clipboard().setText(self.doc.tree.outline(self.goal))
        self.statusBar().showMessage(L("Kerangka disalin."), 3000)

    def print_tree(self):
        printer = QPrinter(QPrinter.HighResolution)
        printer.setPageOrientation(QPageLayout.Landscape)
        dialog = QPrintDialog(printer, self)
        if dialog.exec() == QDialog.Accepted:
            render_print(self.doc.tree, self.goal, printer)

    # ---- edit actions

    def _after_add(self):
        self.canvas.reveal_selection()
        self.focus_editor(select_all=True)

    def add_under(self, node_id, side):
        doc = self.doc
        name = (L("Tambah Dampak") if side == EFFECT else L("Tambah Penyebab")) if node_id == CORE_ID else L("Tambah Simpul")

        def fn(t):
            new = t.add_child(node_id, side)
            if new:
                doc.selection = new
        doc.apply(name, fn)
        self._after_add()

    def add_child(self):
        self.add_under(self.doc.selection, CAUSE)

    def add_effect(self):
        self.add_under(CORE_ID, EFFECT)

    def add_sibling(self):
        doc = self.doc
        node_id = doc.selection
        if node_id == CORE_ID:
            return

        def fn(t):
            new = t.add_sibling(node_id)
            if new:
                doc.selection = new
        doc.apply(L("Tambah Simpul Sejajar"), fn)
        self._after_add()

    def delete_node(self):
        doc = self.doc
        node_id = doc.selection
        if node_id == CORE_ID:
            return

        def fn(t):
            nxt = t.remove(node_id)
            if nxt:
                doc.selection = nxt
        doc.apply(L("Hapus Simpul"), fn)
        self.focus_canvas()

    def move_node(self, delta):
        node_id = self.doc.selection
        self.doc.apply(L("Geser Simpul"), lambda t: t.move(node_id, delta))
        self.canvas.reveal_selection()

    def suggest_objective(self):
        node_id = self.doc.selection

        def fn(t):
            n = t.node(node_id)
            n.obj = suggest_objective(n.text)
        self.doc.apply(L("Usulkan Tujuan"), fn)

    def suggest_all(self):
        self.doc.apply(L("Usulkan Semua Tujuan"), lambda t: t.suggest_all_objectives())

    def reset_all_levels(self):
        self.doc.apply(L("Kembalikan Gaya Level"), lambda t: setattr(t, "levels", {}))

    def set_aspek(self, key):
        node_id = self.doc.selection
        self.doc.apply(L("Ubah Aspek"), lambda t: setattr(t.node(node_id), "aspek", key))

    # ---- focus and view

    def focus_canvas(self):
        self.canvas.setFocus()

    def focus_editor(self, select_all=False):
        self.inspector.focus_editor(self.goal, select_all)

    def set_goal(self, goal):
        self.goal = goal
        settings().setValue("goal", goal)
        self.refresh()

    def zoom_by(self, factor):
        self.canvas.set_zoom(self.canvas.zoom * factor)

    def zoom_fit(self):
        view = self.area.viewport().size()
        lay = self.canvas.lay
        if lay.width and lay.height:
            self.canvas.set_zoom(min(1.0, (view.width() - 8) / lay.width, (view.height() - 8) / lay.height))

    def toggle_inspector(self):
        self.inspector.setVisible(not self.inspector.isVisible())

    def show_guide(self):
        # Same text and key as the Mac guide, so one translation serves both.
        QMessageBox.information(self, L("Cara menyusun pohon masalah"), L(
            "1. Rumuskan satu masalah inti sebagai kondisi negatif, bukan sebagai solusi yang belum ada.\n"
            '2. Ke bawah, tanyakan "mengapa ini terjadi?" sampai menemukan penyebab yang bisa ditangani kebijakan. Penyebab paling bawah ditandai AKAR.\n'
            '3. Ke atas, tanyakan "lalu apa akibatnya?" untuk memetakan dampak.\n'
            "4. Tandai aspek kebijakan tiap penyebab untuk melihat di mana masalah menumpuk.\n"
            "5. Buka Pohon Tujuan untuk membalik setiap kondisi negatif menjadi kondisi yang diharapkan. Akar masalah berubah menjadi titik intervensi.\n\n"
            "Gunakan Berkas > Contoh Stunting Baru untuk melihat contoh lengkap."))

    def show_settings(self):
        from .settings_dialog import SettingsDialog
        SettingsDialog(self).exec()

    def show_about(self):
        about_dialog(self).exec()

    # ---- actions and menus

    def _act(self, text, fn, shortcut=None):
        a = QAction(text, self)
        a.triggered.connect(lambda *_: fn())
        if shortcut:
            a.setShortcut(QKeySequence(shortcut))
        return a

    def _build_actions(self):
        A = self._act
        self.a_new = A(L("Baru"), self.new_document, QKeySequence.New)
        self.a_sample = A(L("Contoh Stunting Baru"), self.new_sample)
        self.a_open = A(L("Buka…"), self.open_dialog, QKeySequence.Open)
        self.a_save = A(L("Simpan"), self.save, QKeySequence.Save)
        self.a_save_as = A(L("Simpan Sebagai…"), self.save_as, "Ctrl+Shift+S")
        self.a_png = A(L("Ekspor sebagai PNG…"), self.export_png, "Ctrl+E")
        self.a_pdf = A(L("Ekspor sebagai PDF…"), self.export_pdf, "Ctrl+Shift+E")
        self.a_outline = A(L("Salin Kerangka Teks"), self.copy_outline, "Ctrl+Shift+C")
        self.a_print = A(L("Cetak…"), self.print_tree, QKeySequence.Print)
        self.a_close = A(L("Tutup"), self.close, "Ctrl+W")
        self.a_quit = A(L("Keluar"), QApplication.closeAllWindows, "Ctrl+Q")

        self.a_undo = A(L("Batalkan"), lambda: self.doc.undo(), QKeySequence.Undo)
        self.a_redo = A(L("Ulangi"), lambda: self.doc.redo(), "Ctrl+Y")
        self.a_redo.setShortcuts([QKeySequence("Ctrl+Y"), QKeySequence("Ctrl+Shift+Z")])

        self.a_child = A(L("Tambah Turunan"), self.add_child, "Ctrl+Shift+N")
        self.a_effect = A(L("Tambah Dampak"), self.add_effect, "Ctrl+Shift+D")
        self.a_sibling = A(L("Tambah Simpul Sejajar"), self.add_sibling, "Ctrl+Alt+N")
        self.a_delete = A(L("Hapus Simpul"), self.delete_node, "Ctrl+Delete")
        self.a_left = A(L("Geser ke Kiri"), lambda: self.move_node(-1), "Ctrl+Alt+Left")
        self.a_right = A(L("Geser ke Kanan"), lambda: self.move_node(1), "Ctrl+Alt+Right")
        self.a_suggest = A(L("Usulkan Rumusan Tujuan"), self.suggest_objective, "Ctrl+Shift+U")
        self.a_suggest_all = A(L("Usulkan Semua Tujuan yang Kosong"), self.suggest_all)
        self.a_reset_levels = A(L("Kembalikan Gaya Semua Level"), self.reset_all_levels)

        self.a_problem = A(L("Pohon Masalah"), lambda: self.set_goal(False), "Ctrl+1")
        self.a_goal = A(L("Pohon Tujuan"), lambda: self.set_goal(True), "Ctrl+2")
        group = QActionGroup(self)
        for a in (self.a_problem, self.a_goal):
            a.setCheckable(True)
            group.addAction(a)
        self.a_zoom_in = A(L("Perbesar"), lambda: self.zoom_by(1.2), "Ctrl+=")
        self.a_zoom_in.setShortcuts([QKeySequence("Ctrl+="), QKeySequence("Ctrl++")])
        self.a_zoom_out = A(L("Perkecil"), lambda: self.zoom_by(1 / 1.2), "Ctrl+-")
        self.a_fit = A(L("Paskan ke Jendela"), self.zoom_fit, "Ctrl+0")
        self.a_inspector = A(L("Tampilkan Panel Kanan"), self.toggle_inspector, "Ctrl+Alt+I")
        self.a_guide = A(L("Cara Menyusun Pohon Masalah"), self.show_guide, "F1")
        self.a_settings = A(L("Pengaturan…"), self.show_settings, "Ctrl+,")
        self.a_site = A(L("Situs Pembuat"), lambda: QDesktopServices.openUrl(QUrl(AUTHOR_URL)))
        self.a_about = A(L("Tentang {0}", APP_NAME), self.show_about)

    def _build_menus(self):
        bar = self.menuBar()
        m = bar.addMenu(L("&Berkas"))
        m.addActions([self.a_new, self.a_sample, self.a_open])
        self.m_recent = m.addMenu(L("Buka Terkini"))
        self.m_recent.aboutToShow.connect(self._fill_recent)
        m.addSeparator()
        m.addActions([self.a_save, self.a_save_as])
        m.addSeparator()
        m.addActions([self.a_png, self.a_pdf, self.a_outline])
        m.addSeparator()
        m.addAction(self.a_print)
        m.addSeparator()
        m.addAction(self.a_settings)
        m.addSeparator()
        m.addActions([self.a_close, self.a_quit])
        m = bar.addMenu(L("&Edit"))
        m.addActions([self.a_undo, self.a_redo])
        m = bar.addMenu(L("&Pohon"))
        m.addActions([self.a_child, self.a_effect, self.a_sibling, self.a_delete])
        m.addSeparator()
        m.addActions([self.a_left, self.a_right])
        m.addSeparator()
        m.addActions([self.a_suggest, self.a_suggest_all])
        m.addSeparator()
        m.addAction(self.a_reset_levels)
        m = bar.addMenu(L("&Tampilan"))
        m.addActions([self.a_problem, self.a_goal])
        m.addSeparator()
        m.addActions([self.a_zoom_in, self.a_zoom_out, self.a_fit])
        m.addSeparator()
        m.addAction(self.a_inspector)
        m = bar.addMenu(L("B&antuan"))
        m.addActions([self.a_guide, self.a_site])
        m.addSeparator()
        m.addAction(self.a_about)

    def _fill_recent(self):
        self.m_recent.clear()
        items = recent_files()
        for path in items:
            a = self.m_recent.addAction(os.path.basename(path))
            a.setToolTip(path)
            a.triggered.connect(lambda *_, p=path: open_path(p, self))
        if items:
            self.m_recent.addSeparator()
            self.m_recent.addAction(L("Bersihkan Menu"), lambda: settings().setValue("recent", []))
        else:
            self.m_recent.addAction(L("Belum ada berkas")).setEnabled(False)

    def _build_toolbar(self):
        t = QToolBar(L("Bilah alat"))
        t.setObjectName("toolbar")
        t.setMovable(False)
        t.setToolButtonStyle(Qt.ToolButtonTextOnly)
        self.addToolBar(t)
        t.addActions([self.a_problem, self.a_goal])
        t.addSeparator()
        t.addActions([self.a_child, self.a_sibling, self.a_delete])
        t.addSeparator()
        t.addAction(self.a_fit)
        export = QToolButton()
        export.setText(L("Ekspor \u25BE"))
        export.setStyleSheet("QToolButton::menu-indicator { image: none; width: 0; }")
        export.setPopupMode(QToolButton.InstantPopup)
        m = QMenu(export)
        m.addActions([self.a_png, self.a_pdf, self.a_outline])
        export.setMenu(m)
        t.addWidget(export)

    def update_actions(self):
        doc = self.doc
        if doc is None:
            return
        loc = doc.tree.location(doc.selection)
        if not loc:
            return
        is_core = loc.side == CORE
        self.a_child.setText({CORE: L("Tambah Penyebab"), EFFECT: L("Tambah Dampak Lanjutan"), CAUSE: L("Tambah Sub-penyebab")}[loc.side])
        self.a_reset_levels.setEnabled(bool(doc.tree.levels))
        self.a_effect.setEnabled(is_core)
        self.a_sibling.setEnabled(not is_core)
        # Inside a text box Qt gives Ctrl+Delete to the box (delete word), so this never fires mid-typing.
        self.a_delete.setEnabled(not is_core)
        self.a_left.setEnabled(not is_core and loc.index > 0)
        self.a_right.setEnabled(not is_core and loc.index < loc.sibling_count - 1)
        self.a_undo.setEnabled(bool(doc.undo_name))
        self.a_undo.setText(L("Batalkan {0}", doc.undo_name) if doc.undo_name else L("Batalkan"))
        self.a_redo.setEnabled(bool(doc.redo_name))
        self.a_redo.setText(L("Ulangi {0}", doc.redo_name) if doc.redo_name else L("Ulangi"))
        self.a_goal.setChecked(self.goal)
        self.a_problem.setChecked(not self.goal)

    def context_menu(self, side):
        m = QMenu(self)
        m.addAction(self.a_child)
        if side == CORE:
            m.addAction(self.a_effect)
        else:
            m.addAction(self.a_sibling)
        m.addSeparator()
        m.addAction(self.a_suggest)
        if side != CORE:
            current = self.doc.tree.node(self.doc.selection).aspek
            sub = m.addMenu(L("Aspek Kebijakan"))
            for key, label in [("", L("Belum ditentukan"))] + [(k, L(v)) for k, v in ASPEK]:
                a = sub.addAction(label)
                a.setCheckable(True)
                a.setChecked(key == current)
                a.triggered.connect(lambda *_, k=key: self.set_aspek(k))
            m.addSeparator()
            m.addActions([self.a_left, self.a_right])
            m.addSeparator()
            m.addAction(self.a_delete)
        return m


def about_dialog(parent):
    d = QDialog(parent)
    d.setWindowTitle(L("Tentang {0}", APP_NAME))
    col = QVBoxLayout(d)
    col.setContentsMargins(32, 24, 32, 20)
    col.setSpacing(6)
    icon = QLabel()
    icon.setPixmap(app_icon().pixmap(96, 96))
    icon.setAlignment(Qt.AlignCenter)
    col.addWidget(icon)
    name = QLabel(f"<b style='font-size:16pt'>{APP_NAME}</b>")
    name.setAlignment(Qt.AlignCenter)
    col.addWidget(name)
    version = QLabel(L("Versi {0}", VERSION))
    version.setAlignment(Qt.AlignCenter)
    col.addWidget(version)
    body = QLabel(
        L("Alat penyusun pohon masalah dan pohon tujuan untuk analisis kebijakan.") + "<br><br>"
        + L("Dibuat oleh {0}", AUTHOR) + "<br>"
        f"<a href='{AUTHOR_URL}'>github.com/lemonspitz</a><br><br>"
        "<small>" + L("Dibangun dengan Qt dan PySide6 (LGPL-3.0). Lihat THIRD-PARTY.md.") + "</small>")
    body.setAlignment(Qt.AlignCenter)
    body.setWordWrap(True)
    body.setOpenExternalLinks(True)
    col.addWidget(body)
    buttons = QDialogButtonBox(QDialogButtonBox.Ok)
    buttons.accepted.connect(d.accept)
    col.addWidget(buttons)
    d.setMinimumWidth(360)
    return d


def _safe_name(s):
    cleaned = "".join("-" if c in '<>:"/\\|?*' or ord(c) < 32 else c for c in s).strip(" .")
    return cleaned or L("Pohon")


# ---- output

def render_png(tree, goal, path, scale=2.0):
    lay = render.layout(tree, goal)
    w, h = render.export_size(lay)
    img = QImage(int(w * scale), int(h * scale), QImage.Format_ARGB32_Premultiplied)
    img.fill(Qt.white)
    p = QPainter(img)
    p.scale(scale, scale)
    render.draw_export(p, tree, lay, goal)
    p.end()
    return img.save(path, "PNG")


def render_pdf(tree, goal, path):
    lay = render.layout(tree, goal)
    w, h = render.export_size(lay)
    writer = QPdfWriter(path)
    writer.setResolution(96)
    writer.setPageSize(QPageSize(QSizeF(w * 0.75, h * 0.75), QPageSize.Point))
    writer.setPageMargins(QMarginsF(0, 0, 0, 0))
    p = QPainter()
    if not p.begin(writer):
        return False
    render.draw_export(p, tree, lay, goal)
    return p.end()


def render_print(tree, goal, printer):
    """Scales the whole tree onto one page."""
    lay = render.layout(tree, goal)
    w, h = render.export_size(lay)
    p = QPainter()
    if not p.begin(printer):
        return False
    page = printer.pageRect(QPrinter.DevicePixel)
    s = min(page.width() / w, page.height() / h)
    p.translate((page.width() - w * s) / 2, (page.height() - h * s) / 2)
    p.scale(s, s)
    render.draw_export(p, tree, lay, goal)
    return p.end()
