from __future__ import annotations

from PySide6.QtCore import QEvent, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QKeySequence, QPainter, QPalette
from PySide6.QtWidgets import (QColorDialog, QComboBox, QFrame, QHBoxLayout, QLabel, QPlainTextEdit, QPushButton, QScrollArea,
                               QSizePolicy, QVBoxLayout, QWidget)

from . import render
from .i18n import L
from .model import ASPEK, CAUSE, CORE, CORE_ID, EFFECT, SHAPES, level_key, suggest_objective


class Editor(QPlainTextEdit):
    """Edits go only through the document's undo, so the box's own history stays off."""

    def __init__(self, height, name):
        super().__init__()
        self.setFixedHeight(height)
        self.setAccessibleName(name)
        self.setUndoRedoEnabled(False)
        self.setTabChangesFocus(False)
        self.on_change = self.on_tab = self.on_backtab = self.on_return = self.on_escape = self.on_focus = None
        self.textChanged.connect(self._changed)
        self._quiet = False

    def set_text(self, s):
        if self.toPlainText() != s:
            self._quiet = True
            self.setPlainText(s)
            self._quiet = False

    def _changed(self):
        if not self._quiet and self.on_change:
            self.on_change(self.toPlainText())

    def event(self, e):
        if e.type() == QEvent.ShortcutOverride and (e.matches(QKeySequence.Undo) or e.matches(QKeySequence.Redo)):
            e.ignore()   # let the Edit menu take these
            return True
        if e.type() == QEvent.KeyPress and e.key() in (Qt.Key_Tab, Qt.Key_Backtab):
            cb = self.on_backtab if e.key() == Qt.Key_Backtab else self.on_tab
            if cb:
                cb()
            return True
        return super().event(e)

    def keyPressEvent(self, e):
        if e.key() in (Qt.Key_Return, Qt.Key_Enter) and not (e.modifiers() & Qt.ShiftModifier):
            if self.on_return:
                self.on_return()
        elif e.key() == Qt.Key_Escape:
            if self.on_escape:
                self.on_escape()
        else:
            super().keyPressEvent(e)

    def focusInEvent(self, e):
        if self.on_focus:
            self.on_focus()
        super().focusInEvent(e)


class ColorButton(QPushButton):
    """Shows the level colour; clicking opens the system colour picker."""

    def __init__(self):
        super().__init__()
        self.setFixedSize(52, 24)
        self.setAccessibleName(L("Warna level"))
        self.color = "#000000"

    def paintEvent(self, e):
        super().paintEvent(e)
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self.color))
        p.drawRoundedRect(QRectF(self.rect()).adjusted(5, 5, -5, -5), 7, 7)


def shape_icon(shape, color):
    from PySide6.QtGui import QIcon, QPixmap
    pm = QPixmap(26, 16)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    p.setPen(QColor(color))
    path = render.shape_path(shape, QRectF(2, 2, 22, 12))
    if shape == "hexagon":
        path = render.QPainterPath()
        path.addPolygon(render.QPolygonF([render.QPointF(x, y) for x, y in
                                          ((6, 2), (20, 2), (24, 8), (20, 14), (6, 14), (2, 8), (6, 2))]))
    elif shape == "rounded":
        path = render.QPainterPath()
        path.addRoundedRect(QRectF(2, 2, 22, 12), 3, 3)
    p.drawPath(path)
    p.end()
    return QIcon(pm)


class Swatch(QWidget):
    def __init__(self, size=12, radius=2):
        super().__init__()
        self.setFixedSize(size, size)
        self.radius = radius
        self.color = "#000000"

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self.color))
        p.drawRoundedRect(QRectF(self.rect()), self.radius, self.radius)


class Bar(QWidget):
    def __init__(self, label, count, fraction, color, track):
        super().__init__()
        self.setFixedHeight(20)
        self.label, self.count, self.fraction, self.color, self.track = label, count, fraction, color, track
        self.setAccessibleName(f"{label}: {count}")

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        label_w, count_w = 112, 22
        p.setPen(self.palette().windowText().color())
        p.drawText(QRectF(0, 0, label_w, self.height()), Qt.AlignVCenter | Qt.AlignLeft, self.label)
        track = QRectF(label_w + 6, self.height() / 2 - 3.5, max(0, self.width() - label_w - count_w - 12), 7)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(self.track))
        p.drawRoundedRect(track, 3.5, 3.5)
        p.setBrush(QColor(self.color))
        p.drawRoundedRect(QRectF(track.x(), track.y(), max(7, track.width() * self.fraction), 7), 3.5, 3.5)
        p.setPen(self.palette().windowText().color())
        p.drawText(QRectF(0, 0, self.width(), self.height()), Qt.AlignVCenter | Qt.AlignRight, str(self.count))


class RootRow(QWidget):
    """One root cause in the summary; clicking selects it on the canvas."""

    def __init__(self, text, color, action):
        super().__init__()
        self.action = action
        self.setCursor(Qt.PointingHandCursor)
        self.setFocusPolicy(Qt.TabFocus)
        self.setAccessibleName(text)
        row = QHBoxLayout(self)
        row.setContentsMargins(0, 2, 0, 2)
        row.setSpacing(8)
        dot = Swatch(8, 4)
        dot.color = color
        row.addWidget(dot, 0, Qt.AlignTop)
        label = QLabel(text)
        label.setWordWrap(True)
        label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        label.setTextFormat(Qt.PlainText)
        row.addWidget(label, 1)

    def mouseReleaseEvent(self, e):
        if e.button() == Qt.LeftButton and self.rect().contains(e.position().toPoint()):
            self.action()

    def keyPressEvent(self, e):
        if e.key() in (Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space):
            self.action()
        else:
            super().keyPressEvent(e)


def _muted(l):
    # Inspector.reload sets this role to the theme's muted colour. A disabled label would read
    # as unavailable, both visually and to screen readers.
    l.setForegroundRole(QPalette.PlaceholderText)
    return l


def _heading(s):
    l = QLabel(s.upper())
    l.setFont(render.font(render.MONO, 11, QFont.Medium))
    return _muted(l)


def _field_label(s=""):
    l = QLabel(s)
    f = l.font()
    f.setBold(True)
    l.setFont(f)
    return l


def _hint(s=""):
    l = QLabel(s)
    l.setWordWrap(True)
    return _muted(l)


class Inspector(QScrollArea):
    def __init__(self, window):
        super().__init__()
        self.win = window
        self.setWidgetResizable(True)
        self.setFrameShape(QFrame.NoFrame)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.setMinimumWidth(310)
        body = QWidget()
        self.setWidget(body)
        col = QVBoxLayout(body)
        col.setContentsMargins(16, 16, 16, 24)
        col.setSpacing(6)

        self.title = Editor(48, L("Judul analisis"))
        col.addWidget(_field_label(L("Judul analisis")))
        col.addWidget(self.title)
        col.addSpacing(14)

        col.addWidget(_heading(L("Simpul terpilih")))
        self.swatch = Swatch()
        self.kind = QLabel()
        self.kind.setFont(render.font(render.SERIF, 19, QFont.DemiBold))
        kind_row = QHBoxLayout()
        kind_row.setSpacing(8)
        kind_row.addWidget(self.swatch)
        kind_row.addWidget(self.kind, 1)
        col.addLayout(kind_row)
        col.addSpacing(4)

        self.text_label = _field_label()
        self.text = Editor(88, L("Rumusan"))
        self.hint = _hint()
        col.addWidget(self.text_label)
        col.addWidget(self.text)
        col.addWidget(self.hint)
        col.addSpacing(8)

        col.addWidget(_field_label(L("Rumusan tujuan (untuk pohon tujuan)")))
        self.obj = Editor(68, L("Rumusan tujuan"))
        col.addWidget(self.obj)
        self.suggest = QPushButton(L("Usulkan dari rumusan masalah"))
        self.suggest.clicked.connect(lambda: self.win.suggest_objective())
        col.addWidget(self.suggest, 0, Qt.AlignLeft)
        col.addSpacing(8)

        self.aspek_row = QWidget()
        ar = QHBoxLayout(self.aspek_row)
        ar.setContentsMargins(0, 0, 0, 0)
        ar.addWidget(_field_label(L("Aspek kebijakan")))
        self.aspek = QComboBox()
        self.aspek.setAccessibleName(L("Aspek kebijakan"))
        self.aspek.addItem(L("Belum ditentukan"), "")
        for key, label in ASPEK:
            self.aspek.addItem(L(label), key)
        self.aspek.activated.connect(self._aspek_changed)
        ar.addWidget(self.aspek, 1)
        col.addWidget(self.aspek_row)
        col.addSpacing(8)

        buttons = QHBoxLayout()
        buttons.setSpacing(6)
        self.b_effect = QPushButton(L("+ Dampak"))
        self.b_child = QPushButton()
        self.b_sibling = QPushButton(L("Sejajar"))
        self.b_delete = QPushButton(L("Hapus"))
        self.b_effect.clicked.connect(lambda: self.win.add_under(CORE_ID, EFFECT))
        self.b_child.clicked.connect(lambda: self.win.add_child())
        self.b_sibling.clicked.connect(lambda: self.win.add_sibling())
        self.b_delete.clicked.connect(lambda: self.win.delete_node())
        for b in (self.b_effect, self.b_child, self.b_sibling, self.b_delete):
            buttons.addWidget(b)
        buttons.addStretch(1)
        col.addLayout(buttons)
        self.key_hints = _hint(L("Di kanvas: Tab menambah turunan, Enter menambah sejajar, Delete menghapus, tombol panah "
                                 "berpindah simpul. Di kotak teks: Tab dan Enter bekerja sama, Esc kembali ke kanvas, "
                                 "Shift+Enter membuat baris baru."))
        col.addWidget(self.key_hints)
        from .settings_dialog import show_key_hints
        self.key_hints.setVisible(show_key_hints())
        col.addSpacing(18)

        # Level style: applies to every node on the selected node's level.
        col.addWidget(_heading(L("Gaya level")))
        self.level_scope = _hint()
        col.addWidget(self.level_scope)
        col.addSpacing(4)
        self.level_name_label = _field_label()
        self.level_name = Editor(32, L("Nama level"))
        self.level_name_hint = _hint()
        col.addWidget(self.level_name_label)
        col.addWidget(self.level_name)
        col.addWidget(self.level_name_hint)
        col.addSpacing(6)
        color_row = QHBoxLayout()
        color_row.setSpacing(8)
        cl = _field_label(L("Warna"))
        cl.setFixedWidth(56)
        self.level_color = ColorButton()
        self.level_color.clicked.connect(self._pick_color)
        self.level_color_default = QPushButton(L("Warna bawaan"))
        self.level_color_default.clicked.connect(lambda: self.set_level_color(None))
        color_row.addWidget(cl)
        color_row.addWidget(self.level_color)
        color_row.addWidget(self.level_color_default)
        color_row.addStretch(1)
        col.addLayout(color_row)
        shape_row = QHBoxLayout()
        shape_row.setSpacing(8)
        sl = _field_label(L("Bentuk"))
        sl.setFixedWidth(56)
        self.level_shape = QComboBox()
        self.level_shape.setAccessibleName(L("Bentuk level"))
        for key, label in SHAPES:
            self.level_shape.addItem(L(label), key)
        self.level_shape.activated.connect(self._shape_changed)
        shape_row.addWidget(sl)
        shape_row.addWidget(self.level_shape, 1)
        col.addLayout(shape_row)
        self.level_reset = QPushButton(L("Kembalikan gaya bawaan level ini"))
        self.level_reset.clicked.connect(self.reset_level)
        col.addWidget(self.level_reset, 0, Qt.AlignLeft)
        col.addSpacing(18)
        self._level = (CORE, 0)
        self._level_goal = False
        self._icon_color = None

        self.summary = QVBoxLayout()
        self.summary.setSpacing(6)
        col.addLayout(self.summary)
        col.addStretch(1)
        self._signature = None
        self._wire()

    def _wire(self):
        back = lambda: self.win.focus_canvas()
        self.title.on_focus = lambda: self.win.doc.end_coalescing()
        self.title.on_change = lambda s: self.win.doc.apply(L("Ubah Judul"), lambda t: setattr(t, "title", s), coalesce="title")
        self.title.on_tab = self.title.on_return = self.title.on_escape = back
        self.title.on_backtab = back

        for editor, key, name in ((self.text, "text", L("Ubah Rumusan")), (self.obj, "obj", L("Ubah Tujuan"))):
            editor.on_focus = lambda: self.win.doc.end_coalescing()
            editor.on_change = self._change_handler(key, name)
            editor.on_escape = back
            editor.on_tab = lambda: self.win.add_under(self.win.doc.selection, CAUSE)
            editor.on_backtab = self._backtab
            editor.on_return = self._return

        self.level_name.on_focus = lambda: self.win.doc.end_coalescing()
        self.level_name.on_change = self._level_name_changed
        self.level_name.on_tab = self.level_name.on_return = self.level_name.on_escape = back
        self.level_name.on_backtab = back

    # ---- level style

    def _edit_level(self, name, fn, coalesce=None):
        side, depth = self._level
        self.win.doc.apply(name, lambda t: t.update_level(side, depth, fn), coalesce=coalesce)

    def _level_name_changed(self, s):
        k = "goalName" if self._level_goal else "name"
        self._edit_level(L("Ubah Nama Level"), lambda st: st.__setitem__(k, s),
                         coalesce=f"levelname:{k}:{level_key(*self._level)}")

    def set_level_color(self, hex_color):
        self._edit_level(L("Ubah Warna Level"), lambda st: st.__setitem__("color", hex_color))

    def _pick_color(self):
        c = QColorDialog.getColor(QColor(self.level_color.color), self, L("Warna level"))
        if c.isValid():
            self.set_level_color(c.name().upper())

    def _shape_changed(self):
        raw = self.level_shape.currentData()
        self._edit_level(L("Ubah Bentuk Level"), lambda st: st.__setitem__("shape", None if raw == "rounded" else raw))

    def reset_level(self):
        self._edit_level(L("Kembalikan Gaya Level"), lambda st: st.clear())

    def _reload_level(self, tree, side, depth, goal, colors):
        self._level, self._level_goal = (side, depth), goal
        st = tree.level(side, depth)
        built_in = render.default_kind_label(side, depth, goal)
        self.level_scope.setText(
            (L("Mengatur tampilan kotak tujuan utama.") if goal else L("Mengatur tampilan kotak masalah inti.")) if side == CORE else
            L("Berlaku untuk {0} simpul di {1}.", tree.node_count(side, depth), built_in.lower()))
        self.level_name_label.setText(L("Nama level di pohon tujuan") if goal else L("Nama level di pohon masalah"))
        self.level_name.set_text(st.get("goalName" if goal else "name", ""))
        self.level_name_hint.setText(L('Kosongkan untuk memakai nama bawaan "{0}". Nama ini tampil di setiap kotak pada level ini.', built_in))
        self.level_color.color = render.level_color(st, side, goal, colors).name()
        self.level_color.update()
        self.level_color_default.setEnabled("color" in st)
        if self._icon_color != colors["ink"]:
            self._icon_color = colors["ink"]
            for i, (key, _) in enumerate(SHAPES):
                self.level_shape.setItemIcon(i, shape_icon(key, colors["ink"]))
        self.level_shape.setCurrentIndex(max(self.level_shape.findData(st.get("shape", "rounded")), 0))
        self.level_reset.setEnabled(bool(st))

    def _change_handler(self, key, name):
        def handler(s):
            doc = self.win.doc
            node_id = doc.selection
            doc.apply(name, lambda t: setattr(t.node(node_id), key, s), coalesce=f"{key}:{node_id}")
        return handler

    def _backtab(self):
        if self.win.doc.selection == CORE_ID:
            self.win.add_under(CORE_ID, EFFECT)

    def _return(self):
        if self.win.doc.selection == CORE_ID:
            self.win.focus_canvas()
        else:
            self.win.add_sibling()

    def _aspek_changed(self):
        doc = self.win.doc
        node_id, raw = doc.selection, self.aspek.currentData()
        doc.apply(L("Ubah Aspek"), lambda t: setattr(t.node(node_id), "aspek", raw))

    def focus_editor(self, goal, select_all=False):
        e = self.obj if goal else self.text
        e.setFocus()
        if select_all:
            e.selectAll()

    def reload(self, goal):
        doc = self.win.doc
        tree, node, loc = doc.tree, doc.tree.node(doc.selection), doc.tree.location(doc.selection)
        if not node:
            return
        colors = self.win.colors()
        pal = self.palette()
        pal.setColor(QPalette.PlaceholderText, QColor(colors["muted"]))
        self.setPalette(pal)
        self.title.set_text(tree.title)
        self.text.set_text(node.text)
        self.obj.set_text(node.obj)
        st = tree.level(loc.side, loc.depth)
        self.swatch.color = render.level_color(st, loc.side, goal, colors).name()
        self.swatch.radius = 6 if st.get("shape") in ("pill", "ellipse") else 2
        self.swatch.update()
        self.kind.setText(render.kind_label(loc.side, loc.depth, goal, tree.levels))
        self._reload_level(tree, loc.side, loc.depth, goal, colors)
        words = {
            CORE: (L("Rumusan masalah inti"), 'Satu kondisi negatif yang ingin diatasi kebijakan. Hindari menulis solusi, misalnya "kurangnya program X".', L("+ Penyebab")),
            EFFECT: (L("Rumusan dampak"), L("Akibat yang muncul bila masalah di bawahnya dibiarkan."), L("+ Dampak lanjutan")),
            CAUSE: (L("Rumusan penyebab"), L("Mengapa masalah di atasnya terjadi? Tulis sebagai kondisi negatif."), L("+ Sub-penyebab")),
        }[loc.side]
        self.text_label.setText(words[0])
        self.hint.setText(words[1])
        self.b_child.setText(words[2])
        is_core = loc.side == CORE
        self.aspek_row.setVisible(not is_core)
        self.b_effect.setVisible(is_core)
        self.b_sibling.setVisible(not is_core)
        self.b_delete.setVisible(not is_core)
        i = self.aspek.findData(node.aspek)
        self.aspek.setCurrentIndex(i if i >= 0 else 0)
        self._reload_summary(tree, goal, colors)

    def _reload_summary(self, tree, goal, colors):
        roots = tree.root_causes
        counts = tree.aspek_counts()

        def root_text(n):
            return (n.obj or suggest_objective(n.text)) if goal else n.text
        sig = (goal, tree.effect_count, tree.cause_count, tree.cause_depth, sorted(counts.items()), id(colors),
               [(n.id, n.aspek, root_text(n)) for n in roots])
        if sig == self._signature:
            return
        self._signature = sig
        while self.summary.count():
            it = self.summary.takeAt(0)
            if it.widget():
                it.widget().deleteLater()
            elif it.layout():
                sub = it.layout()
                while sub.count():
                    w = sub.takeAt(0).widget()
                    if w:
                        w.deleteLater()

        self.summary.addWidget(_heading(L("Ringkasan analisis")))
        stats = QHBoxLayout()
        stats.setSpacing(6)
        for value, caption in ((tree.effect_count, L("Manfaat|jumlah") if goal else L("Dampak|jumlah")),
                               (tree.cause_count, L("Sarana|jumlah") if goal else L("Penyebab|jumlah")),
                               (len(roots), L("Intervensi") if goal else L("Akar masalah")),
                               (tree.cause_depth, L("Kedalaman"))):
            box = QWidget()
            box.setAccessibleName(f"{caption}: {value}")
            v = QVBoxLayout(box)
            v.setContentsMargins(0, 0, 0, 0)
            v.setSpacing(0)
            number = QLabel(str(value))
            number.setFont(render.font(render.SERIF, 23, QFont.DemiBold))
            v.addWidget(number)
            cap = _hint(caption)
            v.addWidget(cap)
            v.addStretch(1)
            stats.addWidget(box, 1)
        self.summary.addLayout(stats)
        self.summary.addSpacing(8)

        if tree.cause_count:
            self.summary.addWidget(_hint(L("Sebaran sarana per aspek kebijakan") if goal else L("Sebaran penyebab per aspek kebijakan")))
            top = max(counts.values())
            for key, label in [(k, L(v)) for k, v in ASPEK] + [("", L("Belum ditentukan"))]:
                n = counts.get(key, 0)
                if n:
                    self.summary.addWidget(Bar(label, n, n / top, colors[key] if key else colors["edge"], colors["band"]))
            self.summary.addSpacing(8)

        self.summary.addWidget(_hint(L("Titik intervensi kebijakan (sarana paling dasar). Klik untuk memilih.") if goal else
                                     L("Akar masalah, yaitu penyebab paling dasar yang menjadi titik intervensi. Klik untuk memilih.")))
        if not roots:
            self.summary.addWidget(_hint(L("Belum ada penyebab.")))
        for n in roots:
            self.summary.addWidget(RootRow(root_text(n), colors[n.aspek] if n.aspek in colors else colors["edge"],
                                           self._go(n.id)))

    def _go(self, node_id):
        def go():
            self.win.doc.select(node_id)
            self.win.canvas.reveal_selection()
        return go
