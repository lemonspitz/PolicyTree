import Foundation

/// Interface language. The Indonesian text in the code is the key; other languages come from
/// strings_<code>.json (shared with the Windows app, in windows/policytree/). Foundation only, so
/// the model tests can use it too.
enum Lang {
    static let choices: [(code: String, label: String)] = [
        ("system", "Ikuti sistem"), ("id", "Bahasa Indonesia"), ("en", "English"),
    ]
    static let defaultsKey = "language"

    /// What the user picked: "id", "en" or "system". Indonesian is the default so an existing
    /// user on an English Mac doesn't see the app switch language after an update.
    static var preference: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? "id"
    }

    static func resolve(_ pref: String) -> String {
        if pref == "id" || pref == "en" { return pref }
        let first = Locale.preferredLanguages.first?.lowercased() ?? "id"
        return first.hasPrefix("id") || first.hasPrefix("ms") ? "id" : "en"
    }

    /// Fixed for the life of the process: changing language takes a relaunch, like macOS itself.
    static var code: String = resolve(ProcessInfo.processInfo.environment["POLICYTREE_LANG"] ?? preference) {
        didSet { table = load(code) }
    }
    static var isEnglish: Bool { code == "en" }

    static var table: [String: String] = load(code)

    static func load(_ code: String) -> [String: String] {
        guard code != "id" else { return [:] }
        let env = ProcessInfo.processInfo.environment["POLICYTREE_STRINGS"]
        let url = env.map { URL(fileURLWithPath: $0) } ?? Bundle.main.url(forResource: "strings_\(code)", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return dict
    }

    /// Stores the choice and the matching AppleLanguages, so AppKit's own text
    /// ("Untitled", save panels, standard menus) follows after the relaunch.
    static func save(_ pref: String) {
        let d = UserDefaults.standard
        d.set(pref, forKey: defaultsKey)
        if pref == "system" { d.removeObject(forKey: "AppleLanguages") } else { d.set([pref], forKey: "AppleLanguages") }
    }
}

/// Translates an Indonesian interface string. `{0}`, `{1}`… are filled from `args` after translation,
/// so word order can differ between languages. A key may end in `|context` when one Indonesian word
/// needs two translations (e.g. "Dampak|jumlah" is the plural caption); Indonesian shows the part before `|`.
func L(_ s: String, _ args: Any...) -> String {
    var out = Lang.table[s] ?? (s.firstIndex(of: "|").map { String(s[..<$0]) } ?? s)
    for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
    return out
}
