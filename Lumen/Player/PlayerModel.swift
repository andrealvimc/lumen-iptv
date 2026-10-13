import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor @Observable
final class PlayerModel {
    // Playback state
    private(set) var item: PlayableItem
    private(set) var queue: [PlayableItem]
    private(set) var index: Int
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var buffered: Double = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = true
    private(set) var hasStarted = false
    private(set) var error: String?
    private(set) var engineName = ""
    private(set) var pipPossible = false
    private(set) var pipActive = false
    private(set) var audioTracks: [MediaTrack] = []
    private(set) var subtitleTracks: [MediaTrack] = []
    private(set) var selectedAudio: String?
    private(set) var selectedSubtitle: String?

    // User adjustable
    var rate: Float = 1 { didSet { engine?.setRate(rate) } }
    var gravity: VideoGravity = .fit { didSet { engine?.setGravity(gravity) } }

    // UI
    var controlsVisible = true
    var isScrubbing = false
    var scrubPosition: Double = 0
    var showQueue = false
    var isLocked = false

    private(set) var engine: PlaybackEngine?
    private(set) var engineGeneration = 0
    private let app: AppModel
    private var triedFallback = false
    private var hideTask: Task<Void, Never>?
    private var lastSaved: Date = .distantPast
    private var retryCount = 0

    var isLive: Bool { item.ref.isLive }
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }
    var nextItem: PlayableItem? { hasNext ? queue[index + 1] : nil }
    var displayPosition: Double { isScrubbing ? scrubPosition : position }

    /// Seconds left before we offer the next episode.
    var upNextCountdown: Double? {
        guard !isLive, hasNext, case .episode = item.ref, duration > 120 else { return nil }
        let left = duration - position
        return left < 25 && left > 0 ? left : nil
    }

    init(session: PlaybackSession, app: AppModel) {
        self.app = app
        queue = session.queue
        index = session.index
        item = session.current
        configureAudioSession()
        configureRemoteCommands()
    }

    // MARK: - Lifecycle

    func start() { load(item, resume: true) }

    func teardown() {
        persist(force: true)
        hideTask?.cancel()
        engine?.stop()
        engine = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let rc = MPRemoteCommandCenter.shared()
        [rc.playCommand, rc.pauseCommand, rc.togglePlayPauseCommand, rc.skipForwardCommand, rc.skipBackwardCommand, rc.changePlaybackPositionCommand, rc.nextTrackCommand, rc.previousTrackCommand].forEach { $0.removeTarget(nil) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func load(_ item: PlayableItem, resume: Bool, forceVLC: Bool = false) {
        persist(force: true)
        self.item = item
        position = 0; duration = 0; buffered = 0
        error = nil
        hasStarted = false
        isBuffering = true
        audioTracks = []; subtitleTracks = []
        triedFallback = forceVLC
        if case .live(let id) = item.ref { app.noteChannel(id) }

        let useVLC = forceVLC || shouldUseVLC(item.ref)
        guard let url = app.url(for: item.ref, preferTS: useVLC && isLive) else { error = "Sessão expirada."; return }

        var start: Double = 0
        if resume, let p = app.progress[item.id], !p.isFinished { start = p.position }

        install(useVLC ? VLCEngine() : AVEngine())
        engine?.load(url, start: start, live: isLive)
        updateNowPlaying()
        bumpControls()
    }

    private func shouldUseVLC(_ ref: MediaRef) -> Bool {
        switch app.enginePreference {
        case .vlc: return true
        case .native: return false
        case .automatic:
            switch ref {
            case .live: return false
            case .movie(_, let ext), .episode(_, let ext, _, _, _):
                return !["mp4", "m4v", "mov", "m3u8"].contains(ext.lowercased())
            }
        }
    }

    private func install(_ new: PlaybackEngine) {
        engine?.stop()
        engine = new
        engineGeneration += 1
        engineName = new.name
        new.setRate(isLive ? 1 : rate)
        new.setGravity(gravity)
        new.onEvent = { [weak self, weak new] event in
            guard let self, let new, new === self.engine else { return }
            self.handle(event)
        }
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case let .time(pos, dur, buf):
            position = pos
            duration = dur
            buffered = buf
            if pos > 0 && !hasStarted { hasStarted = true; retryCount = 0 }
            persist()
            updateNowPlayingTime()
        case .playing(let p):
            isPlaying = p
            if p { hasStarted = true; isBuffering = false }
            updateNowPlayingTime()
        case .buffering(let b):
            isBuffering = b
        case .ready:
            break
        case .tracksChanged:
            audioTracks = engine?.audioTracks ?? []
            subtitleTracks = engine?.subtitleTracks ?? []
            selectedAudio = engine?.selectedAudio
            selectedSubtitle = engine?.selectedSubtitle
        case .ended:
            if isLive { reconnect() }
            else {
                persist(force: true)
                if hasNext && app.autoplayNext { next() } else { controlsVisible = true }
            }
        case .failed(let message):
            if !triedFallback && app.enginePreference == .automatic && engine is AVEngine {
                // AVPlayer can't handle it — hand the same item to VLC transparently.
                triedFallback = true
                let resumeAt = position
                guard let url = app.url(for: item.ref, preferTS: isLive) else { return }
                install(VLCEngine())
                engine?.load(url, start: resumeAt, live: isLive)
            } else if isLive && retryCount < 2 {
                reconnect()
            } else {
                error = message
                isBuffering = false
                controlsVisible = true
            }
        case let .pip(active, possible):
            pipActive = active
            pipPossible = possible
        }
    }

    private func reconnect() {
        retryCount += 1
        let current = item
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard current == self.item else { return }
            self.load(current, resume: false, forceVLC: self.engine is VLCEngine)
        }
    }

    // MARK: - Transport

    func togglePlay() {
        if isPlaying { engine?.pause(); isPlaying = false } else { engine?.play(); isPlaying = true }
        bumpControls()
    }

    func skip(_ delta: Double) {
        guard !isLive else { return }
        let target = min(max(position + delta, 0), duration > 0 ? duration - 1 : .infinity)
        position = target
        engine?.seek(to: target)
        bumpControls()
    }

    func commitScrub() {
        position = scrubPosition
        engine?.seek(to: scrubPosition)
        isScrubbing = false
        bumpControls()
    }

    func retry() { load(item, resume: true, forceVLC: engine is VLCEngine) }
    func retryWithVLC() { load(item, resume: true, forceVLC: true) }

    func next() { jump(to: index + 1) }
    func previous() { jump(to: index - 1) }

    func jump(to i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        load(queue[i], resume: !isLiveRef(queue[i].ref))
    }

    private func isLiveRef(_ r: MediaRef) -> Bool { r.isLive }

    func selectAudio(_ id: String) { engine?.selectAudio(id) }
    func selectSubtitle(_ id: String?) { engine?.selectSubtitle(id) }
    func togglePiP() { engine?.togglePiP() }

    // MARK: - Controls visibility

    func toggleControls() {
        withAnimationIfNeeded { controlsVisible.toggle() }
        if controlsVisible { bumpControls() }
    }

    func bumpControls() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self.isPlaying, !self.isScrubbing, !self.showQueue, self.error == nil else { return }
            self.withAnimationIfNeeded { self.controlsVisible = false }
        }
    }

    private func withAnimationIfNeeded(_ body: () -> Void) { body() }

    // MARK: - Persistence & system integration

    private func persist(force: Bool = false) {
        guard !isLive, hasStarted, duration > 0 else { return }
        guard force || Date().timeIntervalSince(lastSaved) > 5 else { return }
        lastSaved = .now
        app.saveProgress(item, position: position, duration: duration)
    }

    private func configureAudioSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        try? s.setActive(true)
    }

    private func configureRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { [weak self] _ in self?.engine?.play(); return .success }
        rc.pauseCommand.addTarget { [weak self] _ in self?.engine?.pause(); return .success }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(); return .success }
        rc.skipForwardCommand.preferredIntervals = [10]
        rc.skipBackwardCommand.preferredIntervals = [10]
        rc.skipForwardCommand.addTarget { [weak self] _ in self?.skip(10); return .success }
        rc.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(-10); return .success }
        rc.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        rc.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        rc.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.engine?.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.subtitle.map { "\(item.title) — \($0)" } ?? item.title,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let s = item.subtitle { info[MPMediaItemPropertyArtist] = s }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        let rc = MPRemoteCommandCenter.shared()
        rc.skipForwardCommand.isEnabled = !isLive
        rc.skipBackwardCommand.isEnabled = !isLive
        rc.changePlaybackPositionCommand.isEnabled = !isLive
        rc.nextTrackCommand.isEnabled = hasNext
        rc.previousTrackCommand.isEnabled = hasPrevious

        if let art = item.backdrop ?? item.artwork {
            let key = item.id
            Task {
                guard let img = await ImagePipeline.shared.image(for: art, maxPixel: 600), key == self.item.id else { return }
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            }
        }
    }

    private func updateNowPlayingTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
