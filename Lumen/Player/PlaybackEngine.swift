import UIKit

struct MediaTrack: Identifiable, Hashable {
    let id: String
    let name: String
}

enum VideoGravity: String, CaseIterable, Identifiable {
    case fit, fill, stretch
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fit: "Ajustar"
        case .fill: "Preencher"
        case .stretch: "Esticar"
        }
    }
    var symbol: String {
        switch self {
        case .fit: "rectangle.arrowtriangle.2.inward"
        case .fill: "rectangle.arrowtriangle.2.outward"
        case .stretch: "arrow.left.and.right.square"
        }
    }
}

enum EngineEvent {
    case time(position: Double, duration: Double, buffered: Double)
    case playing(Bool)
    case buffering(Bool)
    case ready
    case tracksChanged
    case ended
    case failed(String)
    case pip(active: Bool, possible: Bool)
}

/// The surface the player UI talks to. Two implementations: AVPlayer (native, PiP, AirPlay)
/// and VLC (everything else: mkv, avi, odd codecs, raw MPEG-TS).
@MainActor
protocol PlaybackEngine: AnyObject {
    var view: UIView { get }
    var onEvent: ((EngineEvent) -> Void)? { get set }
    var name: String { get }

    func load(_ url: URL, start: Double, live: Bool)
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()

    func setRate(_ rate: Float)
    func setGravity(_ gravity: VideoGravity)

    var audioTracks: [MediaTrack] { get }
    var subtitleTracks: [MediaTrack] { get }
    var selectedAudio: String? { get }
    var selectedSubtitle: String? { get }
    func selectAudio(_ id: String)
    func selectSubtitle(_ id: String?)

    var supportsPiP: Bool { get }
    func togglePiP()
}

extension PlaybackEngine {
    var supportsPiP: Bool { false }
    func togglePiP() {}
}
