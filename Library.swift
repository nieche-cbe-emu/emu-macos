
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import Security

enum TokenStore {
    private static let service = "local.nieche.cbeemu.mirror"
    private static let account = "github"

    static func load() -> String {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }

    static func save(_ token: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !token.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct GameItem: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var title: String { url.deletingPathExtension().lastPathComponent }
    var size: Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int) ?? 0
    }
}

final class GameLibrary: ObservableObject {
    @Published private(set) var games: [GameItem] = []
    @Published var note: String = ""

    let root: URL

    static var appHome: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let h = base.appendingPathComponent("NiecheEmu", isDirectory: true)

        let legacy = base.appendingPathComponent("NicaiEmu", isDirectory: true)
        if !FileManager.default.fileExists(atPath: h.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: h)
        }
        try? FileManager.default.createDirectory(at: h, withIntermediateDirectories: true)
        return h
    }

    init() {
        root = GameLibrary.appHome.appendingPathComponent("games", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        games = items
            .filter { $0.pathExtension.lowercased() == "cbe" }
            .map(GameItem.init)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @discardableResult
    func mount(_ src: URL) -> URL? {
        let dst = root.appendingPathComponent(src.lastPathComponent)

        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            reload()
            note = "已挂载 \(dst.lastPathComponent)"
            return dst
        } catch {
            note = "挂载失败：\(error.localizedDescription)"
            return nil
        }
    }

    func remove(_ g: GameItem) {
        try? FileManager.default.removeItem(at: g.url)
        reload()
        note = "已移除 \(g.title)"
    }

    func has(file: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path)
    }

    func write(_ data: Data, as file: String) throws -> URL {
        let dst = root.appendingPathComponent(file)
        try data.write(to: dst, options: .atomic)
        reload()
        return dst
    }
}

struct CatalogEntry: Identifiable, Hashable {
    let title: String
    let file: String
    let size: Int
    let sha256: String?
    let note: String?
    var id: String { file }

    var sizeText: String {
        size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : "—"
    }
}

@MainActor
final class CatalogClient: ObservableObject {
    @Published var entries: [CatalogEntry] = []
    @Published var sourceName = ""
    @Published var status = ""
    @Published var busy = false
    @Published var downloading: String?
    @Published var progress: Double = 0

    static let defaultMirror = ""

    @AppStorage("mirrorURL") var mirror: String = CatalogClient.defaultMirror

    @Published var token: String = TokenStore.load()

    private var base: URL?

    static func normalize(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.hasPrefix("http://") || t.hasPrefix("https://") { return t }

        let parts = t.split(separator: "@", maxSplits: 1)
        let repo = String(parts[0])
        let branch = parts.count > 1 ? String(parts[1]) : "main"
        guard repo.split(separator: "/").count == 2 else { return t }
        return "https://raw.githubusercontent.com/\(repo)/\(branch)/index.json"
    }

    func load() async {
        let raw = Self.normalize(mirror)
        guard let url = URL(string: raw), !raw.isEmpty else {
            status = "还没设置镜像源"
            entries = []
            return
        }
        busy = true; status = "正在拉取目录…"
        defer { busy = false }
        do {
            let (data, resp) = try await URLSession.shared.data(for: authed(url))
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                status = http.statusCode == 404 && token.isEmpty
                    ? "拉取失败：HTTP 404（私有仓库要先填令牌）"
                    : "拉取失败：HTTP \(http.statusCode)"
                return
            }
            try parse(data, from: url)
            status = entries.isEmpty ? "目录是空的" : "共 \(entries.count) 个游戏"
        } catch {
            status = "拉取失败：\(error.localizedDescription)"
        }
    }

    private func authed(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return r
    }

    func saveToken() { TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private func parse(_ data: Data, from url: URL) throws {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "catalog", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "index.json 不是一个对象"])
        }
        sourceName = obj["name"] as? String ?? url.host ?? "镜像源"
        if let b = obj["base"] as? String, let u = URL(string: b) {
            base = u
        } else {
            base = url.deletingLastPathComponent()
        }
        let list = obj["games"] as? [[String: Any]] ?? []
        entries = list.compactMap { g in
            guard let file = g["file"] as? String else { return nil }
            return CatalogEntry(title: g["title"] as? String
                                    ?? (file as NSString).deletingPathExtension,
                                file: file,
                                size: g["size"] as? Int ?? 0,
                                sha256: g["sha256"] as? String,
                                note: g["note"] as? String)
        }
    }

    func download(_ e: CatalogEntry, into lib: GameLibrary) async {

        guard let b = base else { status = "镜像源还没加载"; return }
        let resolved = URL(string: e.file, relativeTo: b)
            ?? e.file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                     .flatMap { URL(string: $0, relativeTo: b) }
        guard let url = resolved?.absoluteURL else {
            status = "地址拼不出来：\(e.file)"
            return
        }
        downloading = e.file; progress = 0
        defer { downloading = nil }
        do {
            let (data, resp) = try await URLSession.shared.data(for: authed(url))
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                status = "\(e.title) 下载失败：HTTP \(http.statusCode)"
                return
            }
            if let want = e.sha256?.lowercased(), !want.isEmpty {
                let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if got != want {
                    status = "\(e.title) 校验不通过，已丢弃"
                    return
                }
            }
            _ = try lib.write(data, as: e.file)
            status = "已下载 \(e.title)"
        } catch {
            status = "\(e.title) 下载失败：\(error.localizedDescription)"
        }
    }
}

struct LibraryPane: View {
    @ObservedObject var lib: GameLibrary
    @Binding var selected: GameItem?
    var projectDir: URL
    var onLaunch: (GameItem) -> Void
    @State private var showCatalog = false
    @State private var showSaves = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("游戏库").font(.headline)
                Spacer()
                Text("\(lib.games.count)").foregroundStyle(.secondary).font(.caption)
            }
            if lib.games.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("库是空的").foregroundStyle(.secondary)
                    Text("点「挂载…」从本机选 .cbe，或用「镜像源…」联网下载。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else {
                List(lib.games, selection: $selected) { g in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.title)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(g.size),
                                                           countStyle: .file))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onLaunch(g) }
                    .tag(g)
                    .contextMenu {
                        Button("运行") { onLaunch(g) }
                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([g.url])
                        }
                        Divider()
                        Button("从库中移除", role: .destructive) { lib.remove(g) }
                    }
                }
                .listStyle(.inset)
            }
            HStack(spacing: 6) {
                Button("挂载…") { mountPicker() }
                Button("镜像源…") { showCatalog = true }
                Spacer(minLength: 0)
                Menu {
                    Button("存档管理…") { showSaves = true }
                    Divider()
                    Button("导入项目自带的全部游戏") { importProjectGames() }
                    Button("在访达中打开库目录") { NSWorkspace.shared.open(lib.root) }
                    Button("打开数据目录") { NSWorkspace.shared.open(DataHome.root) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).frame(width: 28)
                Button("运行") { if let s = selected { onLaunch(s) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
            if !lib.note.isEmpty {
                Text(lib.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(minWidth: 210, idealWidth: 240, maxWidth: 280)
        .sheet(isPresented: $showCatalog) { CatalogSheet(lib: lib) }
        .sheet(isPresented: $showSaves) { SaveSheet() }
    }

    private func importProjectGames() {
        let src = projectDir.appendingPathComponent("assets/cbe")
        let items = (try? FileManager.default.contentsOfDirectory(at: src,
                                                                  includingPropertiesForKeys: nil)) ?? []
        var n = 0
        for u in items where u.pathExtension.lowercased() == "cbe" {
            if lib.mount(u) != nil { n += 1 }
        }
        lib.note = n > 0 ? "已从项目导入 \(n) 个游戏" : "项目目录里没找到 .cbe"
    }

    private func mountPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "cbe") ?? .data]
        panel.allowsOtherFileTypes = true
        panel.message = "选择要挂载到游戏库的 .cbe 模块"
        if panel.runModal() == .OK {
            for u in panel.urls { lib.mount(u) }
        }
    }
}

struct CatalogSheet: View {
    @ObservedObject var lib: GameLibrary
    @StateObject private var cat = CatalogClient()
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var shown: [CatalogEntry] {
        filter.isEmpty ? cat.entries
                       : cat.entries.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("镜像源").font(.title3.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 6) {
                TextField("index.json 地址，或 用户名/仓库[@分支]", text: $cat.mirror)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await cat.load() } }
                Button("刷新") { Task { await cat.load() } }.disabled(cat.busy)
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("怎么填")
            }

            HStack(spacing: 6) {
                if CatalogClient.normalize(cat.mirror).isEmpty {
                    Text("模拟器不自带游戏源，需要自己填一个。")
                } else {
                    Text("解析为 " + CatalogClient.normalize(cat.mirror)).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if cat.busy { ProgressView().controlSize(.small) }
                if !cat.sourceName.isEmpty { Text(cat.sourceName) }
                Text(cat.status)
            }
            .font(.caption).foregroundStyle(.secondary)

            if showHelp {
                VStack(alignment: .leading, spacing: 3) {
                    Text("填法二选一：")
                    Text("· GitHub 仓库简写 —— `用户名/仓库`，或 `用户名/仓库@分支`")
                    Text("· 完整 URL —— 任何能直接下载到 index.json 的地址")
                    Text("自己建源：把 .cbe 放进仓库，在仓库根目录跑一次")
                    Text("  python3 tools/mkindex.py . -o index.json")
                        .font(.system(size: 10, design: .monospaced))
                    Text("生成目录并提交即可。私有仓库才需要下面的令牌。")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 6) {
                SecureField("GitHub 令牌（私有仓库才需要）", text: $cat.token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { cat.saveToken(); Task { await cat.load() } }
                Button("保存") { cat.saveToken(); Task { await cat.load() } }
            }

            if !cat.entries.isEmpty {
                TextField("过滤", text: $filter).textFieldStyle(.roundedBorder)
            }

            List(shown) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title)
                        Text([e.sizeText, e.note].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if lib.has(file: e.file) {
                        Text("已在库中").font(.caption2).foregroundStyle(.secondary)
                    } else if cat.downloading == e.file {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("下载") { Task { await cat.download(e, into: lib) } }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .overlay {
                if cat.entries.isEmpty && !cat.busy {
                    Text(CatalogClient.normalize(cat.mirror).isEmpty
                         ? "填一个源地址，然后点刷新" : "这个源里没有可下载的游戏")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("下载的文件直接进本地库；目录里带 sha256 时会校验。令牌存在钥匙串里。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 520, height: 430)
        .task { if !cat.mirror.isEmpty { await cat.load() } }
    }
}

enum DataHome {
    static var root: URL { GameLibrary.appHome }
    static var saves: URL { root.appendingPathComponent("saves", isDirectory: true) }
    static var fs: URL { root.appendingPathComponent("fs", isDirectory: true) }
}

struct SaveEntry: Identifiable, Hashable {
    let module: String
    let files: [URL]
    var id: String { module }
    var bytes: Int {
        files.reduce(0) { acc, u in
            let a = try? FileManager.default.attributesOfItem(atPath: u.path)
            return acc + ((a?[.size] as? Int) ?? 0)
        }
    }
    var modified: Date? {
        files.compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max()
    }
}

final class SaveStore: ObservableObject {
    @Published private(set) var entries: [SaveEntry] = []
    @Published var note = ""

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: DataHome.saves,
                                                includingPropertiesForKeys: nil)) ?? []
        entries = dirs.compactMap { d in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: d.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let fs = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
            return fs.isEmpty ? nil : SaveEntry(module: d.lastPathComponent, files: fs)
        }
        .sorted { $0.module.localizedStandardCompare($1.module) == .orderedAscending }
    }

    func delete(_ e: SaveEntry) {
        try? FileManager.default.removeItem(at: DataHome.saves.appendingPathComponent(e.module))
        note = "已删除 \(e.module) 的存档"
        reload()
    }
}

struct SaveSheet: View {
    @StateObject private var store = SaveStore()
    @Environment(\.dismiss) private var dismiss

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("存档管理").font(.title3.bold())
            Text(verbatim: DataHome.root.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled)
            Text("存档在 saves/<模块名>/，模块自己写的文件在 fs/<模块名>/，两者分开放。")
                .font(.caption2).foregroundStyle(.secondary)

            if store.entries.isEmpty {
                Text("还没有任何存档").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(store.entries) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.module)
                            Text("\(e.files.count) 个文件 · "
                                 + ByteCountFormatter.string(fromByteCount: Int64(e.bytes),
                                                             countStyle: .file)
                                 + (e.modified.map { " · " + Self.fmt.string(from: $0) } ?? ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("显示") {
                            NSWorkspace.shared.open(DataHome.saves
                                .appendingPathComponent(e.module))
                        }.buttonStyle(.borderless)
                        Button("删除") { store.delete(e) }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                }.frame(minHeight: 220)
            }
            HStack {
                Text(store.note).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("打开数据目录") { NSWorkspace.shared.open(DataHome.root) }
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 500, height: 400)
        .onAppear { store.reload() }
    }
}
