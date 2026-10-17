
import Foundation

enum MirrorSafety {

    static func localName(_ remote: String) -> String? {
        let decoded = remote.removingPercentEncoding ?? remote
        let last = decoded
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last.map(String.init) ?? ""
        let name = last.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." || name.contains("\0") {
            return nil
        }
        return name
    }

    static func mayAttachToken(to url: URL, indexURL: URL?) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              let indexHost = indexURL?.host?.lowercased()
        else { return false }
        return host == indexHost
    }

    static func isInside(_ dst: URL, root: URL) -> Bool {
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        let d = dst.standardizedFileURL.resolvingSymlinksInPath()
            .deletingLastPathComponent().path
        return d == r
    }
}

final class StripAuthOnRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var r = request
        let from = task.originalRequest?.url?.host?.lowercased()
        if r.url?.host?.lowercased() != from || r.url?.scheme?.lowercased() != "https" {
            r.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(r)
    }
}
