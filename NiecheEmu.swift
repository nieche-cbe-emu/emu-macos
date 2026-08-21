
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class Engine: ObservableObject {
    @Published var image: CGImage?
    @Published var frame: Int = 0
    @Published var fps: Double = 0
    @Published var logs: [String] = []
    @Published var title: String = "（未加载模块）"
    @Published var running = false

    private var proc: Process?
    private var stdinPipe: Pipe?

    private var generation = 0

    private let ioQueue = DispatchQueue(label: "nieche.engine.io")
    private var buf = Data()
    private var px32 = [UInt32]()
    private var upBuf = [UInt32]()

    private let pendingLock = NSLock()
    private var pending: (CGImage, Int)?
    private var drainScheduled = false

    let audio = AudioOut()

    var mode: UpscaleMode = .nearest
    private var lastTick = CFAbsoluteTimeGetCurrent()
    private var framesSinceTick = 0
    private var gw = 240, gh = 400
    private(set) var width = 240
    private(set) var height = 400

    var projectDir: URL
    init(projectDir: URL) {
        self.projectDir = projectDir

        if let m = ProcessInfo.processInfo.environment["NIECHE_UPSCALE"],
           let v = UpscaleMode(rawValue: m) { mode = v }
    }

    func start(module: URL, fps: Int = 30) {
        stop()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", projectDir.appendingPathComponent("tools/engine.py").path,
                       module.path, "--fps", String(fps)]
        p.currentDirectoryURL = projectDir

        var env = ProcessInfo.processInfo.environment
        env["NIECHE_HOME"] = GameLibrary.appHome.path
        p.environment = env
        let outPipe = Pipe(), inPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardInput = inPipe
        p.standardError = errPipe
        stdinPipe = inPipe
        generation += 1
        let gen = generation

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            if d.isEmpty { return }
            self?.ioQueue.async {
                guard let s = self, s.generation == gen else { return }
                s.consume(d)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let me = self, me.generation == gen else { return }
                me.append(log: "[引擎] " + s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        do {
            try p.run()
            proc = p
            DispatchQueue.main.async {
                self.title = module.deletingPathExtension().lastPathComponent
                self.running = true
                self.logs.removeAll()
            }
        } catch {
            append(log: "启动引擎失败：\(error.localizedDescription)")
        }
    }

    func stop() {
        guard let p = proc else { return }
        send(["quit": true])
        proc = nil
        generation += 1

        if let out = p.standardOutput as? Pipe {
            out.fileHandleForReading.readabilityHandler = nil
        }
        if let err = p.standardError as? Pipe {
            err.fileHandleForReading.readabilityHandler = nil
        }
        stdinPipe = nil
        audio.stop()
        ioQueue.async { self.buf.removeAll(keepingCapacity: false) }
        pendingLock.lock(); pending = nil; drainScheduled = false; pendingLock.unlock()
        DispatchQueue.main.async {
            self.running = false
            self.image = nil
            self.fps = 0
            self.frame = 0
            self.title = "（未加载模块）"
        }

        DispatchQueue.global(qos: .utility).async {
            let deadline = Date().addingTimeInterval(3)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if p.isRunning { p.terminate() }
        }
    }

    func send(_ obj: [String: Any]) {
        guard let h = stdinPipe?.fileHandleForWriting,
              var d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        d.append(0x0a)
        try? h.write(contentsOf: d)
    }

    private func consume(_ d: Data) {
        buf.append(d)
        while true {
            guard buf.count >= 8 else { return }
            let tag = buf.prefix(4)
            if tag == Data("FRM0".utf8) {
                guard buf.count >= 16 else { return }
                let no = le32(4), w = Int(le16(8)), h = Int(le16(10)), len = Int(le32(12))
                guard buf.count >= 16 + len else { return }
                let pix = buf.subdata(in: 16..<(16 + len))
                buf.removeSubrange(0..<(16 + len))
                render(pix, w, h, Int(no))
            } else if tag == Data("AUD0".utf8) {
                let len = Int(le32(4))
                guard buf.count >= 8 + len else { return }
                let body = buf.subdata(in: 8..<(8 + len))
                buf.removeSubrange(0..<(8 + len))
                if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    DispatchQueue.main.async { self.audio.handle(obj) }
                }
            } else if tag == Data("EXT0".utf8) {

                let len = Int(le32(4))
                guard buf.count >= 8 + len else { return }
                buf.removeSubrange(0..<(8 + len))
                DispatchQueue.main.async { [weak self] in
                    self?.append(log: "模块请求退出")
                    self?.stop()
                }
            } else if tag == Data("LOG0".utf8) {
                let len = Int(le32(4))
                guard buf.count >= 8 + len else { return }
                let s = String(data: buf.subdata(in: 8..<(8 + len)), encoding: .utf8) ?? ""
                buf.removeSubrange(0..<(8 + len))
                DispatchQueue.main.async { self.append(log: s) }
            } else {
                buf.removeFirst()
            }
        }
    }

    private func le16(_ o: Int) -> UInt16 {
        UInt16(buf[buf.startIndex + o]) | UInt16(buf[buf.startIndex + o + 1]) << 8
    }
    private func le32(_ o: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in (0..<4).reversed() { v = v << 8 | UInt32(buf[buf.startIndex + o + i]) }
        return v
    }

    private func render(_ pix: Data, _ w: Int, _ h: Int, _ no: Int) {
        let n = w * h
        if px32.count != n { px32 = [UInt32](repeating: 0xFF000000, count: n) }
        pix.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: UInt16.self)
            px32.withUnsafeMutableBufferPointer { dst in
                for i in 0..<min(n, src.count) {
                    let v = src[i]
                    let r = UInt32((v >> 11) & 0x1F)
                    let g = UInt32((v >> 5) & 0x3F)
                    let b = UInt32(v & 0x1F)

                    dst[i] = 0xFF00_0000
                        | ((b << 3 | b >> 2) << 16)
                        | ((g << 2 | g >> 4) << 8)
                        |  (r << 3 | r >> 2)
                }
            }
        }
        let (scaled, ow, oh) = Upscale.apply(mode, px32, w, h, into: &upBuf)
        let out = scaled ? upBuf : px32
        defer { Self.snapshotIfRequested(out, ow, oh, no) }
        let bytes = out.withUnsafeBufferPointer { (b: UnsafeBufferPointer<UInt32>) -> Data in
            Data(bytes: b.baseAddress!, count: b.count * MemoryLayout<UInt32>.size)
        }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return }
        let img: CGImage? = CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: ow * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                          provider: provider, decode: nil,
                          shouldInterpolate: mode.interpolate,
                          intent: .defaultIntent)
        guard let img else { return }
        publish(img, no, w, h)
    }

    private func publish(_ img: CGImage, _ no: Int, _ w: Int, _ h: Int) {
        pendingLock.lock()
        pending = (img, no)
        gw = w; gh = h
        framesSinceTick += 1
        let needDrain = !drainScheduled
        if needDrain { drainScheduled = true }
        pendingLock.unlock()
        guard needDrain else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLock.lock()
            let item = self.pending
            self.pending = nil
            self.drainScheduled = false
            let n = self.framesSinceTick
            let ww = self.gw, hh = self.gh
            self.pendingLock.unlock()
            guard let (i, no) = item else { return }
            self.width = ww; self.height = hh
            self.image = i
            self.frame = no
            let t = CFAbsoluteTimeGetCurrent()
            if t - self.lastTick >= 0.5 {
                self.fps = Double(n) / (t - self.lastTick)
                self.pendingLock.lock(); self.framesSinceTick = 0; self.pendingLock.unlock()
                self.lastTick = t
            }
        }
    }

    static func snapshotIfRequested(_ px: [UInt32], _ w: Int, _ h: Int, _ no: Int) {
        guard let path = ProcessInfo.processInfo.environment["NIECHE_SNAPSHOT"] else { return }
        let want = Int(ProcessInfo.processInfo.environment["NIECHE_SNAPSHOT_FRAME"] ?? "20") ?? 20
        guard no == want else { return }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let dst = ctx.data else { exit(2) }
        px.withUnsafeBytes { dst.copyMemory(from: $0.baseAddress!, byteCount: w * h * 4) }
        guard let img = ctx.makeImage(),
              let out = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { exit(3) }
        CGImageDestinationAddImage(out, img, nil)
        CGImageDestinationFinalize(out)
        exit(0)
    }

    private func append(log s: String) {
        guard !s.isEmpty else { return }
        logs.append(s)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
    }
}

struct ScreenView: View {
    @ObservedObject var engine: Engine
    var scale: CGFloat
    var rotate: Int
    var smooth: Bool
    @State private var touching = false

    var body: some View {
        let gw = CGFloat(engine.width), gh = CGFloat(engine.height)
        let w = gw * scale, h = gh * scale
        let turned = rotate % 180 != 0
        Group {
            if let img = engine.image {

                Image(img, scale: 1, label: Text("屏幕"))
                    .interpolation(smooth ? .high : .none)
                    .resizable()
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(Double(rotate)))
                    .frame(width: turned ? h : w, height: turned ? w : h)
            } else {
                Rectangle().fill(.black)
                    .frame(width: w, height: h)
                    .overlay(Text("从左侧游戏库里选一个双击运行").foregroundStyle(.secondary))
            }
        }
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in

                let p = guestPoint(g.location)
                engine.send(["touch": [p.0, p.1, touching ? "move" : "down"]])
                touching = true
            }
            .onEnded { g in
                let p = guestPoint(g.location)
                engine.send(["touch": [p.0, p.1, "up"]])
                touching = false
            })
    }

    private func guestPoint(_ loc: CGPoint) -> (Int, Int) {
        let W = CGFloat(engine.width), H = CGFloat(engine.height)
        let x = loc.x / scale, y = loc.y / scale
        let (u, v): (CGFloat, CGFloat)
        switch ((rotate % 360) + 360) % 360 {
        case 90:  (u, v) = (y, H - x)
        case 180: (u, v) = (W - x, H - y)
        case 270: (u, v) = (W - y, x)
        default:  (u, v) = (x, y)
        }
        return (Int(min(max(u, 0), W - 1)), Int(min(max(v, 0), H - 1)))
    }
}

struct ContentView: View {

    let engine: Engine
    @StateObject private var lib = GameLibrary()
    @StateObject private var keymap = KeyMap()
    @State private var selected: GameItem?
    @State private var heldKeys: Set<String> = []
    @State private var fitWindow = true
    @State private var manualScale: CGFloat = 2
    @State private var rotate = 0
    @State private var fpsTarget = 30
    @State private var upscale: UpscaleMode = .nearest
    @State private var soundOn = true
    @State private var volume: Double = 0.7
    @State private var monitor: Any?

    @AppStorage("libraryOpen") private var libOpen = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if libOpen {
                LibraryPane(lib: lib, selected: $selected, projectDir: engine.projectDir) { g in
                    engine.start(module: g.url, fps: fpsTarget)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            libraryToggle
            screenColumn
            controlColumn
        }
        .padding(14)
        .onAppear { installKeyMonitor() }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) } }
    }

    private var libraryToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { libOpen.toggle() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: libOpen ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                if !libOpen {
                    Text("游戏库")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(90))
                        .fixedSize()
                        .frame(width: 14, height: 44)
                }
            }
            .frame(width: 16)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(libOpen ? "收起游戏库" : "展开游戏库")
    }

    private var screenColumn: some View {
        ScreenColumn(engine: engine, fitWindow: fitWindow, manualScale: manualScale,
                     rotate: rotate, upscale: upscale)
    }

    private var controlColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EngineTitleBar(engine: engine, onOpen: pick)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("缩放").font(.caption)
                        HStack(spacing: 6) {
                            Toggle("适应窗口", isOn: $fitWindow).toggleStyle(.checkbox)
                            if !fitWindow {
                                Stepper("\(Int(manualScale))×", value: $manualScale, in: 1...6)
                            }
                        }
                    }
                    GridRow {
                        Text("旋转").font(.caption)
                        Picker("", selection: $rotate) {
                            Text("0°").tag(0); Text("90°").tag(90)
                            Text("180°").tag(180); Text("270°").tag(270)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                    }
                    GridRow {
                        Text("放大").font(.caption)
                        Picker("", selection: $upscale) {
                            ForEach(UpscaleMode.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
                            .onChange(of: upscale) { m in engine.mode = m }
                    }
                    GridRow {
                        Text("声音").font(.caption)
                        HStack(spacing: 8) {
                            Toggle("开", isOn: $soundOn).toggleStyle(.checkbox)
                                .onChange(of: soundOn) { v in engine.audio.enabled = v }
                            Slider(value: $volume, in: 0...1) { Text("音量") }
                                .frame(width: 120).labelsHidden()
                                .onChange(of: volume) { v in engine.audio.volume = Float(v) }
                        }
                    }
                    GridRow {
                        Text("帧率").font(.caption)
                        Stepper("\(fpsTarget)", value: $fpsTarget, in: 5...120, step: 5)
                            .onChange(of: fpsTarget) { v in engine.send(["fps": v]) }
                    }
                }
                Divider()
                KeypadView(map: keymap, held: $heldKeys) { mask in
                    engine.send(["keys": mask])
                }
                Divider()
                Text("模块日志").font(.caption).foregroundStyle(.secondary)
                LogPane(engine: engine)
            }
            .padding(.trailing, 4)
        }
        .frame(minWidth: 290, idealWidth: 320, maxWidth: 360)
    }

    private func installKeyMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { ev in
            guard let id = keymap.phoneKey(code: ev.keyCode) else { return ev }

            if ev.type == .keyDown && ev.isARepeat { return nil }
            if ev.type == .keyDown { heldKeys.insert(id) } else { heldKeys.remove(id) }
            engine.send(["keys": heldKeys.reduce(0) { $0 | keymap.mask($1) }])
            return nil
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cbe") ?? .data]
        panel.allowsOtherFileTypes = true
        panel.directoryURL = engine.projectDir.appendingPathComponent("assets/cbe")
        if panel.runModal() == .OK, let url = panel.url {
            let mounted = lib.mount(url) ?? url
            engine.start(module: mounted, fps: fpsTarget)
        }
    }
}

@main
struct NiecheEmuApp: App {
    @StateObject private var engine: Engine

    init() {
        _engine = StateObject(wrappedValue: Engine(projectDir: NiecheEmuApp.findProjectDir()))
    }

    static func findProjectDir() -> URL {
        if let e = ProcessInfo.processInfo.environment["NIECHE_DIR"] {
            return URL(fileURLWithPath: e)
        }

        if let bundled = Bundle.main.url(forResource: "engine", withExtension: nil),
           FileManager.default.fileExists(
               atPath: bundled.appendingPathComponent("tools/engine.py").path) {
            return bundled
        }
        if let r = Bundle.main.url(forResource: "project_dir", withExtension: nil),
           let s = try? String(contentsOf: r, encoding: .utf8) {
            let p = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { return URL(fileURLWithPath: p) }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    var body: some Scene {
        WindowGroup("尼彩 CBE 模拟器") {
            ContentView(engine: engine)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    if let m = ProcessInfo.processInfo.environment["NIECHE_MODULE"] {
                        engine.start(module: URL(fileURLWithPath: m), fps: 30)
                    }

                    NotificationCenter.default.addObserver(
                        forName: NSApplication.willTerminateNotification,
                        object: nil, queue: .main) { _ in engine.stop() }
                }
        }

        .windowResizability(.contentMinSize)
    }
}

struct ScreenColumn: View {
    @ObservedObject var engine: Engine
    var fitWindow: Bool
    var manualScale: CGFloat
    var rotate: Int
    var upscale: UpscaleMode

    var body: some View {
        GeometryReader { geo in
            let turned = rotate % 180 != 0
            let gw = CGFloat(max(engine.width, 1)), gh = CGFloat(max(engine.height, 1))
            let needW = turned ? gh : gw, needH = turned ? gw : gh
            let fitScale = max(1, min(floor(geo.size.width / needW),
                                      floor((geo.size.height - 26) / needH)))
            let s = fitWindow ? fitScale : manualScale
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                ScreenView(engine: engine, scale: s, rotate: rotate,
                           smooth: upscale.interpolate)
                Text(verbatim: String(format: "帧 %d · %.1f fps · %d×%@",
                                      engine.frame, engine.fps, Int(s),
                                      upscale == .nearest ? "" : " · " + upscale.rawValue))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minWidth: 250)
    }
}

struct EngineTitleBar: View {
    @ObservedObject var engine: Engine
    var onOpen: () -> Void
    var body: some View {
        HStack {
            Text(engine.title).font(.headline).lineLimit(1)
            Spacer()
            Button("打开文件…", action: onOpen)
            if engine.running { Button("停止") { engine.stop() } }
        }
    }
}

struct LogPane: View {
    @ObservedObject var engine: Engine
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(engine.logs.suffix(40).enumerated()), id: \.offset) { _, l in
                Text(l).font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
