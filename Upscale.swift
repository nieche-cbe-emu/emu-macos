
import Foundation

enum UpscaleMode: String, CaseIterable, Identifiable {
    case nearest = "像素"
    case smooth  = "平滑"
    case scale2x = "Scale2x"
    case scale3x = "Scale3x"
    var id: String { rawValue }

    var factor: Int {
        switch self {
        case .scale2x: return 2
        case .scale3x: return 3
        default:       return 1
        }
    }

    var interpolate: Bool { self == .smooth }
}

enum Upscale {

    static func scale2x(_ src: [UInt32], _ w: Int, _ h: Int, _ dst: inout [UInt32]) {
        if dst.count != w * h * 4 { dst = [UInt32](repeating: 0, count: w * h * 4) }
        let dw = w * 2
        src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                for y in 0..<h {
                    let up = y > 0 ? (y - 1) * w : y * w
                    let dn = y < h - 1 ? (y + 1) * w : y * w
                    let cur = y * w
                    for x in 0..<w {
                        let p = s[cur + x]
                        let a = s[up + x]
                        let b = s[cur + min(x + 1, w - 1)]
                        let c = s[cur + max(x - 1, 0)]
                        let dd = s[dn + x]
                        var e0 = p, e1 = p, e2 = p, e3 = p
                        if c == a && c != dd && a != b { e0 = a }
                        if a == b && a != c && b != dd { e1 = b }
                        if dd == c && dd != b && c != a { e2 = c }
                        if b == dd && b != a && dd != c { e3 = dd }
                        let o = (y * 2) * dw + x * 2
                        d[o] = e0; d[o + 1] = e1
                        d[o + dw] = e2; d[o + dw + 1] = e3
                    }
                }
            }
        }
    }

    static func scale3x(_ src: [UInt32], _ w: Int, _ h: Int, _ dst: inout [UInt32]) {
        if dst.count != w * h * 9 { dst = [UInt32](repeating: 0, count: w * h * 9) }
        let dw = w * 3
        src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                for y in 0..<h {
                    let uy = y > 0 ? y - 1 : y
                    let dy = y < h - 1 ? y + 1 : y
                    for x in 0..<w {
                        let lx = x > 0 ? x - 1 : x
                        let rx = x < w - 1 ? x + 1 : x
                        let p  = s[y * w + x]
                        let a  = s[uy * w + lx], b = s[uy * w + x], c = s[uy * w + rx]
                        let dd = s[y  * w + lx],                     f = s[y  * w + rx]
                        let g  = s[dy * w + lx], hh = s[dy * w + x], i = s[dy * w + rx]

                        var e0 = p, e1 = p, e2 = p
                        var e3 = p, e5 = p
                        var e6 = p, e7 = p, e8 = p
                        if dd == b && dd != hh && b != f { e0 = dd }
                        if (dd == b && dd != hh && b != f && p != c) ||
                           (b == f && b != dd && f != hh && p != a) { e1 = b }
                        if b == f && b != dd && f != hh { e2 = f }
                        if (hh == dd && hh != f && dd != b && p != a) ||
                           (dd == b && dd != hh && b != f && p != g) { e3 = dd }
                        if (b == f && b != dd && f != hh && p != i) ||
                           (f == hh && f != b && hh != dd && p != c) { e5 = f }
                        if hh == dd && hh != f && dd != b { e6 = dd }
                        if (f == hh && f != b && hh != dd && p != g) ||
                           (hh == dd && hh != f && dd != b && p != i) { e7 = hh }
                        if f == hh && f != b && hh != dd { e8 = hh }
                        let o = (y * 3) * dw + x * 3
                        d[o] = e0; d[o + 1] = e1; d[o + 2] = e2
                        d[o + dw] = e3; d[o + dw + 1] = p; d[o + dw + 2] = e5
                        d[o + dw * 2] = e6; d[o + dw * 2 + 1] = e7; d[o + dw * 2 + 2] = e8
                    }
                }
            }
        }
    }

    static func apply(_ mode: UpscaleMode, _ px: [UInt32], _ w: Int, _ h: Int,
                      into buf: inout [UInt32]) -> (Bool, Int, Int) {
        switch mode {
        case .scale2x: scale2x(px, w, h, &buf); return (true, w * 2, h * 2)
        case .scale3x: scale3x(px, w, h, &buf); return (true, w * 3, h * 3)
        default:       return (false, w, h)
        }
    }
}
