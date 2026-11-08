import Foundation

enum Aspek: String, CaseIterable {
    case regulasi, kelembagaan, anggaran, sdm, sosbud, infra
    var label: String {
        switch self {
        case .regulasi: return L("Regulasi")
        case .kelembagaan: return L("Kelembagaan")
        case .anggaran: return L("Anggaran")
        case .sdm: return L("SDM")
        case .sosbud: return L("Sosial-budaya")
        case .infra: return L("Infrastruktur")
        }
    }
}

enum NodeShape: String, CaseIterable {
    case rounded, rect, pill, hexagon, ellipse
    var label: String {
        switch self {
        case .rounded: return L("Persegi membulat")
        case .rect: return L("Persegi")
        case .pill: return L("Kapsul")
        case .hexagon: return L("Segi enam")
        case .ellipse: return L("Elips")
        }
    }
}

/// What the user changed about one level; every field left nil keeps the built-in look.
/// Colours are "#RRGGBB" so the file stays readable and the Windows app can share it.
struct LevelStyle: Codable, Equatable {
    var name: String?
    var goalName: String?
    var color: String?
    var shape: String?

    var isEmpty: Bool { name == nil && goalName == nil && color == nil && shape == nil }
    var shapeValue: NodeShape { shape.flatMap(NodeShape.init(rawValue:)) ?? .rounded }

    /// Blank strings and unknown values count as "not set", so a hand-edited file can't break drawing.
    func cleaned() -> LevelStyle {
        // Kept untrimmed: the name box rewrites itself from the model on every keystroke,
        // so trimming here would eat the space the user just typed.
        func text(_ s: String?) -> String? {
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return s
        }
        var c = LevelStyle()
        c.name = text(name)
        c.goalName = text(goalName)
        c.color = color.flatMap(LevelStyle.normalizedHex)
        c.shape = shape.flatMap(NodeShape.init(rawValue:))?.rawValue
        return c
    }

    static func normalizedHex(_ s: String) -> String? {
        var h = s.trimmingCharacters(in: .whitespaces).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, h.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + h
    }
}

struct TreeNode: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var obj: String
    var aspek: String
    var children: [TreeNode]

    static func newID() -> String { "n" + UUID().uuidString.prefix(8).lowercased() }

    init(_ text: String, obj: String = "", aspek: Aspek? = nil, children: [TreeNode] = [], id: String = TreeNode.newID()) {
        self.id = id
        self.text = text
        self.obj = obj
        self.aspek = aspek?.rawValue ?? ""
        self.children = children
    }

    enum CodingKeys: String, CodingKey { case id, text, obj, aspek, children }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        text = try c.decode(String.self, forKey: .text)
        obj = try c.decodeIfPresent(String.self, forKey: .obj) ?? ""
        aspek = try c.decodeIfPresent(String.self, forKey: .aspek) ?? ""
        children = try c.decodeIfPresent([TreeNode].self, forKey: .children) ?? []
    }

    var aspekValue: Aspek? { Aspek(rawValue: aspek) }
}

enum Side { case core, effect, cause }

struct NodeLocation: Equatable {
    var side: Side
    var depth: Int
    var parentID: String?   // nil only for the core; first-level nodes have "core"
    var index: Int
    var siblingCount: Int
}

struct PolicyTree: Codable, Equatable {
    var title: String
    var core: TreeNode
    var effects: [TreeNode]
    var causes: [TreeNode]
    /// Keyed by `levelKey(side:depth:)`. Missing means the built-in style.
    var levels: [String: LevelStyle] = [:]

    static let coreID = "core"

    static func levelKey(side: Side, depth: Int) -> String {
        switch side {
        case .core: return "core"
        case .effect: return "effect.\(depth)"
        case .cause: return "cause.\(depth)"
        }
    }

    func level(side: Side, depth: Int) -> LevelStyle { levels[Self.levelKey(side: side, depth: depth)] ?? LevelStyle() }

    mutating func updateLevel(side: Side, depth: Int, _ body: (inout LevelStyle) -> Void) {
        let key = Self.levelKey(side: side, depth: depth)
        var st = levels[key] ?? LevelStyle()
        body(&st)
        st = st.cleaned()
        levels[key] = st.isEmpty ? nil : st
    }

    /// Every level the tree currently has, from the top effect row down to the deepest cause.
    var presentLevels: [(side: Side, depth: Int)] {
        let maxE = Self.depth(effects), maxC = Self.depth(causes)
        return stride(from: maxE, through: 1, by: -1).map { (Side.effect, $0) } + [(.core, 0)] + (0..<maxC).map { (Side.cause, $0 + 1) }
    }

    init(title: String, core: TreeNode, effects: [TreeNode], causes: [TreeNode]) {
        self.title = title
        self.core = core
        self.effects = effects
        self.causes = causes
        normalize()
    }

    enum CodingKeys: String, CodingKey { case title, core, effects, causes, levels }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? L("Analisis kebijakan")
        core = try c.decode(TreeNode.self, forKey: .core)
        effects = try c.decode([TreeNode].self, forKey: .effects)
        causes = try c.decode([TreeNode].self, forKey: .causes)
        // A broken style section should never stop a tree from opening.
        let raw = (try? c.decodeIfPresent([String: LevelStyle].self, forKey: .levels)) ?? [:]
        levels = raw.compactMapValues { let s = $0.cleaned(); return s.isEmpty ? nil : s }
        normalize()
    }

    /// Files without custom styles stay exactly as before, so older apps and the web version read them unchanged.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(core, forKey: .core)
        try c.encode(effects, forKey: .effects)
        try c.encode(causes, forKey: .causes)
        if !levels.isEmpty { try c.encode(levels, forKey: .levels) }
    }

    /// Ids are the only link between the view and the data, so a hand-edited file
    /// with missing or repeated ids gets fresh ones instead of confusing selection.
    private mutating func normalize() {
        core.id = Self.coreID
        core.children = []
        var seen: Set<String> = [Self.coreID]
        func fix(_ arr: inout [TreeNode]) {
            for i in arr.indices {
                if arr[i].id.isEmpty || seen.contains(arr[i].id) { arr[i].id = TreeNode.newID() }
                seen.insert(arr[i].id)
                fix(&arr[i].children)
            }
        }
        fix(&effects)
        fix(&causes)
    }

    static var blank: PolicyTree {
        PolicyTree(title: L("Analisis kebijakan baru"),
                   core: TreeNode(L("Tuliskan masalah inti kebijakan di sini"), id: coreID),
                   effects: [TreeNode(L("Dampak {0}", 1))],
                   causes: [TreeNode(L("Penyebab {0}", 1)), TreeNode(L("Penyebab {0}", 2))])
    }

    /// The worked example, in the interface language. Kept as real prose rather than
    /// dictionary entries so each version reads naturally.
    static var sample: PolicyTree { Lang.isEnglish ? sampleEN : sampleID }

    static var sampleEN: PolicyTree {
        PolicyTree(
            title: "Accelerating stunting reduction in the district (example)",
            core: TreeNode("Stunting prevalence among under-fives remains high (21.5%, illustrative figure)",
                           obj: "Stunting prevalence among under-fives falls to 14%", id: coreID),
            effects: [
                TreeNode("Quality of the next generation's human resources is low", obj: "Quality of the next generation's human resources improves", children: [
                    TreeNode("Regional productivity and competitiveness weaken", obj: "Regional productivity and competitiveness strengthen"),
                ]),
                TreeNode("Regional health costs increase", obj: "Regional health costs decrease", children: [
                    TreeNode("Fiscal space for development programmes is shrinking"),
                ]),
                TreeNode("Risk of non-communicable disease in adulthood increases"),
            ],
            causes: [
                TreeNode("Nutrition intake of pregnant women and under-fives is inadequate", obj: "Nutrition intake of pregnant women and under-fives is adequate", aspek: .sosbud, children: [
                    TreeNode("Family knowledge of nutrition is low", obj: "Family knowledge of nutrition improves", aspek: .sosbud, children: [
                        TreeNode("Counselling at community health posts is irregular", obj: "Counselling at community health posts runs every month", aspek: .sdm),
                    ]),
                    TreeNode("Access to nutritious food is limited for poor families", aspek: .anggaran),
                ]),
                TreeNode("Household sanitation and clean water are poor", aspek: .infra, children: [
                    TreeNode("Coverage of safe latrines is low", aspek: .infra),
                    TreeNode("Sanitation grants are not yet prioritised", aspek: .anggaran),
                ]),
                TreeNode("Coordination across agencies is weak", obj: "Coordination across agencies is strong", aspek: .kelembagaan, children: [
                    TreeNode("No regent regulation on accelerating stunting reduction yet", obj: "Regent regulation on accelerating stunting reduction is issued", aspek: .regulasi),
                    TreeNode("Target data is not integrated across agencies", aspek: .kelembagaan),
                ]),
            ])
    }

    static var sampleID: PolicyTree {
        PolicyTree(
            title: "Percepatan penurunan stunting di Kabupaten (contoh)",
            core: TreeNode("Prevalensi stunting balita masih tinggi (21,5%, angka ilustrasi)",
                           obj: "Prevalensi stunting balita turun menjadi 14%", id: coreID),
            effects: [
                TreeNode("Kualitas SDM generasi mendatang rendah", obj: "Kualitas SDM generasi mendatang meningkat", children: [
                    TreeNode("Produktivitas dan daya saing daerah melemah", obj: "Produktivitas dan daya saing daerah menguat"),
                ]),
                TreeNode("Beban biaya kesehatan daerah meningkat", obj: "Beban biaya kesehatan daerah menurun", children: [
                    TreeNode("Ruang fiskal untuk program pembangunan menyempit"),
                ]),
                TreeNode("Risiko penyakit tidak menular saat dewasa meningkat"),
            ],
            causes: [
                TreeNode("Asupan gizi ibu hamil dan balita tidak memadai", obj: "Asupan gizi ibu hamil dan balita memadai", aspek: .sosbud, children: [
                    TreeNode("Pengetahuan gizi keluarga rendah", obj: "Pengetahuan gizi keluarga meningkat", aspek: .sosbud, children: [
                        TreeNode("Penyuluhan di posyandu tidak rutin", obj: "Penyuluhan di posyandu berjalan rutin tiap bulan", aspek: .sdm),
                    ]),
                    TreeNode("Akses pangan bergizi terbatas bagi keluarga miskin", aspek: .anggaran),
                ]),
                TreeNode("Sanitasi dan air bersih rumah tangga buruk", aspek: .infra, children: [
                    TreeNode("Cakupan jamban sehat rendah", aspek: .infra),
                    TreeNode("Alokasi DAK sanitasi belum diprioritaskan", aspek: .anggaran),
                ]),
                TreeNode("Koordinasi lintas OPD lemah", obj: "Koordinasi lintas OPD kuat", aspek: .kelembagaan, children: [
                    TreeNode("Belum ada Perbup tentang percepatan penurunan stunting", obj: "Perbup percepatan penurunan stunting ditetapkan", aspek: .regulasi),
                    TreeNode("Data sasaran tidak terintegrasi antar-OPD", aspek: .kelembagaan),
                ]),
            ])
    }

    // MARK: File format

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }

    static func decoded(from data: Data) throws -> PolicyTree {
        try JSONDecoder().decode(PolicyTree.self, from: data)
    }

    // MARK: Lookup

    func location(of id: String) -> NodeLocation? {
        if id == Self.coreID { return NodeLocation(side: .core, depth: 0, parentID: nil, index: 0, siblingCount: 1) }
        func search(_ arr: [TreeNode], _ side: Side, _ depth: Int, _ parent: String) -> NodeLocation? {
            for (i, n) in arr.enumerated() {
                if n.id == id { return NodeLocation(side: side, depth: depth, parentID: parent, index: i, siblingCount: arr.count) }
                if let r = search(n.children, side, depth + 1, n.id) { return r }
            }
            return nil
        }
        return search(effects, .effect, 1, Self.coreID) ?? search(causes, .cause, 1, Self.coreID)
    }

    func node(_ id: String) -> TreeNode? {
        if id == Self.coreID { return core }
        func search(_ arr: [TreeNode]) -> TreeNode? {
            for n in arr {
                if n.id == id { return n }
                if let r = search(n.children) { return r }
            }
            return nil
        }
        return search(effects) ?? search(causes)
    }

    /// Runs `body` on the array that directly holds `id`, so inserts and removals share one walk.
    @discardableResult
    private static func withArray(_ arr: inout [TreeNode], holding id: String, _ body: (inout [TreeNode], Int) -> Void) -> Bool {
        if let i = arr.firstIndex(where: { $0.id == id }) { body(&arr, i); return true }
        for i in arr.indices where withArray(&arr[i].children, holding: id, body) { return true }
        return false
    }

    private mutating func withArray(holding id: String, _ body: (inout [TreeNode], Int) -> Void) -> Bool {
        Self.withArray(&effects, holding: id, body) || Self.withArray(&causes, holding: id, body)
    }

    // MARK: Editing

    mutating func update(_ id: String, _ body: (inout TreeNode) -> Void) {
        if id == Self.coreID { body(&core); return }
        _ = withArray(holding: id) { arr, i in body(&arr[i]) }
    }

    /// Adds under `id`. The core has two directions, so `coreSide` picks which one.
    @discardableResult
    mutating func addChild(of id: String, coreSide: Side = .cause) -> String? {
        guard let loc = location(of: id) else { return nil }
        if loc.side == .core {
            if coreSide == .effect {
                let n = TreeNode(L("Dampak baru")); effects.append(n); return n.id
            }
            let n = TreeNode(L("Penyebab baru")); causes.append(n); return n.id
        }
        let parentAspek = node(id)?.aspekValue
        let n = loc.side == .effect ? TreeNode(L("Dampak lanjutan baru")) : TreeNode(L("Sub-penyebab baru"), aspek: parentAspek)
        update(id) { $0.children.append(n) }
        return n.id
    }

    @discardableResult
    mutating func addSibling(after id: String) -> String? {
        guard let loc = location(of: id), loc.side != .core else { return nil }
        let n = TreeNode(loc.side == .effect ? L("Dampak baru") : L("Penyebab baru"))
        _ = withArray(holding: id) { arr, i in arr.insert(n, at: i + 1) }
        return n.id
    }

    /// Removes the node and its subtree; returns what should be selected next.
    mutating func remove(_ id: String) -> String? {
        guard let loc = location(of: id), loc.side != .core else { return nil }
        var next: String? = nil
        _ = withArray(holding: id) { arr, i in
            arr.remove(at: i)
            if i < arr.count { next = arr[i].id } else if i > 0 { next = arr[i - 1].id }
        }
        return next ?? loc.parentID ?? Self.coreID
    }

    mutating func move(_ id: String, by delta: Int) {
        _ = withArray(holding: id) { arr, i in
            let j = i + delta
            guard arr.indices.contains(j) else { return }
            arr.swapAt(i, j)
        }
    }

    // MARK: Analysis

    private static func count(_ arr: [TreeNode]) -> Int { arr.reduce(0) { $0 + 1 + count($1.children) } }
    private static func depth(_ arr: [TreeNode]) -> Int { arr.isEmpty ? 0 : 1 + (arr.map { depth($0.children) }.max() ?? 0) }
    private static func walk(_ arr: [TreeNode], _ fn: (TreeNode) -> Void) { for n in arr { fn(n); walk(n.children, fn) } }

    func nodeCount(side: Side, depth: Int) -> Int {
        func rec(_ arr: [TreeNode], _ d: Int) -> Int { d == depth ? arr.count : arr.reduce(0) { $0 + rec($1.children, d + 1) } }
        switch side {
        case .core: return 1
        case .effect: return rec(effects, 1)
        case .cause: return rec(causes, 1)
        }
    }

    var effectCount: Int { Self.count(effects) }
    var causeCount: Int { Self.count(causes) }
    var causeDepth: Int { Self.depth(causes) }

    /// Causes with nothing beneath them: the root causes a policy can act on.
    var rootCauses: [TreeNode] {
        var out: [TreeNode] = []
        func rec(_ arr: [TreeNode]) { for n in arr { n.children.isEmpty ? out.append(n) : rec(n.children) } }
        rec(causes)
        return out
    }

    /// Cause count per aspect; `nil` key means not yet assigned.
    var aspekCounts: [Aspek?: Int] {
        var out: [Aspek?: Int] = [:]
        Self.walk(causes) { out[$0.aspekValue, default: 0] += 1 }
        return out
    }

    /// Fills every empty objective from its problem statement; returns how many changed.
    @discardableResult
    mutating func suggestAllObjectives() -> Int {
        var changed = 0
        func fill(_ n: inout TreeNode) {
            if n.obj.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !n.text.isEmpty {
                n.obj = suggestObjective(n.text); changed += 1
            }
            for i in n.children.indices { fill(&n.children[i]) }
        }
        fill(&core)
        for i in effects.indices { fill(&effects[i]) }
        for i in causes.indices { fill(&causes[i]) }
        return changed
    }

    func outline(goal: Bool) -> String {
        func txt(_ n: TreeNode) -> String {
            guard goal else { return n.text }
            return n.obj.isEmpty ? suggestObjective(n.text) : n.obj
        }
        func rec(_ arr: [TreeNode], _ indent: Int) -> [String] {
            arr.flatMap { n -> [String] in
                let tag = n.aspekValue.map { " [\($0.label)]" } ?? ""
                return [String(repeating: "  ", count: indent) + "- " + txt(n) + tag] + rec(n.children, indent + 1)
            }
        }
        func block(_ head: String, _ lines: [String]) -> [String] { [head] + (lines.isEmpty ? ["-"] : lines) + [""] }
        var out = ["\(goal ? L("POHON TUJUAN") : L("POHON MASALAH")): \(title)", ""]
        out += block(goal ? L("MANFAAT (DAMPAK POSITIF)") : L("DAMPAK"), rec(effects, 0))
        out += ["\(goal ? L("TUJUAN UTAMA") : L("MASALAH INTI")): \(txt(core))", ""]
        out += block(goal ? L("SARANA / CARA") : L("PENYEBAB"), rec(causes, 0))
        out += block(goal ? L("TITIK INTERVENSI") : L("AKAR MASALAH"), rootCauses.map { "- " + txt($0) })
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

// MARK: Objective suggestion

private let flipsID: [String: String] = [
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
]

/// Same idea for English text. Kept in step with model.py on Windows.
private let flipsEN: [String: String] = [
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
]

private func flipRegex(_ table: [String: String]) -> NSRegularExpression {
    let alternatives = table.keys.sorted { $0.count > $1.count }
        .map { $0.replacingOccurrences(of: " ", with: "\\s+") }
        .joined(separator: "|")
    return try! NSRegularExpression(pattern: "\\b(" + alternatives + ")\\b", options: .caseInsensitive)
}
private let regexID = flipRegex(flipsID)
private let regexEN = flipRegex(flipsEN)

/// Turns a negative problem statement into a positive objective. One pass over the
/// text, so a replacement is never flipped back by a later rule.
func suggestObjective(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let flips = Lang.isEnglish ? flipsEN : flipsID
    let regex = Lang.isEnglish ? regexEN : regexID
    let ns = trimmed as NSString
    let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else {
        return L("Teratasinya kondisi: {0}", trimmed.prefix(1).lowercased() + trimmed.dropFirst())
    }
    var out = trimmed
    for m in matches.reversed() {
        let found = ns.substring(with: m.range)
        let key = found.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard var rep = flips[key], let r = Range(m.range, in: out) else { continue }
        if found.first?.isUppercase == true { rep = rep.prefix(1).uppercased() + rep.dropFirst() }
        out.replaceSubrange(r, with: rep)
    }
    return out
}
