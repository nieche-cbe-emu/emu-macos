
import SwiftUI

struct PhoneKey: Identifiable, Hashable {
    let id: String
    let label: String
    let defaultBits: [Int]

    static let all: [PhoneKey] = [
        .init(id: "lsk",   label: "左软键", defaultBits: [12]),
        .init(id: "rsk",   label: "右软键", defaultBits: [13]),
        .init(id: "call",  label: "呼叫",   defaultBits: [20]),
        .init(id: "end",   label: "挂断",   defaultBits: [13]),
        .init(id: "up",    label: "▲",     defaultBits: [2, 17]),
        .init(id: "down",  label: "▼",     defaultBits: [8, 18]),
        .init(id: "left",  label: "◀",     defaultBits: [4, 15]),
        .init(id: "right", label: "▶",     defaultBits: [6, 16]),
        .init(id: "ok",    label: "OK",    defaultBits: [5, 14]),
        .init(id: "k1",    label: "1",     defaultBits: [19]),
        .init(id: "k2",    label: "2",     defaultBits: [18]),
        .init(id: "k3",    label: "3",     defaultBits: [20]),
        .init(id: "k4",    label: "4",     defaultBits: [15]),
        .init(id: "k5",    label: "5",     defaultBits: [14]),
        .init(id: "k6",    label: "6",     defaultBits: [16]),
        .init(id: "k7",    label: "7",     defaultBits: [21]),
        .init(id: "k8",    label: "8",     defaultBits: [17]),
        .init(id: "k9",    label: "9",     defaultBits: [22]),
        .init(id: "star",  label: "✱",     defaultBits: [23]),
        .init(id: "k0",    label: "0",     defaultBits: [24]),
        .init(id: "pound", label: "#",     defaultBits: [25]),
    ]
    static func find(_ id: String) -> PhoneKey { all.first { $0.id == id } ?? all[0] }
}

let defaultKeyboard: [String: [UInt16]] = [
    "up":   [13, 126],
    "left": [0, 123],
    "down": [1, 125],
    "right": [2, 124],
    "ok":   [38, 49, 36],
    "lsk":  [40], "rsk": [37],
    "call": [32], "end": [53],
    "k1": [18], "k2": [19], "k3": [20], "k4": [21], "k5": [23],
    "k6": [22], "k7": [26], "k8": [28], "k9": [25], "k0": [29],
    "star": [27], "pound": [24],
]

let keyCodeNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
    34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 45: "N", 46: "M",
    18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    24: "=", 27: "-", 30: "]", 33: "[", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
    36: "⏎", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc",
    123: "←", 124: "→", 125: "↓", 126: "↑",
]

func keyCodeName(_ c: UInt16) -> String { keyCodeNames[c] ?? "键码 \(c)" }

final class KeyMap: ObservableObject {
    @Published var bits: [String: [Int]] = [:] { didSet { save() } }

    @Published var kb: [String: [UInt16]] = [:] { didSet { saveKB(); rebuildIndex() } }

    private(set) var codeIndex: [UInt16: String] = [:]

    init() {
        if let d = UserDefaults.standard.dictionary(forKey: "keymap") as? [String: [Int]],
           !d.isEmpty {
            bits = d
        } else {
            bits = Dictionary(uniqueKeysWithValues: PhoneKey.all.map { ($0.id, $0.defaultBits) })
        }
        if let d = UserDefaults.standard.dictionary(forKey: "keyboard") as? [String: [Int]],
           !d.isEmpty {
            kb = d.mapValues { $0.map { UInt16($0) } }
        } else {
            kb = defaultKeyboard
        }
        rebuildIndex()
    }
    private func save() { UserDefaults.standard.set(bits, forKey: "keymap") }
    private func saveKB() {
        UserDefaults.standard.set(kb.mapValues { $0.map { Int($0) } }, forKey: "keyboard")
    }
    private func rebuildIndex() {
        var idx: [UInt16: String] = [:]
        for (id, codes) in kb { for c in codes { idx[c] = id } }
        codeIndex = idx
    }

    func phoneKey(code: UInt16) -> String? { codeIndex[code] }

    func bind(_ code: UInt16, to id: String) {
        var next = kb
        for (k, v) in next where k != id {
            next[k] = v.filter { $0 != code }
        }
        var mine = next[id] ?? []
        if !mine.contains(code) { mine.append(code) }
        next[id] = mine
        kb = next
    }
    func unbind(_ code: UInt16, from id: String) {
        kb[id] = (kb[id] ?? []).filter { $0 != code }
    }
    func kbText(_ id: String) -> String {
        let v = kb[id] ?? []
        return v.isEmpty ? "（未绑定）" : v.map(keyCodeName).joined(separator: " / ")
    }

    func reset() {
        bits = Dictionary(uniqueKeysWithValues: PhoneKey.all.map { ($0.id, $0.defaultBits) })
        kb = defaultKeyboard
    }
    func mask(_ id: String) -> Int {
        (bits[id] ?? PhoneKey.find(id).defaultBits).reduce(0) { $0 | (1 << $1) }
    }
    func text(_ id: String) -> String {
        (bits[id] ?? PhoneKey.find(id).defaultBits).map(String.init).joined(separator: ",")
    }
}

struct KeypadView: View {
    @ObservedObject var map: KeyMap

    @Binding var held: Set<String>
    var send: (Int) -> Void

    var sendSoft: (String) -> Void = { _ in }
    @State private var showEditor = false

    private func key(_ id: String, wide: Bool = false) -> some View {
        let k = PhoneKey.find(id)
        return Text(k.label)
            .font(.system(size: 13, weight: .medium))
            .frame(width: wide ? 74 : 46, height: 30)
            .background(held.contains(id) ? Color.accentColor.opacity(0.75)
                                          : Color.secondary.opacity(0.16))
            .foregroundStyle(held.contains(id) ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())

            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !held.contains(id) {
                        held.insert(id); emit()
                        if id == "lsk" { sendSoft("left") }
                        if id == "rsk" { sendSoft("right") }
                    }
                }
                .onEnded { _ in
                    held.remove(id); emit()
                })
    }

    private func emit() {
        send(held.reduce(0) { $0 | map.mask($1) })
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("键盘").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("键位…") { showEditor = true }
                    .buttonStyle(.borderless).font(.caption)
            }

            HStack(spacing: 4) {
                key("lsk", wide: true)
                Spacer(minLength: 4)
                key("rsk", wide: true)
            }
            HStack(spacing: 4) {
                VStack(spacing: 4) { key("call", wide: true); key("end", wide: true) }
                Spacer(minLength: 2)
                VStack(spacing: 4) {
                    key("up")
                    HStack(spacing: 4) { key("left"); key("ok"); key("right") }
                    key("down")
                }
                Spacer(minLength: 2)
            }
            .padding(.vertical, 2)
            VStack(spacing: 4) {
                HStack(spacing: 4) { key("k1"); key("k2"); key("k3") }
                HStack(spacing: 4) { key("k4"); key("k5"); key("k6") }
                HStack(spacing: 4) { key("k7"); key("k8"); key("k9") }
                HStack(spacing: 4) { key("star"); key("k0"); key("pound") }
            }
            Text("""
                 键盘：WASD 或方向键 = 方向，J/空格/⏎ = OK，K = 左软键，L = 右软键，                 U = 呼叫，Esc = 挂断，数字键直通。
                 触摸一直可用：直接在屏幕上点。软键、对话框按钮多数只吃触摸。
                 """)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showEditor) { KeyMapEditor(map: map) }
    }
}

struct KeyMapEditor: View {
    @ObservedObject var map: KeyMap
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    @State private var recording: String?
    @State private var monitor: Any?

    private func startRecording(_ id: String) {
        stopRecording()
        recording = id

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { ev in
            if ev.keyCode == 53 {
                stopRecording()
            } else {
                map.bind(ev.keyCode, to: id)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("键位映射").font(.title3.bold())
            Text("""
                 「键盘按键」改的是电脑上哪个键对应手机上的哪个键——点「录制」再按一下\
                 想用的键即可，一个手机键可以绑多个。Esc 放弃录制。
                 「键位掩码」是手机键对应模块里的哪几个位，一般不用动：方向键、中心键、\
                 软键是从游戏实际查询的掩码反推的；数字 1/3/7/9/✱/0/# 是顺排的猜测。
                 用 `python3 tools/keyprobe.py <模块>` 可以对单个游戏逐位试。
                 """)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $tab) {
                Text("键盘按键").tag(0)
                Text("键位掩码").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(PhoneKey.all) { k in
                        if tab == 0 {
                            HStack {
                                Text(k.label).frame(width: 56, alignment: .leading)
                                Text(map.kbText(k.id))
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(recording == k.id ? Color.accentColor : .primary)
                                if recording == k.id {
                                    Text("按一下要绑的键…").font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button("取消") { stopRecording() }
                                        .buttonStyle(.borderless).font(.caption)
                                } else {
                                    Button("录制") { startRecording(k.id) }
                                        .buttonStyle(.borderless).font(.caption)
                                    Button("清空") { map.kb[k.id] = [] }
                                        .buttonStyle(.borderless).font(.caption)
                                        .disabled((map.kb[k.id] ?? []).isEmpty)
                                }
                            }
                            .padding(.vertical, 1)
                        } else {
                            HStack {
                                Text(k.label).frame(width: 56, alignment: .leading)
                                TextField("位", text: Binding(
                                    get: { map.text(k.id) },
                                    set: { s in
                                        let v = s.split(whereSeparator: { ",， ".contains($0) })
                                            .compactMap { Int($0) }.filter { (0..<32).contains($0) }
                                        map.bits[k.id] = v
                                    }))
                                    .textFieldStyle(.roundedBorder)
                                Text("mask \(String(format: "0x%08x", map.mask(k.id)))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary).frame(width: 96, alignment: .trailing)
                            }
                        }
                    }
                }
            }.frame(height: 300)
            HStack {
                Button("恢复默认") { map.reset() }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 480)
        .onDisappear { stopRecording() }
    }
}
