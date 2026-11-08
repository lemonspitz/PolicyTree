"""Tree data, editing and analysis. Same file format as the Mac app (Sources/Model.swift)."""
from __future__ import annotations

import copy
import json
import re
import uuid
from dataclasses import dataclass, field

from . import i18n
from .i18n import L

CORE_ID = "core"
CORE, EFFECT, CAUSE = "core", "effect", "cause"

ASPEK = [
    ("regulasi", "Regulasi"),
    ("kelembagaan", "Kelembagaan"),
    ("anggaran", "Anggaran"),
    ("sdm", "SDM"),
    ("sosbud", "Sosial-budaya"),
    ("infra", "Infrastruktur"),
]
ASPEK_LABEL = dict(ASPEK)


SHAPES = [
    ("rounded", "Persegi membulat"),
    ("rect", "Persegi"),
    ("pill", "Kapsul"),
    ("hexagon", "Segi enam"),
    ("ellipse", "Elips"),
]
SHAPE_LABEL = dict(SHAPES)
_HEX = re.compile(r"^#?([0-9A-Fa-f]{6})$")


def normalized_hex(s):
    m = _HEX.match(s.strip()) if isinstance(s, str) else None
    return "#" + m.group(1).upper() if m else None


def level_key(side, depth):
    return "core" if side == CORE else f"{side}.{depth}"


def clean_style(d) -> dict:
    """Keeps only valid, non-blank fields (same rules as LevelStyle.cleaned on the Mac).
    Names stay untrimmed so a space being typed is not eaten."""
    if not isinstance(d, dict):
        return {}
    out = {}
    for k in ("name", "goalName"):
        v = d.get(k)
        if isinstance(v, str) and v.strip():
            out[k] = v
    c = normalized_hex(d.get("color"))
    if c:
        out["color"] = c
    if d.get("shape") in SHAPE_LABEL:
        out["shape"] = d["shape"]
    return out


def new_id() -> str:
    return "n" + uuid.uuid4().hex[:8]


@dataclass
class Node:
    text: str
    obj: str = ""
    aspek: str = ""
    children: list = field(default_factory=list)
    id: str = field(default_factory=new_id)

    @property
    def aspek_label(self):
        label = ASPEK_LABEL.get(self.aspek)
        return L(label) if label else None


@dataclass
class Location:
    side: str
    depth: int
    parent_id: str | None
    index: int
    sibling_count: int


class FileFormatError(ValueError):
    pass


def _node_from(d, required=True) -> Node:
    if not isinstance(d, dict) or not isinstance(d.get("text"), str):
        raise FileFormatError("simpul tanpa teks")
    kids = d.get("children") or []
    if not isinstance(kids, list):
        raise FileFormatError("children bukan daftar")
    return Node(text=d["text"], obj=d.get("obj") or "", aspek=d.get("aspek") or "",
                id=d.get("id") or "", children=[_node_from(k) for k in kids])


def _node_to(n: Node) -> dict:
    return {"aspek": n.aspek, "children": [_node_to(c) for c in n.children], "id": n.id, "obj": n.obj, "text": n.text}


@dataclass
class Tree:
    title: str
    core: Node
    effects: list
    causes: list
    levels: dict = field(default_factory=dict)  # level_key -> {name, goalName, color, shape}

    def __post_init__(self):
        self._normalize()
        self.levels = {k: v for k, v in ((k, clean_style(v)) for k, v in (self.levels or {}).items()
                                         if isinstance(k, str)) if v}

    def level(self, side, depth) -> dict:
        return self.levels.get(level_key(side, depth), {})

    def update_level(self, side, depth, fn):
        key = level_key(side, depth)
        st = dict(self.levels.get(key, {}))
        fn(st)
        st = clean_style(st)
        if st:
            self.levels[key] = st
        else:
            self.levels.pop(key, None)

    def present_levels(self):
        me, mc = self._depth(self.effects), self._depth(self.causes)
        return [(EFFECT, d) for d in range(me, 0, -1)] + [(CORE, 0)] + [(CAUSE, d) for d in range(1, mc + 1)]

    def node_count(self, side, depth):
        if side == CORE:
            return 1

        def rec(arr, d):
            return len(arr) if d == depth else sum(rec(n.children, d + 1) for n in arr)
        return rec(self.effects if side == EFFECT else self.causes, 1)

    def _normalize(self):
        """Ids are the only link between view and data, so bad ones get replaced."""
        self.core.id = CORE_ID
        self.core.children = []
        seen = {CORE_ID}

        def fix(arr):
            for n in arr:
                if not n.id or n.id in seen:
                    n.id = new_id()
                seen.add(n.id)
                fix(n.children)
        fix(self.effects)
        fix(self.causes)

    # ---- construction

    @staticmethod
    def blank() -> "Tree":
        return Tree(L("Analisis kebijakan baru"), Node(L("Tuliskan masalah inti kebijakan di sini"), id=CORE_ID),
                    [Node(L("Dampak {0}", 1))], [Node(L("Penyebab {0}", 1)), Node(L("Penyebab {0}", 2))])

    @staticmethod
    def sample() -> "Tree":
        """The worked example in the interface language (same text as the Mac)."""
        return Tree.sample_en() if i18n.is_english() else Tree.sample_id()

    @staticmethod
    def sample_en() -> "Tree":
        return Tree(
            "Accelerating stunting reduction in the district (example)",
            Node("Stunting prevalence among under-fives remains high (21.5%, illustrative figure)",
                 obj="Stunting prevalence among under-fives falls to 14%", id=CORE_ID),
            [
                Node("Quality of the next generation's human resources is low", obj="Quality of the next generation's human resources improves", children=[
                    Node("Regional productivity and competitiveness weaken", obj="Regional productivity and competitiveness strengthen"),
                ]),
                Node("Regional health costs increase", obj="Regional health costs decrease", children=[
                    Node("Fiscal space for development programmes is shrinking"),
                ]),
                Node("Risk of non-communicable disease in adulthood increases"),
            ],
            [
                Node("Nutrition intake of pregnant women and under-fives is inadequate", obj="Nutrition intake of pregnant women and under-fives is adequate", aspek="sosbud", children=[
                    Node("Family knowledge of nutrition is low", obj="Family knowledge of nutrition improves", aspek="sosbud", children=[
                        Node("Counselling at community health posts is irregular", obj="Counselling at community health posts runs every month", aspek="sdm"),
                    ]),
                    Node("Access to nutritious food is limited for poor families", aspek="anggaran"),
                ]),
                Node("Household sanitation and clean water are poor", aspek="infra", children=[
                    Node("Coverage of safe latrines is low", aspek="infra"),
                    Node("Sanitation grants are not yet prioritised", aspek="anggaran"),
                ]),
                Node("Coordination across agencies is weak", obj="Coordination across agencies is strong", aspek="kelembagaan", children=[
                    Node("No regent regulation on accelerating stunting reduction yet", obj="Regent regulation on accelerating stunting reduction is issued", aspek="regulasi"),
                    Node("Target data is not integrated across agencies", aspek="kelembagaan"),
                ]),
            ])

    @staticmethod
    def sample_id() -> "Tree":
        return Tree(
            "Percepatan penurunan stunting di Kabupaten (contoh)",
            Node("Prevalensi stunting balita masih tinggi (21,5%, angka ilustrasi)",
                 obj="Prevalensi stunting balita turun menjadi 14%", id=CORE_ID),
            [
                Node("Kualitas SDM generasi mendatang rendah", obj="Kualitas SDM generasi mendatang meningkat", children=[
                    Node("Produktivitas dan daya saing daerah melemah", obj="Produktivitas dan daya saing daerah menguat"),
                ]),
                Node("Beban biaya kesehatan daerah meningkat", obj="Beban biaya kesehatan daerah menurun", children=[
                    Node("Ruang fiskal untuk program pembangunan menyempit"),
                ]),
                Node("Risiko penyakit tidak menular saat dewasa meningkat"),
            ],
            [
                Node("Asupan gizi ibu hamil dan balita tidak memadai", obj="Asupan gizi ibu hamil dan balita memadai", aspek="sosbud", children=[
                    Node("Pengetahuan gizi keluarga rendah", obj="Pengetahuan gizi keluarga meningkat", aspek="sosbud", children=[
                        Node("Penyuluhan di posyandu tidak rutin", obj="Penyuluhan di posyandu berjalan rutin tiap bulan", aspek="sdm"),
                    ]),
                    Node("Akses pangan bergizi terbatas bagi keluarga miskin", aspek="anggaran"),
                ]),
                Node("Sanitasi dan air bersih rumah tangga buruk", aspek="infra", children=[
                    Node("Cakupan jamban sehat rendah", aspek="infra"),
                    Node("Alokasi DAK sanitasi belum diprioritaskan", aspek="anggaran"),
                ]),
                Node("Koordinasi lintas OPD lemah", obj="Koordinasi lintas OPD kuat", aspek="kelembagaan", children=[
                    Node("Belum ada Perbup tentang percepatan penurunan stunting", obj="Perbup percepatan penurunan stunting ditetapkan", aspek="regulasi"),
                    Node("Data sasaran tidak terintegrasi antar-OPD", aspek="kelembagaan"),
                ]),
            ])

    # ---- file format

    def to_json(self) -> str:
        d = {"causes": [_node_to(n) for n in self.causes], "core": _node_to(self.core),
             "effects": [_node_to(n) for n in self.effects], "title": self.title}
        if self.levels:  # files without custom styles stay exactly as before
            d["levels"] = self.levels
        return json.dumps(d, ensure_ascii=False, indent=2, sort_keys=True)

    @staticmethod
    def from_json(text: str) -> "Tree":
        try:
            d = json.loads(text)
        except (ValueError, TypeError) as e:
            raise FileFormatError("bukan JSON") from e
        if not isinstance(d, dict) or not isinstance(d.get("causes"), list) or not isinstance(d.get("effects"), list):
            raise FileFormatError('harus memiliki "core", "causes", dan "effects"')
        title = d.get("title")
        levels = d.get("levels")  # a broken style section never stops a tree from opening
        return Tree(title if isinstance(title, str) else L("Analisis kebijakan"), _node_from(d.get("core")),
                    [_node_from(x) for x in d["effects"]], [_node_from(x) for x in d["causes"]],
                    levels if isinstance(levels, dict) else {})

    def clone(self) -> "Tree":
        return copy.deepcopy(self)

    # ---- lookup

    def location(self, node_id: str):
        if node_id == CORE_ID:
            return Location(CORE, 0, None, 0, 1)

        def search(arr, side, depth, parent):
            for i, n in enumerate(arr):
                if n.id == node_id:
                    return Location(side, depth, parent, i, len(arr))
                r = search(n.children, side, depth + 1, n.id)
                if r:
                    return r
            return None
        return search(self.effects, EFFECT, 1, CORE_ID) or search(self.causes, CAUSE, 1, CORE_ID)

    def node(self, node_id: str):
        if node_id == CORE_ID:
            return self.core

        def search(arr):
            for n in arr:
                if n.id == node_id:
                    return n
                r = search(n.children)
                if r:
                    return r
            return None
        return search(self.effects) or search(self.causes)

    def siblings(self, node_id: str):
        """The list that directly holds the node, or None for the core and unknown ids."""
        def search(arr):
            for n in arr:
                if n.id == node_id:
                    return arr
                r = search(n.children)
                if r is not None:
                    return r
            return None
        r = search(self.effects)
        return r if r is not None else search(self.causes)

    # ---- editing

    def add_child(self, node_id: str, core_side: str = CAUSE):
        loc = self.location(node_id)
        if not loc:
            return None
        if loc.side == CORE:
            n = Node(L("Dampak baru")) if core_side == EFFECT else Node(L("Penyebab baru"))
            (self.effects if core_side == EFFECT else self.causes).append(n)
            return n.id
        parent = self.node(node_id)
        n = Node(L("Dampak lanjutan baru")) if loc.side == EFFECT else Node(L("Sub-penyebab baru"), aspek=parent.aspek)
        parent.children.append(n)
        return n.id

    def add_sibling(self, node_id: str):
        loc = self.location(node_id)
        if not loc or loc.side == CORE:
            return None
        n = Node(L("Dampak baru") if loc.side == EFFECT else L("Penyebab baru"))
        arr = self.siblings(node_id)
        arr.insert(loc.index + 1, n)
        return n.id

    def remove(self, node_id: str):
        """Removes the node and its subtree; returns what should be selected next."""
        loc = self.location(node_id)
        if not loc or loc.side == CORE:
            return None
        arr = self.siblings(node_id)
        del arr[loc.index]
        if loc.index < len(arr):
            return arr[loc.index].id
        if loc.index > 0:
            return arr[loc.index - 1].id
        return loc.parent_id or CORE_ID

    def move(self, node_id: str, delta: int):
        arr = self.siblings(node_id)
        if arr is None:
            return
        i = next(k for k, n in enumerate(arr) if n.id == node_id)
        j = i + delta
        if 0 <= j < len(arr):
            arr[i], arr[j] = arr[j], arr[i]

    # ---- analysis

    @staticmethod
    def _count(arr):
        return sum(1 + Tree._count(n.children) for n in arr)

    @staticmethod
    def _depth(arr):
        return 1 + max(Tree._depth(n.children) for n in arr) if arr else 0

    @property
    def effect_count(self):
        return self._count(self.effects)

    @property
    def cause_count(self):
        return self._count(self.causes)

    @property
    def cause_depth(self):
        return self._depth(self.causes)

    @property
    def root_causes(self):
        out = []

        def rec(arr):
            for n in arr:
                if n.children:
                    rec(n.children)
                else:
                    out.append(n)
        rec(self.causes)
        return out

    def aspek_counts(self):
        """Cause count per aspect key; an unassigned cause counts under ''."""
        out = {}

        def rec(arr):
            for n in arr:
                key = n.aspek if n.aspek in ASPEK_LABEL else ""
                out[key] = out.get(key, 0) + 1
                rec(n.children)
        rec(self.causes)
        return out

    def suggest_all_objectives(self) -> int:
        changed = [0]

        def fill(n):
            if not n.obj.strip() and n.text:
                n.obj = suggest_objective(n.text)
                changed[0] += 1
            for c in n.children:
                fill(c)
        fill(self.core)
        for n in self.effects + self.causes:
            fill(n)
        return changed[0]

    def outline(self, goal: bool) -> str:
        def txt(n):
            if not goal:
                return n.text
            return n.obj if n.obj else suggest_objective(n.text)

        def rec(arr, indent):
            lines = []
            for n in arr:
                tag = f" [{n.aspek_label}]" if n.aspek_label else ""
                lines.append("  " * indent + "- " + txt(n) + tag)
                lines += rec(n.children, indent + 1)
            return lines

        def block(head, lines):
            return [head] + (lines or ["-"]) + [""]
        out = [(L("POHON TUJUAN") if goal else L("POHON MASALAH")) + ": " + self.title, ""]
        out += block(L("MANFAAT (DAMPAK POSITIF)") if goal else L("DAMPAK"), rec(self.effects, 0))
        out += [(L("TUJUAN UTAMA") if goal else L("MASALAH INTI")) + ": " + txt(self.core), ""]
        out += block(L("SARANA / CARA") if goal else L("PENYEBAB"), rec(self.causes, 0))
        out += block(L("TITIK INTERVENSI") if goal else L("AKAR MASALAH"), ["- " + txt(n) for n in self.root_causes])
        return "\n".join(out).strip("\n")


FLIPS = {
    "masih tinggi": "menurun", "tidak memadai": "memadai", "tidak terintegrasi": "terintegrasi",
    "tidak rutin": "berjalan rutin", "tidak optimal": "optimal", "tidak efektif": "efektif",
    "belum optimal": "optimal", "belum efektif": "efektif", "belum ada": "tersedia",
    "belum tersedia": "tersedia", "belum diprioritaskan": "diprioritaskan", "tidak tersedia": "tersedia",
    "kurangnya": "meningkatnya", "rendahnya": "meningkatnya", "tingginya": "menurunnya",
    "lemahnya": "menguatnya", "buruknya": "membaiknya", "rendah": "meningkat", "tinggi": "menurun",
    "meningkat": "menurun", "menurun": "meningkat", "melemah": "menguat", "lemah": "kuat",
    "memburuk": "membaik", "buruk": "baik", "terbatas": "memadai", "menyempit": "meluas",
    "sulit": "mudah", "lambat": "cepat", "mahal": "terjangkau", "rusak": "baik", "minim": "memadai",
    "kurang": "cukup", "tumpang tindih": "selaras",
}
# Same idea for English text; kept in step with flipsEN in Sources/Model.swift.
FLIPS_EN = {
    "remains high": "falls", "remain high": "fall", "still high": "reduced", "is inadequate": "is adequate",
    "inadequate": "adequate", "insufficient": "sufficient", "not integrated": "integrated", "irregular": "regular",
    "not optimal": "optimal", "suboptimal": "optimal", "ineffective": "effective", "not effective": "effective",
    "not yet available": "available", "unavailable": "available", "not available": "available",
    "not yet prioritised": "prioritised", "not yet prioritized": "prioritized", "lack of": "adequate",
    "lacking": "sufficient", "poor": "good", "weak": "strong", "weaken": "strengthen", "weakens": "strengthens",
    "weakening": "strengthening", "low": "high", "high": "low", "increase": "decrease", "increases": "decreases",
    "increasing": "decreasing", "rising": "falling", "decrease": "increase", "decreases": "increases",
    "declining": "improving", "worsening": "improving", "worsens": "improves", "limited": "adequate",
    "shrinking": "expanding", "difficult": "easy", "slow": "fast", "expensive": "affordable",
    "damaged": "in good condition", "overlapping": "aligned", "uncoordinated": "coordinated", "unclear": "clear",
}


def _flip_re(table):
    return re.compile(r"\b(" + "|".join(k.replace(" ", r"\s+") for k in sorted(table, key=len, reverse=True)) + r")\b",
                      re.IGNORECASE)


_FLIP_RE = _flip_re(FLIPS)
_FLIP_RE_EN = _flip_re(FLIPS_EN)


def suggest_objective(text: str) -> str:
    """Turns a negative statement into a positive objective, in one pass so rules never chain."""
    t = text.strip()
    if not t:
        return ""
    table, regex = (FLIPS_EN, _FLIP_RE_EN) if i18n.is_english() else (FLIPS, _FLIP_RE)

    def sub(m):
        found = m.group(0)
        rep = table[" ".join(found.lower().split())]
        return rep[0].upper() + rep[1:] if found[0].isupper() else rep
    out, hits = regex.subn(sub, t)
    return out if hits else L("Teratasinya kondisi: {0}", t[0].lower() + t[1:])
