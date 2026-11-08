from __future__ import annotations

import os
import sys

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication, QMessageBox

from . import APP_NAME, VERSION, document, i18n, settings_dialog
from .i18n import L
from .window import _windows, app_icon, open_path, open_window


def _offer_recovery():
    found = list(document.pending_recoveries())
    if not found:
        return False
    box = QMessageBox(QMessageBox.Question, APP_NAME, L("Ada {0} pohon yang belum tersimpan saat aplikasi terakhir ditutup.", len(found)))
    box.setInformativeText(L("Pulihkan sekarang? Jika dibuang, perubahan tersebut hilang."))
    restore = box.addButton(L("Pulihkan"), QMessageBox.AcceptRole)
    box.addButton(L("Buang"), QMessageBox.DestructiveRole)
    box.exec()
    restored = box.clickedButton() is restore
    for path, doc in found:
        if restored:
            open_window(doc)
        try:
            os.unlink(path)
        except OSError:
            pass
    return restored


def _selfcheck(app):
    """For the packaged build: proves the bundle has what it needs. Reports by exit code, since a
    windowed .exe has no console. Nonzero codes say which part failed."""
    import tempfile

    from PySide6.QtPrintSupport import QPrinter

    from .model import Tree
    from .window import render_pdf, render_png, render_print
    if app_icon().isNull():
        return 2
    from . import i18n as _i18n
    if _i18n.init("en") != "en" or _i18n.L("Pohon Masalah") == "Pohon Masalah":
        return 6  # strings_en.json missing from the bundle
    _i18n.init(settings_dialog.language_pref())
    tree = Tree.sample()
    with tempfile.TemporaryDirectory() as folder:
        if not render_png(tree, False, os.path.join(folder, "a.png")):
            return 3
        if not render_pdf(tree, True, os.path.join(folder, "a.pdf")):
            return 4
        printer = QPrinter(QPrinter.HighResolution)
        printer.setOutputFormat(QPrinter.PdfFormat)
        printer.setOutputFileName(os.path.join(folder, "p.pdf"))
        if not render_print(tree, False, printer):
            return 5
    w = open_window()
    QTimer.singleShot(500, lambda: (w.close(), app.exit(0)))
    return app.exec()


def main(argv=None):
    argv = list(sys.argv if argv is None else argv)
    if sys.platform == "win32":
        # Gives the taskbar our icon instead of grouping the app under Python.
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("lemonspitz.PolicyTree")
    app = QApplication(argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(VERSION)
    app.setOrganizationName("lemonspitz")
    app.setWindowIcon(app_icon())
    # Language first: everything built after this point reads it.
    i18n.init(settings_dialog.language_pref())
    settings_dialog.apply_appearance()

    if "--selfcheck" in argv:
        return _selfcheck(app)

    restored = _offer_recovery()
    files = [a for a in argv[1:] if not a.startswith("-")]
    for path in files:
        open_path(path)
    if not _windows and not restored:
        open_window()
    return app.exec()
