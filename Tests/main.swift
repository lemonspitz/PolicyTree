import Foundation
import CoreGraphics

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if !cond { failures += 1; print("GAGAL (baris \(line)): \(msg)") }
}
func eq(_ a: String, _ b: String, line: Int = #line) { check(a == b, "'\(a)' != '\(b)'", line: line) }

// Objective suggestion: one pass, so rules never chain back.
eq(suggestObjective("Kualitas SDM rendah"), "Kualitas SDM meningkat")
eq(suggestObjective("Biaya meningkat"), "Biaya menurun")
eq(suggestObjective("Prevalensi masih tinggi"), "Prevalensi menurun")
eq(suggestObjective("Belum ada Perbup"), "Tersedia Perbup")
eq(suggestObjective("Rendahnya kepatuhan"), "Meningkatnya kepatuhan")
eq(suggestObjective("Regulasi tumpang   tindih"), "Regulasi selaras")
eq(suggestObjective("Banjir tahunan"), "Teratasinya kondisi: banjir tahunan")
eq(suggestObjective("   "), "")
eq(suggestObjective("Tinggi dan lemah"), "Menurun dan kuat")

// Word boundaries: "kurang" must not fire inside "berkurang".
eq(suggestObjective("Stok berkurang"), "Teratasinya kondisi: stok berkurang")

// Round trip, plus the JSON the web version exports.
var t = PolicyTree.sample
let back = try! PolicyTree.decoded(from: try! t.encoded())
check(back == t, "round trip berubah")

let web = """
{"title":"Web","core":{"id":"core","text":"Masalah","obj":""},
 "effects":[{"id":"a","text":"D","obj":"","aspek":"","children":[]}],
 "causes":[{"id":"a","text":"P","children":[{"text":"Q","aspek":"sdm"}]}]}
""".data(using: .utf8)!
let w = try! PolicyTree.decoded(from: web)
check(w.causes[0].id != "a", "id ganda harus diganti")
check(!w.causes[0].children[0].id.isEmpty, "id kosong harus diisi")
check(w.causes[0].children[0].aspekValue == .sdm, "aspek terbaca")
check((try? PolicyTree.decoded(from: "{\"title\":\"x\"}".data(using: .utf8)!)) == nil, "berkas tanpa core ditolak")

// Editing
var e = PolicyTree.blank
let c1 = e.causes[0].id, c2 = e.causes[1].id
let sub = e.addChild(of: c1)!
check(e.location(of: sub)?.depth == 2, "kedalaman anak")
check(e.location(of: sub)?.parentID == c1, "induk anak")
check(e.rootCauses.map(\.id) == [sub, c2], "akar masalah = daun penyebab")
let dmp = e.addChild(of: PolicyTree.coreID, coreSide: .effect)!
check(e.location(of: dmp)?.side == .effect, "tambah dampak dari inti")
let sib = e.addSibling(after: c1)!
check(e.causes.map(\.id) == [c1, sib, c2], "saudara disisipkan setelahnya")
e.move(c1, by: 1)
check(e.causes.map(\.id) == [sib, c1, c2], "geser kanan")
e.move(sib, by: -1)
check(e.causes.map(\.id) == [sib, c1, c2], "geser melewati tepi diabaikan")
check(e.remove(PolicyTree.coreID) == nil, "inti tak bisa dihapus")
check(e.remove(c1) == c2, "seleksi pindah ke saudara berikut")
check(e.node(sub) == nil, "subpohon ikut terhapus")
check(e.remove(c2) == sib, "seleksi pindah ke saudara sebelum")
check(e.remove(sib) == PolicyTree.coreID, "seleksi pindah ke inti")

var a = PolicyTree.blank
let inherit = a.addChild(of: a.causes[0].id)!
check(a.node(inherit)?.aspekValue == nil, "tanpa aspek induk")
a.update(a.causes[0].id) { $0.aspek = Aspek.anggaran.rawValue }
let inherit2 = a.addChild(of: a.causes[0].id)!
check(a.node(inherit2)?.aspekValue == .anggaran, "sub-penyebab mewarisi aspek")

// Analysis
let s = PolicyTree.sample
check(s.effectCount == 5, "jumlah dampak \(s.effectCount)")
check(s.causeCount == 10, "jumlah penyebab \(s.causeCount)")
check(s.causeDepth == 3, "kedalaman \(s.causeDepth)")
check(s.rootCauses.count == 6, "akar \(s.rootCauses.count)")
check(s.outline(goal: false).contains("MASALAH INTI: Prevalensi"), "kerangka masalah")
check(s.outline(goal: true).contains("TUJUAN UTAMA: Prevalensi stunting balita turun"), "kerangka tujuan")
var fill = s
let filled = fill.suggestAllObjectives()
check(filled > 0 && fill.node(fill.causes[1].id)?.obj == "Sanitasi dan air bersih rumah tangga baik", "isi semua tujuan: \(filled)")
check(fill.suggestAllObjectives() == 0, "isi kedua tidak mengubah apa pun")

// Layout: varied heights and uneven subtrees must never overlap, and edges must touch nodes.
func assertLayout(_ tree: PolicyTree, _ label: String) {
    let l = TreeLayout.compute(tree: tree) { n, side, _ in side == .core ? 80 : 50 + CGFloat(n.text.count % 5) * 14 }
    for (i, x) in l.items.enumerated() {
        check(x.frame.minX >= 0 && x.frame.minY >= 0 && x.frame.maxX <= l.size.width && x.frame.maxY <= l.size.height, "\(label): keluar batas \(x.node.text)")
        for y in l.items[(i + 1)...] {
            check(!x.frame.intersects(y.frame), "\(label): tumpang tindih \(x.node.text) / \(y.node.text)")
        }
    }
    check(l.edges.count == l.items.count - 1, "\(label): satu garis per simpul non-inti")
    for edge in l.edges {
        check(edge.count == 4 && edge[3].y < edge[0].y, "\(label): panah harus menunjuk ke atas")
    }
}
assertLayout(.sample, "contoh")
assertLayout(.blank, "kosong")
var noSides = PolicyTree.blank; noSides.effects = []; noSides.causes = []
assertLayout(noSides, "hanya inti")
var uneven = PolicyTree.blank
var cursor = uneven.causes[0].id
for _ in 0..<5 { cursor = uneven.addChild(of: cursor)!; _ = uneven.addSibling(after: cursor) }
for _ in 0..<4 { _ = uneven.addChild(of: PolicyTree.coreID, coreSide: .effect) }
assertLayout(uneven, "tak seimbang")

// Edge cases: wide trees stay centred around the core.
let wide = TreeLayout.compute(tree: uneven) { _, _, _ in 60 }
check(wide.item(id: PolicyTree.coreID)!.frame.midX > TreeLayout.padding, "inti di dalam kanvas")

// Level styles: saved in the file, ignored when empty, and robust against hand edits.
do {
    let plain = String(data: try PolicyTree.sample.encoded(), encoding: .utf8)!
    check(!plain.contains("\"levels\""), "tanpa gaya: berkas tidak berubah")
    var styled = PolicyTree.sample
    styled.updateLevel(side: .cause, depth: 2) { $0.name = "Akar langsung"; $0.color = "#1a7f5a"; $0.shape = "hexagon" }
    styled.updateLevel(side: .core, depth: 0) { $0.goalName = "Sasaran"; $0.shape = "ellipse" }
    check(styled.levels["cause.2"]?.color == "#1A7F5A", "warna dinormalkan")
    let back = try PolicyTree.decoded(from: try styled.encoded())
    check(back == styled, "gaya level bolak-balik lewat berkas")
    check(back.level(side: .cause, depth: 2).shapeValue == .hexagon, "bentuk terbaca")
    check(back.level(side: .effect, depth: 1).isEmpty, "level lain tetap bawaan")
    styled.updateLevel(side: .cause, depth: 2) { $0 = LevelStyle() }
    check(styled.levels["cause.2"] == nil, "atur ulang menghapus entri")
    styled.updateLevel(side: .effect, depth: 1) { $0.name = "   " }
    check(styled.levels["effect.1"] == nil, "nama kosong = bawaan")
    styled.updateLevel(side: .effect, depth: 1) { $0.name = "Akibat " }
    check(styled.levels["effect.1"]?.name == "Akibat ", "spasi yang sedang diketik tidak dibuang")

    let messy = ##"{"title":"x","core":{"text":"a"},"effects":[],"causes":[{"text":"b"}],"levels":{"cause.1":{"color":"merah","shape":"bintang","name":"Ok"},"effect.1":{"color":"#zzz"}}}"##
    let m = try PolicyTree.decoded(from: Data(messy.utf8))
    check(m.levels["cause.1"] == LevelStyle(name: "Ok"), "nilai rusak diabaikan")
    check(m.levels["effect.1"] == nil, "entri yang seluruhnya rusak dibuang")
    let broken = #"{"title":"x","core":{"text":"a"},"effects":[],"causes":[],"levels":[1,2]}"#
    check((try? PolicyTree.decoded(from: Data(broken.utf8))) != nil, "bagian gaya rusak tidak menghalangi berkas dibuka")

    let lv = PolicyTree.sample.presentLevels.map { PolicyTree.levelKey(side: $0.side, depth: $0.depth) }
    check(lv == ["effect.2", "effect.1", "core", "cause.1", "cause.2", "cause.3"], "daftar level: \(lv)")
    check(PolicyTree.sample.nodeCount(side: .cause, depth: 2) == 6, "jumlah simpul per level")
} catch { check(false, "gaya level: \(error)") }

// English interface: dictionary, word order, context keys, and the English suggestion rules.
Lang.code = "en"
check(!Lang.table.isEmpty, "kamus Inggris termuat (POLICYTREE_STRINGS)")
check(L("Berlaku untuk {0} simpul di {1}.", 3, "x") == "Applies to 3 node(s) at x.", "penanda diisi setelah terjemahan")
check(L("Dampak|jumlah") == "Effects" && L("Dampak") == "Effect", "kunci berkonteks")
check(suggestObjective("Stunting prevalence remains high") == "Stunting prevalence falls", "usulan Inggris: \(suggestObjective("Stunting prevalence remains high"))")
check(suggestObjective("Coordination is weak") == "Coordination is strong", "usulan Inggris 2")
check(suggestObjective("Children skip school") == "Resolved: children skip school", "usulan Inggris tanpa aturan")
check(PolicyTree.blank.causes[0].text == "Cause 1" && PolicyTree.sample.title.hasPrefix("Accelerating"), "pohon baru dan contoh dalam bahasa Inggris")
check(PolicyTree.sampleEN.causeCount == PolicyTree.sampleID.causeCount && PolicyTree.sampleEN.effectCount == PolicyTree.sampleID.effectCount, "contoh Inggris sama bentuknya")
check(PolicyTree.sample.outline(goal: false).hasPrefix("PROBLEM TREE: "), "kerangka teks Inggris")
Lang.code = "id"
check(L("Dampak|jumlah") == "Dampak" && suggestObjective("Koordinasi lemah") == "Koordinasi kuat", "kembali ke bahasa Indonesia")

if failures == 0 { print("Semua tes lulus.") } else { print("\(failures) tes gagal."); exit(1) }
