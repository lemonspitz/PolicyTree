"""Tree geometry, same as Sources/Layout.swift. Every arrow points up: cause -> problem -> effect."""
from __future__ import annotations

from dataclasses import dataclass, field

from .model import CAUSE, CORE, CORE_ID, EFFECT

NODE_W = 200.0
CORE_W = 280.0
GAP_X = 22.0
GAP_Y = 64.0
PAD = 56.0
GUTTER = 30.0


@dataclass
class Rect:
    x: float
    y: float
    w: float
    h: float

    @property
    def right(self):
        return self.x + self.w

    @property
    def bottom(self):
        return self.y + self.h

    @property
    def cx(self):
        return self.x + self.w / 2

    @property
    def cy(self):
        return self.y + self.h / 2

    def contains(self, px, py):
        return self.x <= px <= self.right and self.y <= py <= self.bottom

    def intersects(self, o):
        return self.x < o.right and o.x < self.right and self.y < o.bottom and o.y < self.bottom


@dataclass
class Item:
    node: object
    side: str
    depth: int
    parent_id: str | None
    is_root_cause: bool
    frame: Rect


@dataclass
class Layout:
    items: list = field(default_factory=list)
    edges: list = field(default_factory=list)  # polylines; the last point is the arrow tip
    bands: list = field(default_factory=list)  # (side, Rect)
    width: float = 0.0
    height: float = 0.0
    levels: dict = field(default_factory=dict)

    def item(self, node_id):
        return next((i for i in self.items if i.node.id == node_id), None)

    def item_at(self, x, y):
        for i in reversed(self.items):
            if i.frame.contains(x, y):
                return i
        return None


def compute(tree, height) -> Layout:
    """`height(node, side, depth)` measures a card; keeping it a callback keeps this free of Qt."""
    raw = {CORE_ID: dict(node=tree.core, side=CORE, depth=0, parent=None, root=False, h=height(tree.core, CORE, 0), x=0.0)}
    order = [CORE_ID]
    level = {EFFECT: {}, CAUSE: {}}
    widths = {}

    def collect(arr, side, depth, parent):
        for n in arr:
            h = height(n, side, depth)
            raw[n.id] = dict(node=n, side=side, depth=depth, parent=parent, root=side == CAUSE and not n.children, h=h, x=0.0)
            order.append(n.id)
            level[side][depth] = max(level[side].get(depth, 0.0), h)
            collect(n.children, side, depth + 1, n.id)
    collect(tree.effects, EFFECT, 1, CORE_ID)
    collect(tree.causes, CAUSE, 1, CORE_ID)

    def row_width(arr):
        return sum(subtree(n) for n in arr) + GAP_X * (len(arr) - 1) if arr else 0.0

    def subtree(n):
        w = max(NODE_W, row_width(n.children))
        widths[n.id] = w
        return w
    e_total, c_total = row_width(tree.effects), row_width(tree.causes)
    inner = max(e_total, c_total, CORE_W)
    x0 = PAD + GUTTER

    def place(arr, left):
        for n in arr:
            w = widths[n.id]
            raw[n.id]["x"] = left + w / 2
            if n.children:
                cw = sum(widths[c.id] for c in n.children) + GAP_X * (len(n.children) - 1)
                place(n.children, left + (w - cw) / 2)
            left += w + GAP_X
    place(tree.effects, x0 + (inner - e_total) / 2)
    place(tree.causes, x0 + (inner - c_total) / 2)
    raw[CORE_ID]["x"] = x0 + inner / 2

    top = {EFFECT: {}, CAUSE: {}}
    y = PAD
    max_e, max_c = max(level[EFFECT], default=0), max(level[CAUSE], default=0)
    for d in range(max_e, 0, -1):
        top[EFFECT][d] = y
        y += level[EFFECT][d] + GAP_Y
    core_top, core_h = y, raw[CORE_ID]["h"]
    y += core_h
    for d in range(1, max_c + 1):
        y += GAP_Y
        top[CAUSE][d] = y
        y += level[CAUSE][d]

    out = Layout(width=inner + x0 + PAD, height=y + PAD, levels=dict(tree.levels))
    frames = {}
    for node_id in order:
        r = raw[node_id]
        w = CORE_W if r["side"] == CORE else NODE_W
        if r["side"] == CORE:
            t = core_top
        elif r["side"] == EFFECT:
            t = top[EFFECT][r["depth"]] + level[EFFECT][r["depth"]] - r["h"]  # sit on the edge nearest the core
        else:
            t = top[CAUSE][r["depth"]]
        f = Rect(r["x"] - w / 2, t, w, r["h"])
        frames[node_id] = f
        out.items.append(Item(r["node"], r["side"], r["depth"], r["parent"], r["root"], f))
    for it in out.items:
        if it.parent_id is None:
            continue
        p, f = frames[it.parent_id], it.frame
        if it.side == CAUSE:
            mid = p.bottom + GAP_Y / 2
            out.edges.append([(f.cx, f.y), (f.cx, mid), (p.cx, mid), (p.cx, p.bottom)])
        else:
            mid = p.y - GAP_Y / 2
            out.edges.append([(p.cx, p.y), (p.cx, mid), (f.cx, mid), (f.cx, f.bottom)])
    bx, bw = 8.0, GUTTER + 20
    if max_e:
        out.bands.append((EFFECT, Rect(bx, PAD - 24, bw, core_top - GAP_Y / 2 - (PAD - 24))))
    out.bands.append((CORE, Rect(bx, core_top - 10, bw, core_h + 20)))
    if max_c:
        t = core_top + core_h + GAP_Y / 2
        out.bands.append((CAUSE, Rect(bx, t, bw, y + 24 - t)))
    return out
