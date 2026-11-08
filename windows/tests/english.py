"""The interface in English: menus, inspector, canvas and settings, with screenshots.
Usage: python tests/english.py <screenshot folder>"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
os.environ.setdefault("POLICYTREE_RECOVERY", tempfile.mkdtemp())

from PySide6.QtCore import QSettings
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from policytree import i18n, window
from policytree.document import Document
from policytree.model import CAUSE, Tree
from policytree.settings_dialog import SettingsDialog

shots = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp()
os.makedirs(shots, exist_ok=True)
_ini = os.path.join(tempfile.mkdtemp(), "s.ini")
window.settings = lambda: QSettings(_ini, QSettings.IniFormat)
failures = []


def check(c, msg):
    if not c:
        failures.append(msg)
        print("GAGAL:", msg, flush=True)


app = QApplication(sys.argv)
i18n.init("en")
w = window.open_window(Document(Tree.sample()))
QTest.qWaitForWindowExposed(w)
QTest.qWait(80)
menus = [a.text() for a in w.menuBar().actions()]
check(menus == ["&File", "&Edit", "&Tree", "&View", "&Help"], f"menu: {menus}")
check(w.a_undo.text() == "Undo" and w.a_settings.text() == "Settings…", "aksi")
first = w.doc.tree.causes[0]
w.doc.select(first.id)
QTest.qWait(30)
check(w.inspector.kind.text() == "Cause level 1", f"inspektor: {w.inspector.kind.text()}")
check(w.inspector.text_label.text() == "Cause statement", "label rumusan")
check(w.inspector.aspek.itemText(1) == "Regulation", "aspek")
check(w.inspector.level_shape.itemText(3) == "Hexagon", "bentuk")
labels = [i.node.aspek_label for i in w.canvas.lay.items if i.node.aspek_label]
check("Socio-cultural" in labels, "label aspek di kanvas")
w.add_under(first.id, CAUSE)
check(w.doc.tree.node(w.doc.selection).text == "New sub-cause", "simpul baru berbahasa Inggris")
w.doc.undo()
w.grab().save(os.path.join(shots, "english.png"))
w.set_goal(True)
QTest.qWait(30)
w.grab().save(os.path.join(shots, "english-goal.png"))
d = SettingsDialog(w)
d.show()
QTest.qWait(30)
check(d.windowTitle() == "Settings" and d.language.itemText(0) == "Follow system", "dialog pengaturan")
d.grab().save(os.path.join(shots, "english-settings.png"))
d.close()
w.confirm_discard = lambda: True
w.close()
print("Uji bahasa Inggris lulus." if not failures else f"{len(failures)} uji bahasa Inggris gagal.", flush=True)
sys.exit(1 if failures else 0)
