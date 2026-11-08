"""Settings window, the Windows counterpart of Sources/Settings.swift."""
from __future__ import annotations

import sys

from PySide6.QtCore import QProcess, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QDialog, QDialogButtonBox, QFormLayout, QLabel,
                               QPushButton, QVBoxLayout)

from . import i18n
from .i18n import L

LANGUAGE, APPEARANCE, PNG_SCALE, KEY_HINTS = "language", "appearance", "pngScale", "showKeyHints"


def _settings():
    from .window import settings
    return settings()


def get(key, default):
    v = _settings().value(key, default)
    if isinstance(default, bool):
        return v if isinstance(v, bool) else str(v).lower() in ("true", "1")
    if isinstance(default, int):
        try:
            return int(v)
        except (TypeError, ValueError):
            return default
    return v if isinstance(v, str) else default


def language_pref():
    return get(LANGUAGE, "id")


def png_scale():
    s = get(PNG_SCALE, 2)
    return float(s if s in (1, 2, 3) else 2)


def show_key_hints():
    return get(KEY_HINTS, True)


def apply_appearance():
    """Light/dark override for the whole app; 'system' follows Windows. The canvas
    repaints through the colorSchemeChanged signal each window already listens to."""
    scheme = {"light": Qt.ColorScheme.Light, "dark": Qt.ColorScheme.Dark}.get(get(APPEARANCE, "system"),
                                                                             Qt.ColorScheme.Unknown)
    hints = QGuiApplication.styleHints()
    if hasattr(hints, "setColorScheme"):  # Qt 6.8+: also restyles menus, dialogs and scroll bars
        hints.setColorScheme(scheme)
    from .window import _windows
    for w in _windows:  # the canvas colours come from is_dark(), so repaint even if no signal fires
        w._theme_changed()


def restart():
    """Closes every window the normal way (each may ask to save), then starts the app again."""
    from .window import _windows
    for w in list(_windows):
        if not w.close():
            return False
    # The packaged .exe is sys.executable itself; in development it is Python running run.py.
    args = [] if getattr(sys, "frozen", False) else [sys.argv[0]]
    QProcess.startDetached(sys.executable, args)
    QApplication.instance().quit()
    return True


class SettingsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle(L("Pengaturan"))
        self.setMinimumWidth(460)
        col = QVBoxLayout(self)
        self.form = form = QFormLayout()
        form.setLabelAlignment(Qt.AlignRight | Qt.AlignVCenter)
        form.setVerticalSpacing(10)
        col.addLayout(form)

        self.language = QComboBox()
        self.language.setAccessibleName(L("Bahasa"))
        for code, label in i18n.CHOICES:
            self.language.addItem(L(label) if code == "system" else label, code)
        self._select(self.language, language_pref())
        self.language.activated.connect(self._language_changed)
        form.addRow(L("Bahasa"), self.language)
        self.restart_note = QLabel()
        self.restart_note.setWordWrap(True)
        self.restart_button = QPushButton(L("Mulai Ulang Sekarang"))
        self.restart_button.clicked.connect(restart)
        form.addRow("", self.restart_note)
        form.addRow("", self.restart_button)

        self.appearance = QComboBox()
        self.appearance.setAccessibleName(L("Tema"))
        for label, code in ((L("Ikuti sistem"), "system"), (L("Terang"), "light"), (L("Gelap"), "dark")):
            self.appearance.addItem(label, code)
        self._select(self.appearance, get(APPEARANCE, "system"))
        self.appearance.activated.connect(self._appearance_changed)
        form.addRow(L("Tema"), self.appearance)

        self.scale = QComboBox()
        self.scale.setAccessibleName(L("Resolusi PNG"))
        for label, v in ((L("Standar (1×)"), 1), (L("Tajam (2×)"), 2), (L("Sangat tajam (3×)"), 3)):
            self.scale.addItem(label, v)
        self._select(self.scale, int(png_scale()))
        self.scale.activated.connect(lambda: _settings().setValue(PNG_SCALE, self.scale.currentData()))
        form.addRow(L("Resolusi PNG"), self.scale)

        self.hints = QCheckBox(L("Tampilkan petunjuk keyboard di panel kanan"))
        self.hints.setChecked(show_key_hints())
        self.hints.toggled.connect(self._hints_changed)
        form.addRow("", self.hints)

        buttons = QDialogButtonBox(QDialogButtonBox.Close)
        buttons.button(QDialogButtonBox.Close).setText(L("Tutup"))
        buttons.rejected.connect(self.reject)
        col.addWidget(buttons)
        self._update_note()

    @staticmethod
    def _select(combo, value):
        i = combo.findData(value)
        combo.setCurrentIndex(max(i, 0))

    def _update_note(self):
        pending = i18n.resolve(language_pref()) != i18n.code
        self.restart_note.setText(
            L("Bahasa baru dipakai setelah Policy Tree dimulai ulang. Anda akan ditanya untuk menyimpan perubahan.")
            if pending else L("Mengganti bahasa memerlukan memulai ulang aplikasi."))
        self.form.setRowVisible(self.restart_button, pending)

    def _language_changed(self):
        _settings().setValue(LANGUAGE, self.language.currentData())
        self._update_note()

    def _appearance_changed(self):
        _settings().setValue(APPEARANCE, self.appearance.currentData())
        apply_appearance()

    def _hints_changed(self, on):
        _settings().setValue(KEY_HINTS, bool(on))
        from .window import _windows
        for w in _windows:
            w.inspector.key_hints.setVisible(bool(on))
