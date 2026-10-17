
import Foundation

@main
struct MirrorSafetyTest {
    static var bad = 0
    static func check(_ ok: Bool, _ what: String) {
        if !ok { print("   ✗ \(what)"); bad += 1 }
    }

    static func main() {

        let names: [(String, String?)] = [
            ("众神之战.CBE", "众神之战.CBE"),
            ("games/魔塔.CBE", "魔塔.CBE"),
            ("../../escaped.txt", "escaped.txt"),
            ("..%2F..%2Fescaped.txt", "escaped.txt"),
            ("a\\..\\b.cbe", "b.cbe"),
            ("/etc/passwd", "passwd"),
            ("..", nil), (".", nil), ("", nil), ("/", nil), ("a/..", nil),
        ]
        for (remote, want) in names {
            let got = MirrorSafety.localName(remote)
            check(got == want, "localName(\(remote)) = \(got ?? "nil")，期望 \(want ?? "nil")")
        }

        let index = URL(string: "https://raw.githubusercontent.com/u/r/main/index.json")
        let tokenCases: [(String, Bool)] = [
            ("https://raw.githubusercontent.com/u/r/main/games/x.CBE", true),
            ("https://RAW.githubusercontent.com/u/r/main/x.CBE", true),
            ("https://evil.example.com/x.CBE", false),
            ("http://raw.githubusercontent.com/u/r/main/x.CBE", false),
        ]
        for (u, want) in tokenCases {
            let got = MirrorSafety.mayAttachToken(to: URL(string: u)!, indexURL: index)
            check(got == want, "mayAttachToken(\(u)) = \(got)，期望 \(want)")
        }
        check(!MirrorSafety.mayAttachToken(to: URL(string: "https://a.com/x")!, indexURL: nil),
              "没有索引地址时不发令牌")

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirror-safety-\(UUID().uuidString)")
        let root = tmp.appendingPathComponent("home/lib")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let name = MirrorSafety.localName("../../escaped.txt") {
            let dst = root.appendingPathComponent(name)
            check(MirrorSafety.isInside(dst, root: root), "清洗后的目标应在库里")
            try! Data("x".utf8).write(to: dst)
        }
        check(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path),
              "文件应落在库里")
        check(!FileManager.default.fileExists(atPath: tmp.appendingPathComponent("escaped.txt").path),
              "库外不应出现文件")
        check(!MirrorSafety.isInside(root.appendingPathComponent("../x"), root: root), "isInside 挡住 ..")
        check(!MirrorSafety.isInside(root.appendingPathComponent("sub/x"), root: root), "isInside 不收子目录")

        print(bad == 0 ? "ok" : "\(bad) 条不符")
        exit(bad == 0 ? 0 : 1)
    }
}
