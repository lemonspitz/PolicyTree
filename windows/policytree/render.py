"""Drawing shared by the canvas, export and printing."""
from __future__ import annotations

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QFontMetricsF, QPainter, QPainterPath, QPen, QPolygonF, QTextLayout, QTextOption

from . import layout as LY
from .i18n import L
from .model import CAUSE, CORE, EFFECT, level_key

LIGHT = dict(canvas="#F2F4F1", card="#FFFFFF", line="#D3D9D5", band="#E6EBE7", edge="#8C9893",
             effect="#9A5B14", core="#8C1D2A", cause="#1D5964", goal="#2D6A3B", goal_core="#2D6A3B",
             ink="#1C2220", muted="#5B6661", accent="#0A64C8",
             regulasi="#7A4FB0", kelembagaan="#1D5964", anggaran="#B0631A", sdm="#3F7D3A", sosbud="#B33A5B", infra="#4A6FA5")
DARK = dict(canvas="#151917", card="#212725", line="#38413D", band="#1D2321", edge="#6E7A75",
            effect="#E1A45C", core="#B23A4B", cause="#62B2BD", goal="#62B376", goal_core="#37804A",
            ink="#E4EAE7", muted="#99A49F", accent="#5AA9FF",
            regulasi="#A98AE0", kelembagaan="#62B2BD", anggaran="#E1A45C", sdm="#7FC17A", sosbud="#E37A96", infra="#86A8DE")

PAD_X, PAD_TOP, PAD_BOTTOM, META_H = 11.0, 10.0, 11.0, 19.0
CORE_PAD_X, CORE_PAD_Y = 16.0, 14.0
SANS = ["Segoe UI Variable Text", "Segoe UI", "Helvetica Neue", "Arial"]
MONO = ["Cascadia Mono", "Consolas", "Menlo", "Courier New"]
SERIF = ["Cambria", "Georgia", "Times New Roman"]


def font(families, px, weight=QFont.Normal, italic=False):
    f = QFont()
    f.setFamilies(families)
    f.setPixelSize(px)
    f.setWeight(weight)
    f.setItalic(italic)
    # Without this, text reflows as the canvas zooms and no longer fits its measured card.
    f.setHintingPreference(QFont.PreferNoHinting)
    return f


def default_kind_label(side, depth, goal):
    if side == CORE:
        return L("Tujuan utama") if goal else L("Masalah inti")
    if side == EFFECT:
        return L("{0} tingkat {1}", L("Manfaat") if goal else L("Dampak"), depth)
    return L("{0} tingkat {1}", L("Sarana") if goal else L("Penyebab"), depth)


def kind_label(side, depth, goal, levels=None):
    st = (levels or {}).get(level_key(side, depth), {})
    name = st.get("goalName" if goal else "name")
    return name.strip() if name else default_kind_label(side, depth, goal)


def style(levels, side, depth):
    return (levels or {}).get(level_key(side, depth), {})


def default_color_key(side, goal):
    if side == CORE:
        return "goal_core" if goal else "core"
    return "goal" if goal else side


def level_color(st, side, goal, colors):
    """A chosen colour wins in both views; otherwise the built-in one for this theme."""
    return QColor(st["color"]) if st.get("color") else QColor(colors[default_color_key(side, goal)])


def inset(shape):
    """Extra inner room so text stays clear of slanted or curved edges (same as the Mac)."""
    return {"pill": (10.0, 0.0), "hexagon": (16.0, 0.0), "ellipse": (24.0, 9.0)}.get(shape, (0.0, 0.0))


def shape_path(shape, r: QRectF, grow=0.0):
    f = r.adjusted(-grow, -grow, grow, grow)
    path = QPainterPath()
    if shape == "rect":
        path.addRoundedRect(f, 1.5 + grow, 1.5 + grow)
    elif shape == "pill":
        rad = min(f.height() / 2, 26 + grow)
        path.addRoundedRect(f, rad, rad)
    elif shape == "ellipse":
        path.addEllipse(f)
    elif shape == "hexagon":
        cut = min(18 + grow, f.height() / 2)
        path.addPolygon(QPolygonF([QPointF(f.left() + cut, f.top()), QPointF(f.right() - cut, f.top()),
                                   QPointF(f.right(), f.center().y()), QPointF(f.right() - cut, f.bottom()),
                                   QPointF(f.left() + cut, f.bottom()), QPointF(f.left(), f.center().y())]))
        path.closeSubpath()
    else:
        path.addRoundedRect(f, 7 + grow, 7 + grow)
    return path


def display(node, goal):
    """(text, pending): pending text is a placeholder, drawn differently."""
    if not goal:
        return (node.text, False) if node.text else (L("(kosong)"), True)
    if not node.obj.strip():
        return (L("Belum dirumuskan: ") + node.text, True)
    return (node.obj, False)


def _text_font(side, pending):
    return font(SERIF, 18, QFont.Medium, pending) if side == CORE else font(SANS, 14, QFont.Normal, pending)


def _lay_out(text, f, width):
    """Wraps at words, and inside a word only when it can't fit a line. Returns (layout, height)."""
    option = QTextOption()
    option.setWrapMode(QTextOption.WrapAtWordBoundaryOrAnywhere)
    tl = QTextLayout(text.replace("\n", " "), f)
    tl.setTextOption(option)
    tl.beginLayout()
    y = 0.0
    while True:
        line = tl.createLine()
        if not line.isValid():
            break
        line.setLineWidth(width)
        line.setPosition(QPointF(0, y))
        y += line.height()
    tl.endLayout()
    return tl, y


def card_height(node, side, goal, shape=None):
    text, pending = display(node, goal)
    ix, iy = inset(shape)
    width = (LY.CORE_W - CORE_PAD_X * 2 if side == CORE else LY.NODE_W - PAD_X * 2) - ix * 2
    _, h = _lay_out(text, _text_font(side, pending), width)
    return ((CORE_PAD_Y * 2 + META_H + h) if side == CORE else (PAD_TOP + META_H + h + PAD_BOTTOM)) + iy * 2


def layout(tree, goal):
    return LY.compute(tree, lambda n, side, depth: card_height(n, side, goal, tree.level(side, depth).get("shape")))


def add_buttons(item):
    d, gap, f = 24.0, 10.0, item.frame
    up = LY.Rect(f.cx - d / 2, f.y - gap - d, d, d)
    down = LY.Rect(f.cx - d / 2, f.bottom + gap, d, d)
    if item.side == CORE:
        return [(up, EFFECT), (down, CAUSE)]
    return [(up, EFFECT)] if item.side == EFFECT else [(down, CAUSE)]


def q(r):
    return QRectF(r.x, r.y, r.w, r.h)


def draw(p: QPainter, lay, goal, selection, colors, focused=False):
    c = {k: QColor(v) for k, v in colors.items()}
    p.setRenderHint(QPainter.Antialiasing)
    for side, rect in lay.bands:
        _draw_band(p, side, rect, goal, c)
    _draw_edges(p, lay, c)
    for item in lay.items:
        _draw_node(p, item, goal, c, lay.levels)
    if selection:
        it = lay.item(selection)
        if it:
            _draw_selection(p, it, focused, c, style(lay.levels, it.side, it.depth).get("shape"))


def _draw_band(p, side, rect, goal, c):
    p.setPen(Qt.NoPen)
    p.setBrush(c["band"])
    p.drawRoundedRect(q(rect), 6, 6)
    label = {EFFECT: L("MANFAAT") if goal else L("DAMPAK"), CORE: L("TUJUAN") if goal else L("INTI"),
             CAUSE: L("SARANA") if goal else L("PENYEBAB")}[side]
    f = font(MONO, 11, QFont.Medium)
    f.setLetterSpacing(QFont.AbsoluteSpacing, 1.4)
    p.save()
    p.setFont(f)
    p.setPen(c["muted"])
    p.translate(rect.cx, rect.cy)
    p.rotate(-90)
    p.drawText(QRectF(-rect.h / 2, -rect.w / 2, rect.h, rect.w), Qt.AlignCenter, label)
    p.restore()


def _draw_edges(p, lay, c):
    pen = QPen(c["edge"], 1.5)
    pen.setJoinStyle(Qt.MiterJoin)
    for pts in lay.edges:
        tip = pts[-1]
        path = QPainterPath(QPointF(*pts[0]))
        for pt in pts[1:-1]:
            path.lineTo(QPointF(*pt))
        path.lineTo(QPointF(tip[0], tip[1] + 6))
        p.setPen(pen)
        p.setBrush(Qt.NoBrush)
        p.drawPath(path)
        p.setPen(Qt.NoPen)
        p.setBrush(c["edge"])
        p.drawPolygon(QPolygonF([QPointF(*tip), QPointF(tip[0] - 4.5, tip[1] + 8), QPointF(tip[0] + 4.5, tip[1] + 8)]))


def _text(p, text, f, color, x, y, width):
    tl, _ = _lay_out(text, f, width)
    p.setPen(color)
    tl.draw(p, QPointF(x, y))


def _draw_node(p, item, goal, c, levels):
    st = style(levels, item.side, item.depth)
    form = st.get("shape", "rounded")
    accent = level_color(st, item.side, goal, c)
    ix, iy = inset(form)
    f = item.frame
    r = q(f)
    shape = shape_path(form, r)
    # soft shadow
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(0, 0, 0, 20))
    p.drawPath(shape.translated(0, 2))
    text, pending = display(item.node, goal)
    if item.side == CORE:
        p.setBrush(accent)
        p.drawPath(shape)
        meta = font(MONO, 11)
        meta.setLetterSpacing(QFont.AbsoluteSpacing, 0.5)
        white = QColor(255, 255, 255)
        faded = QColor(255, 255, 255, 205)
        x, y, w = f.x + CORE_PAD_X + ix, f.y + CORE_PAD_Y + iy, f.w - (CORE_PAD_X + ix) * 2
        p.setFont(meta)
        p.setPen(faded)
        label = kind_label(CORE, 0, goal, levels).upper()
        p.drawText(QRectF(x, y, w, META_H), Qt.AlignLeft | Qt.AlignTop, QFontMetricsF(meta).elidedText(label, Qt.ElideRight, w))
        _text(p, text, _text_font(CORE, pending), faded if pending else white, x, y + META_H, w)
        return

    p.setBrush(c["card"])
    p.drawPath(shape)
    if st.get("color"):
        # A light wash of a chosen colour makes the level readable at a glance.
        wash = QColor(accent)
        wash.setAlphaF(0.09)
        p.setBrush(wash)
        p.drawPath(shape)
    line = shape_path(form, r.adjusted(0.5, 0.5, -0.5, -0.5))
    p.setBrush(Qt.NoBrush)
    if form in ("rounded", "rect", "pill"):
        p.save()
        p.setClipPath(shape)
        p.setPen(Qt.NoPen)
        p.setBrush(accent)
        p.drawRect(QRectF(f.x, f.y if item.side == EFFECT else f.bottom - 3, f.w, 3))
        p.restore()
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(c["line"], 1))
    else:
        # A bar would be clipped to a sliver on slanted or curved edges, so the outline carries the colour.
        pen = QPen(accent, 2)
        pen.setJoinStyle(Qt.RoundJoin)
        p.setPen(pen)
    p.drawPath(line)

    x = f.x + PAD_X + ix
    right = f.right - PAD_X - ix
    y = f.y + PAD_TOP + iy
    if item.node.aspek_label:
        p.setPen(Qt.NoPen)
        p.setBrush(c[item.node.aspek])
        p.drawEllipse(QRectF(x, y + 3.5, 8, 8))
        x += 13
    # A level the user named shows that name; otherwise the aspect, as before.
    named = st.get("goalName" if goal else "name")
    meta_text = kind_label(item.side, item.depth, goal, levels) if named else (
        item.node.aspek_label or kind_label(item.side, item.depth, goal, levels))
    meta = font(MONO, 11)
    fm = QFontMetricsF(meta)
    badge = (L("INTERVENSI") if goal else L("AKAR")) if item.is_root_cause else None
    bf = font(MONO, 9, QFont.Medium)
    bw = QFontMetricsF(bf).horizontalAdvance(badge) + 8 if badge else 0.0
    room = max(right - x - (bw + 7 if badge else 0), 20)
    meta_text = fm.elidedText(meta_text, Qt.ElideRight, room)
    p.setFont(meta)
    p.setPen(c["muted"])
    p.drawText(QRectF(x, y, room + 1, META_H), Qt.AlignLeft | Qt.AlignTop, meta_text)
    x += fm.horizontalAdvance(meta_text) + 7
    if badge:
        rect = QRectF(x, y + 0.5, bw, 14)
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(accent, 1))
        p.drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), 3, 3)
        p.setFont(bf)
        p.drawText(rect, Qt.AlignCenter, badge)
    _text(p, text, _text_font(item.side, pending), c["muted"] if pending else c["ink"],
          f.x + PAD_X + ix, y + META_H, f.w - (PAD_X + ix) * 2)


def _draw_selection(p, item, focused, c, shape=None):
    p.setBrush(Qt.NoBrush)
    pen = QPen(c["accent"] if focused else c["muted"], 2.5)
    pen.setJoinStyle(Qt.RoundJoin)
    p.setPen(pen)
    p.drawPath(shape_path(shape or "rounded", q(item.frame), 3.5))
    for rect, _ in add_buttons(item):
        p.setBrush(c["card"])
        p.setPen(QPen(c["edge"], 1))
        p.drawEllipse(q(rect))
        pen = QPen(c["ink"], 1.8)
        pen.setCapStyle(Qt.RoundCap)
        p.setPen(pen)
        p.drawLine(QPointF(rect.cx - 5, rect.cy), QPointF(rect.cx + 5, rect.cy))
        p.drawLine(QPointF(rect.cx, rect.cy - 5), QPointF(rect.cx, rect.cy + 5))


# ---- whole-tree output: always light, with a title line

HEADER = 70.0


def export_size(lay):
    return max(lay.width, 560.0), lay.height + HEADER


def draw_export(p, tree, lay, goal):
    w, h = export_size(lay)
    c = {k: QColor(v) for k, v in LIGHT.items()}
    p.fillRect(QRectF(0, 0, w, h), QColor("#FFFFFF"))
    eyebrow = font(MONO, 11, QFont.Medium)
    eyebrow.setLetterSpacing(QFont.AbsoluteSpacing, 1.2)
    p.setFont(eyebrow)
    p.setPen(c["muted"])
    p.drawText(QRectF(24, 16, w - 48, 16), Qt.AlignLeft, L("POHON TUJUAN") if goal else L("POHON MASALAH"))
    title = font(SERIF, 22, QFont.DemiBold)
    p.setFont(title)
    p.setPen(c["ink"])
    p.drawText(QRectF(24, 32, w - 48, 32), Qt.AlignLeft | Qt.AlignVCenter,
               QFontMetricsF(title).elidedText(tree.title, Qt.ElideRight, w - 48))
    p.save()
    p.translate((w - lay.width) / 2, HEADER)
    draw(p, lay, goal, None, LIGHT)
    p.restore()
