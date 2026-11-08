from __future__ import annotations

from PySide6.QtCore import QEvent, QPoint, QSize, Qt
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QScrollArea, QWidget

from . import render
from .i18n import L
from .layout import Layout
from .model import CAUSE, CORE, CORE_ID, EFFECT

MIN_ZOOM, MAX_ZOOM = 0.3, 2.0


class TreeCanvas(QWidget):
    def __init__(self, window):
        super().__init__()
        self.win = window
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAccessibleName(L("Kanvas pohon"))
        self.setContextMenuPolicy(Qt.DefaultContextMenu)
        self.lay = Layout()
        self.zoom = 1.0
        self.tree = None
        self.selection = CORE_ID
        self.goal = False
        self._pan = None

    def reload(self, tree, selection, goal):
        self.tree, self.selection, self.goal = tree, selection, goal
        self.lay = render.layout(tree, goal)
        self._resize()
        self.update()

    def _resize(self):
        self.setFixedSize(QSize(int(self.lay.width * self.zoom) + 1, int(self.lay.height * self.zoom) + 1))

    def set_zoom(self, z):
        self.zoom = max(MIN_ZOOM, min(MAX_ZOOM, z))
        self._resize()
        self.update()

    def reveal_selection(self):
        it = self.lay.item(self.selection)
        area = self._area()
        if it and area:
            f = it.frame
            area.ensureVisible(int(f.cx * self.zoom), int(f.cy * self.zoom),
                               int((f.w / 2 + 30) * self.zoom), int((f.h / 2 + 44) * self.zoom))

    def _area(self):
        w = self.parentWidget()
        while w and not isinstance(w, QScrollArea):
            w = w.parentWidget()
        return w

    def paintEvent(self, _):
        colors = self.win.colors()
        p = QPainter(self)
        p.fillRect(self.rect(), QColor(colors["canvas"]))
        p.scale(self.zoom, self.zoom)
        render.draw(p, self.lay, self.goal, self.selection, colors, focused=self.hasFocus())

    def focusInEvent(self, e):
        self.update()
        super().focusInEvent(e)

    def focusOutEvent(self, e):
        self.update()
        super().focusOutEvent(e)

    # ---- mouse

    def _pos(self, e):
        pos = e.position()
        return pos.x() / self.zoom, pos.y() / self.zoom

    def mousePressEvent(self, e):
        if e.button() != Qt.LeftButton:
            return
        self.setFocus()
        x, y = self._pos(e)
        sel = self.lay.item(self.selection)
        if sel:
            for rect, side in render.add_buttons(sel):
                if rect.contains(x, y):
                    self.win.add_under(sel.node.id, side)
                    return
        it = self.lay.item_at(x, y)
        if it:
            self.win.doc.select(it.node.id)
            return
        area = self._area()
        if area:
            self._pan = (e.globalPosition().toPoint(), area.horizontalScrollBar().value(), area.verticalScrollBar().value())
            self.setCursor(Qt.ClosedHandCursor)

    def mouseDoubleClickEvent(self, e):
        x, y = self._pos(e)
        it = self.lay.item_at(x, y)
        if it and e.button() == Qt.LeftButton:
            self.win.doc.select(it.node.id)
            self.win.focus_editor()

    def mouseMoveEvent(self, e):
        if self._pan:
            start, hv, vv = self._pan
            d = e.globalPosition().toPoint() - start
            area = self._area()
            area.horizontalScrollBar().setValue(hv - d.x())
            area.verticalScrollBar().setValue(vv - d.y())

    def mouseReleaseEvent(self, e):
        self._pan = None
        self.unsetCursor()

    def wheelEvent(self, e):
        if e.modifiers() & Qt.ControlModifier:
            self.set_zoom(self.zoom * (1.1 if e.angleDelta().y() > 0 else 1 / 1.1))
            e.accept()
        else:
            e.ignore()

    def contextMenuEvent(self, e):
        x, y = e.pos().x() / self.zoom, e.pos().y() / self.zoom
        it = self.lay.item_at(x, y)
        if it:
            self.setFocus()
            self.win.doc.select(it.node.id)
            self.win.context_menu(it.side).exec(e.globalPos())

    # ---- keyboard

    def event(self, e):
        # Qt would otherwise spend Tab on moving focus before keyPressEvent sees it.
        if e.type() == QEvent.KeyPress and e.key() in (Qt.Key_Tab, Qt.Key_Backtab):
            if not (e.modifiers() & (Qt.ControlModifier | Qt.AltModifier)):
                side = EFFECT if e.key() == Qt.Key_Backtab else CAUSE
                if side == EFFECT and self.selection != CORE_ID:
                    return True
                self.win.add_under(self.selection, side)
                return True
        return super().event(e)

    def keyPressEvent(self, e):
        k = e.key()
        if e.modifiers() & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier):
            super().keyPressEvent(e)
        elif k in (Qt.Key_Return, Qt.Key_Enter):
            if self.selection == CORE_ID:
                self.win.focus_editor()
            else:
                self.win.add_sibling()
        elif k in (Qt.Key_Delete, Qt.Key_Backspace):
            if self.selection != CORE_ID:
                self.win.delete_node()
        elif k == Qt.Key_F2:
            self.win.focus_editor()
        elif k == Qt.Key_Left:
            self._sideways(-1)
        elif k == Qt.Key_Right:
            self._sideways(1)
        elif k == Qt.Key_Down:
            self._vertical(True)
        elif k == Qt.Key_Up:
            self._vertical(False)
        else:
            super().keyPressEvent(e)

    def _sideways(self, delta):
        loc = self.tree.location(self.selection)
        if not loc or loc.side == CORE:
            return
        arr = self.tree.siblings(self.selection)
        i = loc.index + delta
        if 0 <= i < len(arr):
            self.win.doc.select(arr[i].id)
            self.reveal_selection()

    def _vertical(self, down):
        loc = self.tree.location(self.selection)
        node = self.tree.node(self.selection)
        if not loc:
            return
        if loc.side == CORE:
            arr = self.tree.causes if down else self.tree.effects
            target = arr[0].id if arr else None
        elif (loc.side == CAUSE) == down:
            target = node.children[0].id if node.children else None
        else:
            target = loc.parent_id
        if target:
            self.win.doc.select(target)
            self.reveal_selection()
