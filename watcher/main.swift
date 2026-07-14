import AppKit
import Foundation

// Restrict default creation perms so atomic-write temp files land 0600, not
// 0644 — the explicit chmod below still runs as belt-and-suspenders.
umask(0o077)

let fm = FileManager.default
let dataDir = ProcessInfo.processInfo.environment["CLIPHIST_DATA_DIR"]
    .map { URL(fileURLWithPath: $0) }
    ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/clip-hist")
let historyURL = dataDir.appendingPathComponent("history.jsonl")
let configURL = dataDir.appendingPathComponent("config.json")
let pauseURL = dataDir.appendingPathComponent("paused")

let maxItems = 500
let maxItemBytes = 100 * 1024
let pollInterval: TimeInterval = 0.3
let defaultRetention: TimeInterval = 8 * 3600

let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

func parseObject(_ line: String) -> [String: Any]? {
    guard let d = line.data(using: .utf8),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
    return o
}

func loadConfig() -> [String: Any] {
    guard let data = try? Data(contentsOf: configURL),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj
}

// nil means "off" (keep forever)
func retentionSeconds() -> TimeInterval? {
    guard let data = try? Data(contentsOf: configURL),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let r = obj["retention"] as? String else { return defaultRetention }
    if r == "off" { return nil }
    guard r.count >= 2, let n = Double(r.dropLast()), n.isFinite else { return defaultRetention }
    let seconds: TimeInterval
    switch r.last! {
    case "m": seconds = n * 60
    case "h": seconds = n * 3600
    case "d": seconds = n * 86400
    default: return defaultRetention
    }
    // A zero or negative retention would put the cutoff at/after "now",
    // pruning all history on the next copy. Treat that as invalid input
    // rather than a wipe-everything footgun.
    guard seconds.isFinite, seconds > 0 else { return defaultRetention }
    return seconds
}

// nil = file exists but could not be read: fail closed, never clobber
func loadLines() -> [String]? {
    if !fm.fileExists(atPath: historyURL.path) { return [] }
    guard let s = try? String(contentsOf: historyURL, encoding: .utf8) else { return nil }
    return s.split(separator: "\n").map(String.init)
}

func append(text: String, app: String) {
    guard var lines = loadLines() else {
        FileHandle.standardError.write(Data("clip-hist-watcher: history unreadable, skipping write to avoid data loss\n".utf8))
        return
    }
    if let last = lines.last, parseObject(last)?["text"] as? String == text { return }
    // global dedupe: re-copying existing text moves it to the top instead of duplicating
    lines = lines.filter { parseObject($0)?["text"] as? String != text }

    let record: [String: Any] = ["ts": Date().timeIntervalSince1970, "app": app, "text": text]
    guard let d = try? JSONSerialization.data(withJSONObject: record),
          let json = String(data: d, encoding: .utf8) else { return }
    lines.append(json)

    if let ret = retentionSeconds() {
        let cutoff = Date().timeIntervalSince1970 - ret
        lines = lines.filter { line in
            guard let ts = parseObject(line)?["ts"] as? Double else { return false }
            return ts >= cutoff
        }
    }
    if lines.count > maxItems { lines = Array(lines.suffix(maxItems)) }

    try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true,
                             attributes: [.posixPermissions: 0o700])
    do {
        try (lines.joined(separator: "\n") + "\n")
            .write(to: historyURL, atomically: true, encoding: .utf8)
    } catch {
        FileHandle.standardError.write(Data("clip-hist-watcher: history write failed\n".utf8))
        return
    }
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
}

func shannonEntropy(_ s: String) -> Double {
    var freq: [Character: Double] = [:]
    for c in s { freq[c, default: 0] += 1 }
    let len = Double(s.count)
    guard len > 0 else { return 0 }
    return freq.values.reduce(0) { $0 - ($1 / len) * log2($1 / len) }
}

let secretPrefixes = ["ghp_", "github_pat_", "gho_", "sk-", "AKIA", "xoxb-", "xoxp-", "AIza"]

// Prefix + JWT-shape checks only — no entropy branch, so this is safe to run
// against individual whitespace-separated tokens without flagging ordinary
// prose that merely happens to contain a long word.
func tokenLooksLikeSecret(_ s: String) -> Bool {
    if s.count >= 20, secretPrefixes.contains(where: { s.hasPrefix($0) }) { return true }
    if s.hasPrefix("eyJ"), s.contains("."), s.count > 60 { return true }
    return false
}

// Delimiters/wrappers commonly seen around an embedded token, e.g.
// `OPENAI_API_KEY=sk-...`, `token:"ghp_..."`, `Bearer=ghp_...`, or a
// quoted/bracketed JSON value.
let secretDelims = CharacterSet(charactersIn: "=:\"'`,;()[]{}<>")

func looksLikeSecret(_ text: String) -> Bool {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.contains("PRIVATE KEY-----") { return true }
    guard !s.contains(where: { $0.isWhitespace || $0.isNewline }) else {
        // Whitespace-containing text (e.g. "Authorization: Bearer ghp_xxx",
        // a curl command, or a multi-line .env dump) skips the full-string
        // entropy check to avoid flagging ordinary prose, but if any
        // individual token independently looks like a credential, the
        // whole thing is still treated as a secret. Also split each token on
        // common delimiters/wrappers (=, :, quotes, brackets, ...) so a
        // secret embedded in a `KEY=value`, `"token": "value"`, or
        // `Bearer=value` form is still caught even though the raw
        // whitespace-separated token itself doesn't start with a known
        // prefix.
        return s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .contains { token in
                let tokenStr = String(token)
                if tokenLooksLikeSecret(tokenStr) { return true }
                return tokenStr.components(separatedBy: secretDelims)
                    .contains { !$0.isEmpty && tokenLooksLikeSecret($0) }
            }
    }
    if tokenLooksLikeSecret(s) { return true }
    if s.count >= 32, s.count <= 256, !s.contains("://"), !s.hasPrefix("/") {
        let classes = [s.contains(where: { $0.isUppercase }),
                       s.contains(where: { $0.isLowercase }),
                       s.contains(where: { $0.isNumber })].filter { $0 }.count
        if classes >= 3, shannonEntropy(s) >= 4.0 { return true }
    }
    return false
}

let pb = NSPasteboard.general
var lastChange = pb.changeCount

func tick() {
    guard pb.changeCount != lastChange else { return }
    lastChange = pb.changeCount

    if fm.fileExists(atPath: pauseURL.path) { return }
    let types = pb.types ?? []
    if types.contains(concealedType) || types.contains(transientType) { return }
    guard let text = pb.string(forType: .string) else { return }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
    if text.utf8.count > maxItemBytes { return }

    let front = NSWorkspace.shared.frontmostApplication
    let app = front?.bundleIdentifier ?? front?.localizedName ?? "unknown"
    let cfg = loadConfig()
    if let ignored = cfg["ignored_apps"] as? [String], ignored.contains(app) { return }
    if (cfg["skip_secrets"] as? String) != "off", looksLikeSecret(text) { return }
    append(text: text, app: app)
}

// NSWorkspace.frontmostApplication is updated via workspace notifications
// delivered on a run loop. A bare Thread.sleep polling loop never processes
// them, so the value stays frozen at whatever was frontmost when the process
// launched — poll from a RunLoop timer instead.
let timer = Timer(timeInterval: pollInterval, repeats: true) { _ in tick() }
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
