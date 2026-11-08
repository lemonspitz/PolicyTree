"""Model and layout tests, mirroring Tests/main.swift so both apps behave the same."""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from policytree.layout import compute
from policytree.model import CAUSE, CORE, CORE_ID, EFFECT, FileFormatError, Node, Tree, level_key, suggest_objective

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("GAGAL:", msg)


def eq(a, b):
    check(a == b, f"{a!r} != {b!r}")


eq(suggest_objective("Kualitas SDM rendah"), "Kualitas SDM meningkat")
eq(suggest_objective("Biaya meningkat"), "Biaya menurun")
eq(suggest_objective("Prevalensi masih tinggi"), "Prevalensi menurun")
eq(suggest_objective("Belum ada Perbup"), "Tersedia Perbup")
eq(suggest_objective("Rendahnya kepatuhan"), "Meningkatnya kepatuhan")
eq(suggest_objective("Regulasi tumpang   tindih"), "Regulasi selaras")
eq(suggest_objective("Banjir tahunan"), "Teratasinya kondisi: banjir tahunan")
eq(suggest_objective("   "), "")
eq(suggest_objective("Tinggi dan lemah"), "Menurun dan kuat")
eq(suggest_objective("Stok berkurang"), "Teratasinya kondisi: stok berkurang")

t = Tree.sample()
check(Tree.from_json(t.to_json()) == t, "round trip berubah")

web = '''{"title":"Web","core":{"id":"core","text":"Masalah","obj":""},
 "effects":[{"id":"a","text":"D","obj":"","aspek":"","children":[]}],
 "causes":[{"id":"a","text":"P","children":[{"text":"Q","aspek":"sdm"}]}]}'''
w = Tree.from_json(web)
check(w.causes[0].id != "a", "id ganda harus diganti")
check(w.causes[0].children[0].id, "id kosong harus diisi")
eq(w.causes[0].children[0].aspek, "sdm")
for bad in ('{"title":"x"}', "bukan json", "[]", '{"core":{"text":"x"},"effects":[],"causes":[{"id":"a"}]}',
            '{"core":{},"effects":[],"causes":[]}', '{"core":{"text":"x"},"effects":{},"causes":[]}'):
    try:
        Tree.from_json(bad)
        check(False, f"harus ditolak: {bad}")
    except FileFormatError:
        pass

e = Tree.blank()
c1, c2 = e.causes[0].id, e.causes[1].id
sub = e.add_child(c1)
eq(e.location(sub).depth, 2)
eq(e.location(sub).parent_id, c1)
eq([n.id for n in e.root_causes], [sub, c2])
dmp = e.add_child(CORE_ID, EFFECT)
eq(e.location(dmp).side, EFFECT)
sib = e.add_sibling(c1)
eq([n.id for n in e.causes], [c1, sib, c2])
e.move(c1, 1)
eq([n.id for n in e.causes], [sib, c1, c2])
e.move(sib, -1)
eq([n.id for n in e.causes], [sib, c1, c2])
eq(e.remove(CORE_ID), None)
eq(e.remove(c1), c2)
eq(e.node(sub), None)
eq(e.remove(c2), sib)
eq(e.remove(sib), CORE_ID)

a = Tree.blank()
a.causes[0].aspek = "anggaran"
eq(a.node(a.add_child(a.causes[0].id)).aspek, "anggaran")

s = Tree.sample()
eq(s.effect_count, 5)
eq(s.cause_count, 10)
eq(s.cause_depth, 3)
eq(len(s.root_causes), 6)
check("MASALAH INTI: Prevalensi" in s.outline(False), "kerangka masalah")
check("TUJUAN UTAMA: Prevalensi stunting balita turun" in s.outline(True), "kerangka tujuan")
f = s.clone()
check(f.suggest_all_objectives() > 0, "isi tujuan")
eq(f.node(f.causes[1].id).obj, "Sanitasi dan air bersih rumah tangga baik")
eq(f.suggest_all_objectives(), 0)
check(s.suggest_all_objectives() and f == s, "isi tujuan konsisten")


def assert_layout(tree, label):
    lay = compute(tree, lambda n, side, depth: 80 if side == CORE else 50 + (len(n.text) % 5) * 14)
    for i, x in enumerate(lay.items):
        check(x.frame.x >= 0 and x.frame.y >= 0 and x.frame.right <= lay.width and x.frame.bottom <= lay.height, f"{label}: keluar batas")
        for y in lay.items[i + 1:]:
            check(not x.frame.intersects(y.frame), f"{label}: tumpang tindih {x.node.text}/{y.node.text}")
    eq(len(lay.edges), len(lay.items) - 1)
    for edge in lay.edges:
        check(len(edge) == 4 and edge[3][1] < edge[0][1], f"{label}: panah harus ke atas")


assert_layout(Tree.sample(), "contoh")
assert_layout(Tree.blank(), "kosong")
bare = Tree.blank()
bare.effects, bare.causes = [], []
assert_layout(bare, "hanya inti")
uneven = Tree.blank()
cur = uneven.causes[0].id
for _ in range(5):
    cur = uneven.add_child(cur)
    uneven.add_sibling(cur)
for _ in range(4):
    uneven.add_child(CORE_ID, EFFECT)
assert_layout(uneven, "tak seimbang")

# ---- level styles

check('"levels"' not in Tree.sample().to_json(), "tanpa gaya: berkas tidak berubah")
st = Tree.sample()
st.update_level(CAUSE, 2, lambda d: d.update(name="Akar langsung", color="#1a7f5a", shape="hexagon"))
st.update_level(CORE, 0, lambda d: d.update(goalName="Sasaran", shape="ellipse"))
check(st.levels["cause.2"]["color"] == "#1A7F5A", "warna dinormalkan")
back = Tree.from_json(st.to_json())
check(back.levels == st.levels, "gaya level bolak-balik lewat berkas")
check(back.level(EFFECT, 1) == {}, "level lain tetap bawaan")
st.update_level(CAUSE, 2, lambda d: d.clear())
check("cause.2" not in st.levels, "atur ulang menghapus entri")
st.update_level(EFFECT, 1, lambda d: d.update(name="   "))
check("effect.1" not in st.levels, "nama kosong = bawaan")
st.update_level(EFFECT, 1, lambda d: d.update(name="Akibat "))
check(st.levels["effect.1"]["name"] == "Akibat ", "spasi yang sedang diketik tidak dibuang")
messy = Tree.from_json('{"title":"x","core":{"text":"a"},"effects":[],"causes":[{"text":"b"}],'
                       '"levels":{"cause.1":{"color":"merah","shape":"bintang","name":"Ok"},"effect.1":{"color":"#zzz"}}}')
check(messy.levels == {"cause.1": {"name": "Ok"}}, f"nilai rusak diabaikan: {messy.levels}")
check(Tree.from_json('{"title":"x","core":{"text":"a"},"effects":[],"causes":[],"levels":[1,2]}').levels == {},
      "bagian gaya rusak tidak menghalangi berkas dibuka")
lv = [level_key(s, d) for s, d in Tree.sample().present_levels()]
check(lv == ["effect.2", "effect.1", "core", "cause.1", "cause.2", "cause.3"], f"daftar level: {lv}")
check(Tree.sample().node_count(CAUSE, 2) == 6, "jumlah simpul per level")

# ---- English interface

from policytree import i18n
from policytree.i18n import L
check(i18n.init("en") == "en", "bahasa Inggris aktif")
check(L("Berlaku untuk {0} simpul di {1}.", 3, "x") == "Applies to 3 node(s) at x.", "penanda diisi setelah terjemahan")
check(L("Dampak|jumlah") == "Effects" and L("Dampak") == "Effect", "kunci berkonteks")
check(suggest_objective("Stunting prevalence remains high") == "Stunting prevalence falls", "usulan Inggris")
check(suggest_objective("Coordination is weak") == "Coordination is strong", "usulan Inggris 2")
check(suggest_objective("Children skip school") == "Resolved: children skip school", "usulan Inggris tanpa aturan")
check(Tree.blank().causes[0].text == "Cause 1" and Tree.sample().title.startswith("Accelerating"), "pohon baru dan contoh Inggris")
en, idn = Tree.sample_en(), Tree.sample_id()
check(en.cause_count == idn.cause_count and en.effect_count == idn.effect_count, "contoh Inggris sama bentuknya")
check(Tree.sample().outline(False).startswith("PROBLEM TREE: "), "kerangka teks Inggris")
check(i18n.init("id") == "id" and L("Dampak|jumlah") == "Dampak" and suggest_objective("Koordinasi lemah") == "Koordinasi kuat",
      "kembali ke bahasa Indonesia")
check(i18n.resolve("system") in ("id", "en"), "bahasa sistem")

print("Tes model lulus." if not failures else f"{len(failures)} tes model gagal.")
sys.exit(1 if failures else 0)
