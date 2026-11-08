"""Drives a real window with real key and mouse events, and saves screenshots to argv[1]."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
TMP = tempfile.mkdtemp(prefix="policytree-test-")
os.environ["POLICYTREE_RECOVERY"] = os.path.join(TMP, "recovery")

from PySide6.QtCore import QEvent, QPoint, QSettings, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtPrintSupport import QPrinter
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication, QPlainTextEdit

import policytree
from policytree import document, render, window
from policytree.document import Document
from policytree.main import _offer_recovery
from policytree.model import CAUSE, CORE_ID, EFFECT, Tree

shots = sys.argv[1] if len(sys.argv) > 1 else os.path.join(TMP, "shots")
os.makedirs(shots, exist_ok=True)
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("GAGAL:", msg, flush=True)


# Never touch the user's real settings.
_ini = os.path.join(TMP, "settings.ini")
window.settings = lambda: QSettings(_ini, QSettings.IniFormat)

app = QApplication(["policytree-test"])
app.setApplicationName(policytree.APP_NAME)


def spin():
    QTest.qWait(10)


w = window.open_window()
QTest.qWaitForWindowExposed(w)
w.activateWindow()
QTest.qWaitForWindowActive(w, 2000)
spin()
doc, canvas, ins = w.doc, w.canvas, w.inspector


def key(k, mods=Qt.NoModifier, target=None):
    QTest.keyClick(target or QApplication.focusWidget() or canvas, k, mods)
    spin()


def typing(s):
    QTest.keyClicks(QApplication.focusWidget(), s)
    spin()


def click(x, y, double=False):
    p = QPoint(int(x * canvas.zoom), int(y * canvas.zoom))
    if double:
        QTest.mouseDClick(canvas, Qt.LeftButton, Qt.NoModifier, p)
    else:
        QTest.mouseClick(canvas, Qt.LeftButton, Qt.NoModifier, p)
    spin()


def editing():
    return isinstance(QApplication.focusWidget(), QPlainTextEdit)


# ---- keyboard on the canvas

w.focus_canvas()
spin()
check(QApplication.focusWidget() is canvas, "kanvas fokus")
before = doc.tree.cause_count
key(Qt.Key_Tab, target=canvas)
check(doc.tree.cause_count == before + 1, "Tab menambah penyebab")
check(editing(), "fokus pindah ke kotak teks")
new_id = doc.selection
typing("Anggaran kurang")
check(doc.tree.node(new_id).text == "Anggaran kurang", f"mengetik mengganti teks: {doc.tree.node(new_id).text!r}")
check(ins.b_child.text() == "+ Sub-penyebab", "tombol mengikuti simpul")

# one run of typing is one undo step, and Ctrl+Z reaches the document from inside a text box
key(Qt.Key_Z, Qt.ControlModifier)
check(doc.tree.node(new_id).text == "Penyebab baru", f"Ctrl+Z dari kotak teks: {doc.tree.node(new_id).text!r}")
doc.undo(); spin()
check(doc.tree.cause_count == before and doc.selection == CORE_ID, "batalkan penambahan")
doc.redo(); doc.redo(); spin()
check(doc.tree.node(new_id).text == "Anggaran kurang", "ulangi dua langkah")
check(ins.text.toPlainText() == "Anggaran kurang", "panel mengikuti ulangi")

# Tab / Return / Esc inside the text box
doc.select(new_id)
w.focus_editor(True); spin()
key(Qt.Key_Tab)
sub = doc.selection
check(doc.tree.location(sub).parent_id == new_id, "Tab di kotak teks menambah turunan")
check(doc.tree.node(sub).text == "Sub-penyebab baru", "tab tidak masuk ke teks")
key(Qt.Key_Return)
second = doc.selection
check(doc.tree.location(second).parent_id == new_id and second != sub, "Enter di kotak teks menambah sejajar")
key(Qt.Key_Return, Qt.ShiftModifier)
check("\n" in ins.text.toPlainText() or " " in ins.text.toPlainText(), "Shift+Enter membuat baris baru")
key(Qt.Key_Escape)
check(QApplication.focusWidget() is canvas, "Esc kembali ke kanvas")

# arrows and Delete
key(Qt.Key_Left); check(doc.selection == sub, "panah kiri")
key(Qt.Key_Up); check(doc.selection == new_id, "panah atas ke induk")
key(Qt.Key_Down); check(doc.selection == sub, "panah bawah ke anak")
key(Qt.Key_Delete)
check(doc.tree.node(sub) is None and doc.selection == second, "Delete memilih saudara")
doc.undo(); spin()
check(doc.tree.node(sub) is not None and doc.selection == sub, "batalkan hapus")
doc.select(CORE_ID); w.focus_canvas(); spin()
total = doc.tree.cause_count
key(Qt.Key_Delete)
check(doc.tree.cause_count == total, "masalah inti tak bisa dihapus")
e0 = doc.tree.effect_count
key(Qt.Key_Backtab, target=canvas)
check(doc.tree.effect_count == e0 + 1, "Shift+Tab dari inti menambah dampak")
doc.undo(); w.focus_canvas(); spin()

# ---- mouse

target = canvas.lay.item(new_id).frame
click(target.cx, target.cy)
check(doc.selection == new_id, "klik memilih simpul")
plus = render.add_buttons(canvas.lay.item(new_id))[0][0]
n0 = doc.tree.cause_count
click(plus.cx, plus.cy)
check(doc.tree.cause_count == n0 + 1, "tombol + menambah")
core = canvas.lay.item(CORE_ID).frame
w.focus_canvas(); spin()
click(core.cx, core.cy, double=True)
check(doc.selection == CORE_ID and editing(), "klik ganda membuka penyunting")
w.focus_canvas(); spin()
up = next(r for r, side in render.add_buttons(canvas.lay.item(CORE_ID)) if side == EFFECT)
e0 = doc.tree.effect_count
click(up.cx, up.cy)
check(doc.tree.effect_count == e0 + 1, "tombol + atas menambah dampak")
check(any(a.menu() for a in w.context_menu(CAUSE).actions()), "menu konteks punya submenu aspek")

# ---- goal view edits the objective only

w.set_goal(True); spin()
doc.select(new_id); w.focus_editor(True); spin()
text_before = doc.tree.node(new_id).text
typing("Anggaran cukup")
check(doc.tree.node(new_id).obj == "Anggaran cukup" and doc.tree.node(new_id).text == text_before, "tujuan tersunting terpisah")
w.set_goal(False); spin()
doc.apply("x", lambda t: setattr(t.node(new_id), "text", "Anggaran kurang"))
doc.apply("x", lambda t: setattr(t.node(new_id), "obj", ""))
w.suggest_objective(); spin()
check(doc.tree.node(new_id).obj == "Anggaran cukup", "usulkan tujuan")
w.suggest_all(); spin()
check(doc.tree.core.obj, "isi semua tujuan")

# ---- level style from the inspector

doc.select(new_id); spin()
ins.level_name.setFocus(); spin()
typing("Penyebab langsung")
check(doc.tree.levels.get("cause.1", {}).get("name") == "Penyebab langsung", f"nama level: {doc.tree.levels}")
check(ins.kind.text() == "Penyebab langsung", "nama level tampil di inspektor")
doc.undo(); spin()
check("cause.1" not in doc.tree.levels, "nama level dibatalkan sebagai satu langkah")
doc.redo(); spin()
w.focus_canvas(); spin()
ins.level_shape.setCurrentIndex(ins.level_shape.findData("hexagon"))
ins.level_shape.activated.emit(ins.level_shape.currentIndex()); spin()
check(doc.tree.levels["cause.1"].get("shape") == "hexagon", "bentuk level")
ins.set_level_color("#bf382b"); spin()
check(doc.tree.levels["cause.1"].get("color") == "#BF382B", "warna level")
check(ins.level_color_default.isEnabled() and ins.level_reset.isEnabled(), "tombol bawaan aktif")
check(canvas.lay.levels == doc.tree.levels, "kanvas memakai gaya terbaru")
w.grab().save(os.path.join(shots, "level-style.png"))
w.set_goal(True); spin()
check(ins.level_name.toPlainText() == "", "pohon tujuan punya nama level sendiri")
ins.level_name.setFocus(); spin()
typing("Sarana langsung")
check(doc.tree.levels["cause.1"].get("goalName") == "Sarana langsung" and doc.tree.levels["cause.1"]["name"] == "Penyebab langsung", "nama tujuan terpisah")
w.set_goal(False); w.focus_canvas(); spin()
check(w.a_reset_levels.isEnabled(), "kembalikan semua aktif saat ada gaya")
w.a_reset_levels.trigger(); spin()
check(doc.tree.levels == {} and not w.a_reset_levels.isEnabled(), "kembalikan semua gaya")
doc.undo(); spin()
check(doc.tree.levels["cause.1"].get("shape") == "hexagon", "batalkan pengembalian gaya")
ins.reset_level(); spin()
check("cause.1" not in doc.tree.levels, "kembalikan gaya satu level")

# ---- actions

doc.select(CORE_ID); spin()
check(not w.a_delete.isEnabled() and not w.a_sibling.isEnabled(), "aksi nonaktif pada inti")
check(w.a_child.text() == "Tambah Penyebab", "judul menu mengikuti simpul")
check(w.a_undo.isEnabled() and w.a_undo.text().startswith("Batalkan "), "menu batalkan menyebut aksinya")
doc.select(new_id); spin()
check(w.a_delete.isEnabled(), "hapus aktif pada simpul")
for a in (w.a_problem, w.a_goal):
    a.trigger(); spin()
check(w.goal, "aksi tampilan")
w.a_problem.trigger(); spin()
check(not w.goal, "kembali ke pohon masalah")

# ---- zoom

w.zoom_fit(); spin()
check(0.29 < canvas.zoom <= 1.0, f"paskan: {canvas.zoom}")
z = canvas.zoom
w.zoom_by(10); check(canvas.zoom == 2.0, "batas zoom atas")
w.zoom_by(0.001); check(canvas.zoom == 0.3, "batas zoom bawah")
w.zoom_fit(); spin()

# ---- output

png, pdf, prn = (os.path.join(TMP, n) for n in ("a.png", "a.pdf", "print.pdf"))
check(window.render_png(doc.tree, False, png), "PNG tertulis")
check(open(png, "rb").read(4) == b"\x89PNG", "PNG valid")
check(window.render_pdf(doc.tree, True, pdf), "PDF tertulis")
check(open(pdf, "rb").read(4) == b"%PDF", "PDF valid")
printer = QPrinter(QPrinter.HighResolution)
printer.setOutputFormat(QPrinter.PdfFormat)
printer.setOutputFileName(prn)
check(window.render_print(doc.tree, False, printer) and os.path.getsize(prn) > 1000, "cetak ke PDF")
check(not window.render_png(doc.tree, False, os.path.join(TMP, "tidak-ada", "x.png")), "folder salah dilaporkan gagal")
w.copy_outline()
check(QApplication.clipboard().text().startswith("POHON MASALAH"), "salin kerangka")
window.about_dialog(w).grab().save(os.path.join(shots, "about.png"))
about_text = " ".join(l.text() for l in window.about_dialog(w).findChildren(window.QLabel))
check("@lemonspitz" in about_text and "github.com/lemonspitz" in about_text and "Versi 1.0" in about_text, "kredit dan versi")

# ---- files, recovery and closing

path = os.path.join(TMP, "uji.policytree")
check(doc.dirty and w.isWindowModified(), "tanda belum tersimpan")
check(w._save_to(path), "simpan")
check(not doc.dirty and not w.isWindowModified() and os.path.basename(path) in w.windowTitle(), "judul setelah simpan")
check(window.recent_files() == [os.path.abspath(path)], "berkas terkini")
check(Document.load(path).tree == doc.tree, "simpan lalu buka sama")
check(not [f for f in os.listdir(TMP) if f.startswith(".policytree-")], "tidak ada berkas sementara")

old = doc.tree.to_json()
bad = os.path.join(TMP, "rusak.policytree")
open(bad, "w").write("bukan json")
errors = []
window._error = lambda parent, text, detail: errors.append(text)
check(window.open_path(bad, w) is None and errors and "bukan pohon masalah" in errors[0], "berkas rusak ditolak")
check(doc.tree.to_json() == old, "berkas rusak tidak mengubah pohon")
check(window.open_path(os.path.join(TMP, "hilang.policytree"), w) is None, "berkas hilang dilaporkan")
check(window.open_path(path, w) is w, "berkas yang sudah terbuka difokuskan")
bom = os.path.join(TMP, "bom.json")
open(bom, "w", encoding="utf-8-sig").write(Tree.sample().to_json())
w2 = window.open_path(bom, w)
check(w2 is not None and w2 is not w and w2.doc.tree.cause_count == 10, "JSON ber-BOM dari Notepad terbuka")
w2.close(); spin()

# recovery: unsaved edits survive a crash, and saving removes the copy
doc.apply("x", lambda t: setattr(t, "title", "Belum disimpan"))
w.write_recovery()
found = list(document.pending_recoveries())
check(len(found) == 1 and found[0][1].tree.title == "Belum disimpan" and found[0][1].dirty and found[0][1].path == path, "salinan pemulihan")
open(os.path.join(os.environ["POLICYTREE_RECOVERY"], "rusak.json"), "w").write("{")
check(len(list(document.pending_recoveries())) == 1, "salinan rusak dilewati")
os.unlink(os.path.join(os.environ["POLICYTREE_RECOVERY"], "rusak.json"))
check(w._save_to(path) and not list(document.pending_recoveries()), "simpan membersihkan salinan")

# closing with unsaved work asks first
doc.apply("x", lambda t: setattr(t, "title", "Lagi"))
w.confirm_discard = lambda: False
w.close(); spin()
check(w.isVisible(), "batal menutup menjaga jendela")
w.confirm_discard = lambda: True
doc.apply("x", lambda t: setattr(t, "title", "Terakhir"))
w.write_recovery()

# ---- long text keeps the layout clean; screenshots

doc.select(new_id)
doc.apply("x", lambda t: setattr(t.node(new_id), "text", "kata panjang " * 60 + "x" * 300))
spin()
items = canvas.lay.items
for i, a in enumerate(items):
    for b in items[i + 1:]:
        check(not a.frame.intersects(b.frame), "teks panjang tumpang tindih")

sample = window.open_window(Document(Tree.sample()))
QTest.qWaitForWindowExposed(sample)
QTest.qWait(50)
check(sample.canvas.zoom < 1.0, f"pohon contoh dipaskan: {sample.canvas.zoom}")
from PySide6.QtGui import QColor, QPalette
check(sample.area.viewport().palette().color(QPalette.Window) == QColor(sample.colors()["canvas"]), "sekitar kanvas mengikuti warna kanvas")
check(sample.grab().toImage().pixelColor(sample.area.mapTo(sample, QPoint(3, 3))) == QColor(sample.colors()["canvas"]), "piksel sekitar kanvas")
check(sample.inspector.palette().color(QPalette.PlaceholderText) == QColor(sample.colors()["muted"]), "warna petunjuk")
sample.grab().save(os.path.join(shots, "window.png"))
sample.set_goal(True); spin()
sample.grab().save(os.path.join(shots, "window-goal.png"))
sample.set_goal(False)
window.render_png(Tree.sample(), False, os.path.join(shots, "export.png"))
for name, colors in (("dark", render.DARK),):
    window.MainWindow.colors = lambda self, c=colors: c
    sample._theme_changed(); spin()
    sample.grab().save(os.path.join(shots, f"window-{name}.png"))
    window.MainWindow.colors = lambda self: render.LIGHT

# ---- settings dialog

from policytree import i18n, settings_dialog
from policytree.settings_dialog import SettingsDialog
dlg = SettingsDialog(w)
dlg.show(); spin()
check(dlg.language.currentData() == "id" and not dlg.restart_button.isVisible(), "bahasa awal Indonesia, tanpa tombol mulai ulang")
dlg.language.setCurrentIndex(dlg.language.findData("en")); dlg.language.activated.emit(dlg.language.currentIndex()); spin()
check(settings_dialog.language_pref() == "en" and dlg.restart_button.isVisible(), "bahasa tersimpan, tombol mulai ulang muncul")
check(i18n.code == "id", "bahasa yang sedang dipakai tetap sampai dimulai ulang")
dlg.language.setCurrentIndex(dlg.language.findData("id")); dlg.language.activated.emit(dlg.language.currentIndex()); spin()
check(not dlg.restart_button.isVisible(), "tombol mulai ulang hilang lagi")
dlg.appearance.setCurrentIndex(dlg.appearance.findData("dark")); dlg.appearance.activated.emit(dlg.appearance.currentIndex()); spin()
check(settings_dialog.get(settings_dialog.APPEARANCE, "") == "dark", "tema tersimpan")
check(window.is_dark(), "tema gelap dipakai (colors() membaca is_dark)")
w.grab().save(os.path.join(shots, "settings-dark.png"))
dlg.appearance.setCurrentIndex(dlg.appearance.findData("system")); dlg.appearance.activated.emit(dlg.appearance.currentIndex()); spin()
dlg.scale.setCurrentIndex(dlg.scale.findData(3)); dlg.scale.activated.emit(dlg.scale.currentIndex()); spin()
check(settings_dialog.png_scale() == 3.0, "resolusi PNG")
dlg.hints.setChecked(False); spin()
check(not ins.key_hints.isVisible() and not settings_dialog.show_key_hints(), "petunjuk keyboard disembunyikan")
dlg.hints.setChecked(True); spin()
check(ins.key_hints.isVisible(), "petunjuk keyboard tampil lagi")
dlg.grab().save(os.path.join(shots, "settings.png"))
dlg.close()
check(w.a_settings.shortcut().toString() == "Ctrl+,", "pintasan pengaturan")

# ---- files shared with the Mac app (only where its binary is available)

mac = os.environ.get("POLICYTREE_MAC_BIN")
if mac:
    from_win = os.path.join(TMP, "dari-windows.policytree")
    Document(Tree.sample()).save(from_win)
    out = os.path.join(TMP, "dari-windows.png")
    check(subprocess.run([mac, "--render", from_win, out]).returncode == 0 and os.path.getsize(out) > 1000, "Mac membuka berkas dari Windows")
    from_mac = os.path.join(TMP, "dari-mac.policytree")
    subprocess.run([mac, "--write-sample", from_mac], check=True)
    loaded = Document.load(from_mac).tree
    check(loaded.cause_count == 10 and loaded.effect_count == 5, "Windows membuka berkas dari Mac")
    check(json.loads(loaded.to_json()) == json.load(open(from_mac, encoding="utf-8")), "isi berkas Mac identik setelah dibaca")
    styled = Tree.sample()
    styled.update_level(CAUSE, 1, lambda d: d.update(name="Penyebab langsung", goalName="Sarana", color="#C0392B", shape="hexagon"))
    styled.update_level("core", 0, lambda d: d.update(shape="ellipse"))
    styled_path, resaved = os.path.join(TMP, "gaya.policytree"), os.path.join(TMP, "gaya-mac.policytree")
    Document(styled).save(styled_path)
    subprocess.run([mac, "--resave", styled_path, resaved], check=True)
    check(json.load(open(resaved, encoding="utf-8")) == json.load(open(styled_path, encoding="utf-8")), "gaya level utuh lewat aplikasi Mac")

for x in list(window._windows):
    x.confirm_discard = lambda: True
    x.close()
shutil.rmtree(TMP, ignore_errors=True)
print("Uji UI lulus." if not failures else f"{len(failures)} uji UI gagal.", flush=True)
sys.exit(1 if failures else 0)
