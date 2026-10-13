import AVFoundation
import AVKit
import UIKit

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor
final class AVEngine: NSObject, PlaybackEngine {
    let name = "AVPlayer"
    var onEvent: ((EngineEvent) -> Void)?

    private let player = AVPlayer()
    private let layerView = PlayerLayerView()
    private var pip: AVPictureInPictureController?
    private var observers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var isLive = false
    private var desiredRate: Float = 1
    private var lastURL: URL?
    private var audioGroup: AVMediaSelectionGroup?
    private var legibleGroup: AVMediaSelectionGroup?
    private var pipObservers: [NSKeyValueObservation] = []
    private var itemObserver: NSKeyValueObservation?

    var view: UIView { layerView }

    override init() {
        super.init()
        layerView.backgroundColor = .black
        layerView.playerLayer.player = player
        layerView.playerLayer.videoGravity = .resizeAspect
        player.allowsExternalPlayback = true
        player.appliesMediaSelectionCriteriaAutomatically = true
        player.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(preferredLanguages: ["pt-BR", "pt"], preferredMediaCharacteristics: nil), forMediaCharacteristic: .audible)

        if AVPictureInPictureController.isPictureInPictureSupported(), let pip = AVPictureInPictureController(playerLayer: layerView.playerLayer) {
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            pip.delegate = self
            self.pip = pip
            pipObservers.append(pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] p, _ in
                Task { @MainActor in self?.onEvent?(.pip(active: p.isPictureInPictureActive, possible: p.isPictureInPicturePossible)) }
            })
        }

        observers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.onEvent?(.playing(p.timeControlStatus == .playing))
                self.onEvent?(.buffering(p.timeControlStatus == .waitingToPlayAtSpecifiedRate))
            }
        })

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.emitTime() }
        }
    }

    func load(_ url: URL, start: Double, live: Bool) {
        isLive = live
        lastURL = url
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = live ? 6 : 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = live
        if live { item.automaticallyPreservesTimeOffsetFromLive = true }

        itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.onEvent?(.ready)
                    await self.loadTracks(item)
                case .failed:
                    self.onEvent?(.failed(item.error?.localizedDescription ?? "Não foi possível reproduzir."))
                default: break
                }
            }
        }

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.ended) }
        }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.onEvent?(.failed(err?.localizedDescription ?? "A transmissão foi interrompida."))
            }
        }

        player.replaceCurrentItem(with: item)
        if start > 1 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
        play()
    }

    private func emitTime() {
        guard let item = player.currentItem else { return }
        let pos = player.currentTime().seconds
        var dur = item.duration.seconds
        if !dur.isFinite { dur = 0 }
        let buffered = item.loadedTimeRanges.map(\.timeRangeValue).map { ($0.start + $0.duration).seconds }.max() ?? 0
        onEvent?(.time(position: pos.isFinite ? pos : 0, duration: dur, buffered: buffered))
    }

    private func loadTracks(_ item: AVPlayerItem) async {
        audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible)
        legibleGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        onEvent?(.tracksChanged)
    }

    func play() { player.playImmediately(atRate: isLive ? 1 : desiredRate) }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated { self?.emitTime() }
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        observers.removeAll()
        itemObserver = nil
        pipObservers.removeAll()
    }

    func setRate(_ rate: Float) {
        desiredRate = rate
        if player.timeControlStatus != .paused { player.rate = rate }
    }

    func setGravity(_ gravity: VideoGravity) {
        let g: AVLayerVideoGravity = switch gravity {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        case .stretch: .resize
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        layerView.playerLayer.videoGravity = g
        CATransaction.commit()
    }

    // MARK: Tracks

    var audioTracks: [MediaTrack] {
        audioGroup?.options.enumerated().map { MediaTrack(id: "\($0.offset)", name: Self.label($0.element)) } ?? []
    }
    var subtitleTracks: [MediaTrack] {
        legibleGroup?.options.enumerated()
            .filter { !$0.element.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
            .map { MediaTrack(id: "\($0.offset)", name: Self.label($0.element)) } ?? []
    }
    var selectedAudio: String? { selectedID(audioGroup) }
    var selectedSubtitle: String? { selectedID(legibleGroup) }

    private func selectedID(_ group: AVMediaSelectionGroup?) -> String? {
        guard let group, let item = player.currentItem, let opt = item.currentMediaSelection.selectedMediaOption(in: group) else { return nil }
        return group.options.firstIndex(of: opt).map { "\($0)" }
    }

    func selectAudio(_ id: String) {
        guard let group = audioGroup, let i = Int(id), group.options.indices.contains(i) else { return }
        player.currentItem?.select(group.options[i], in: group)
        onEvent?(.tracksChanged)
    }

    func selectSubtitle(_ id: String?) {
        guard let group = legibleGroup else { return }
        if let id, let i = Int(id), group.options.indices.contains(i) {
            player.currentItem?.select(group.options[i], in: group)
        } else {
            player.currentItem?.select(nil, in: group)
        }
        onEvent?(.tracksChanged)
    }

    private static func label(_ o: AVMediaSelectionOption) -> String {
        let name = o.displayName
        if let code = o.extendedLanguageTag ?? o.locale?.identifier,
           let local = Locale(identifier: "pt_BR").localizedString(forIdentifier: code), !name.localizedCaseInsensitiveContains(local) {
            return local.capitalized
        }
        return name.capitalized
    }

    // MARK: PiP

    var supportsPiP: Bool { pip != nil }
    func togglePiP() {
        guard let pip else { return }
        pip.isPictureInPictureActive ? pip.stopPictureInPicture() : pip.startPictureInPicture()
    }
}

extension AVEngine: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.onEvent?(.pip(active: true, possible: true)) }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.onEvent?(.pip(active: false, possible: true)) }
    }
}
