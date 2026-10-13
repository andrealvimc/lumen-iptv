import UIKit
import MobileVLCKit

/// Fallback engine for containers/codecs AVPlayer can't open (mkv, avi, raw TS…).
@MainActor
final class VLCEngine: NSObject, PlaybackEngine {
    let name = "VLC"
    var onEvent: ((EngineEvent) -> Void)?

    private let player = VLCMediaPlayer()
    private let surface = UIView()
    private var gravity: VideoGravity = .fit
    private var startAt: Double = 0
    private var didSeekToStart = false
    private var isLive = false

    var view: UIView { surface }

    override init() {
        super.init()
        surface.backgroundColor = .black
        player.drawable = surface
        player.delegate = self
    }

    func load(_ url: URL, start: Double, live: Bool) {
        isLive = live
        startAt = start
        didSeekToStart = start <= 1
        let media = VLCMedia(url: url)
        media.addOptions([
            "network-caching": live ? 1500 : 3000,
            "http-reconnect": true,
            "clock-jitter": 0,
            "clock-synchro": 0,
        ])
        player.media = media
        player.play()
        onEvent?(.buffering(true))
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.time = VLCTime(int: Int32(max(seconds, 0) * 1000))
        emitTime()
    }

    func stop() {
        player.delegate = nil
        player.stop()
        player.media = nil
    }

    func setRate(_ rate: Float) { player.rate = rate }

    func setGravity(_ g: VideoGravity) {
        gravity = g
        applyGravity()
    }

    private func applyGravity() {
        let size = surface.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let ratio = "\(Int(size.width)):\(Int(size.height))"
        switch gravity {
        case .fit:
            player.videoCropGeometry = nil
            player.videoAspectRatio = nil
        case .fill:
            player.videoAspectRatio = nil
            ratio.withCString { player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) }
        case .stretch:
            player.videoCropGeometry = nil
            ratio.withCString { player.videoAspectRatio = UnsafeMutablePointer(mutating: $0) }
        }
    }

    private func emitTime() {
        let pos = Double(player.time.intValue) / 1000
        let len = Double(player.media?.length.intValue ?? 0) / 1000
        onEvent?(.time(position: max(pos, 0), duration: isLive ? 0 : max(len, 0), buffered: 0))
    }

    // MARK: Tracks

    private func tracks(names: [Any]?, ids: [Any]?) -> [MediaTrack] {
        guard let names = names as? [String], let ids = ids as? [NSNumber] else { return [] }
        return zip(ids, names).filter { $0.0.int32Value >= 0 }.map { MediaTrack(id: $0.0.stringValue, name: $0.1) }
    }

    var audioTracks: [MediaTrack] { tracks(names: player.audioTrackNames, ids: player.audioTrackIndexes) }
    var subtitleTracks: [MediaTrack] { tracks(names: player.videoSubTitlesNames, ids: player.videoSubTitlesIndexes) }
    var selectedAudio: String? { "\(player.currentAudioTrackIndex)" }
    var selectedSubtitle: String? { player.currentVideoSubTitleIndex >= 0 ? "\(player.currentVideoSubTitleIndex)" : nil }

    func selectAudio(_ id: String) {
        if let i = Int32(id) { player.currentAudioTrackIndex = i }
        onEvent?(.tracksChanged)
    }

    func selectSubtitle(_ id: String?) {
        player.currentVideoSubTitleIndex = id.flatMap(Int32.init) ?? -1
        onEvent?(.tracksChanged)
    }
}

extension VLCEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            switch self.player.state {
            case .buffering:
                self.onEvent?(.buffering(!self.player.isPlaying))
            case .playing:
                self.onEvent?(.buffering(false))
                self.onEvent?(.playing(true))
                self.onEvent?(.ready)
                self.onEvent?(.tracksChanged)
                self.applyGravity()
            case .paused:
                self.onEvent?(.playing(false))
            case .ended:
                self.onEvent?(.playing(false))
                self.onEvent?(.ended)
            case .error:
                self.onEvent?(.failed("O VLC não conseguiu abrir este conteúdo."))
            default: break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            if !self.didSeekToStart, (self.player.media?.length.intValue ?? 0) > 0 {
                self.didSeekToStart = true
                self.player.time = VLCTime(int: Int32(self.startAt * 1000))
            }
            self.onEvent?(.buffering(false))
            self.emitTime()
        }
    }
}
