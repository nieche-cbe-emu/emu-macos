
import AVFoundation
import Foundation

final class AudioOut {
    private var midi: AVMIDIPlayer?
    private var sample: AVAudioPlayer?
    private var loopTimer: Timer?
    private(set) var now = ""

    var enabled = true { didSet { if !enabled { stop() } } }
    var volume: Float = 0.7 {
        didSet { sample?.volume = volume }
    }

    func handle(_ event: [String: Any]) {
        guard enabled else { return }
        switch event["op"] as? String {
        case "play":
            guard let path = event["path"] as? String else { return }
            play(URL(fileURLWithPath: path),
                 loop: event["loop"] as? Bool ?? false,
                 name: event["name"] as? String ?? "")
        case "stop":
            stop()
        default:
            break
        }
    }

    private func play(_ url: URL, loop: Bool, name: String) {
        stop()
        now = name
        let ext = url.pathExtension.lowercased()
        if ext == "mid" || ext == "midi" {
            guard let p = try? AVMIDIPlayer(contentsOf: url, soundBankURL: nil) else { return }
            p.prepareToPlay()
            midi = p
            p.play { [weak self] in

                guard loop, let s = self, s.midi === p, s.enabled else { return }
                DispatchQueue.main.async { s.play(url, loop: true, name: name) }
            }
        } else {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.numberOfLoops = loop ? -1 : 0
            p.volume = volume
            p.prepareToPlay()
            p.play()
            sample = p
        }
    }

    func stop() {
        midi?.stop(); midi = nil
        sample?.stop(); sample = nil
        loopTimer?.invalidate(); loopTimer = nil
        now = ""
    }
}
