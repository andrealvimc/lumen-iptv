import Foundation

enum MediaRef: Codable, Hashable, Sendable {
    case live(Int)
    case movie(Int, ext: String)
    case episode(String, ext: String, seriesID: Int, season: Int, number: Int)

    var key: String {
        switch self {
        case .live(let id): "live:\(id)"
        case .movie(let id, _): "movie:\(id)"
        case .episode(let id, _, _, _, _): "episode:\(id)"
        }
    }

    var isLive: Bool { if case .live = self { true } else { false } }
}

/// Everything the player needs to show and resume an item. URLs are rebuilt from the
/// current credentials so nothing secret is persisted with progress.
struct PlayableItem: Identifiable, Codable, Hashable, Sendable {
    var ref: MediaRef
    var title: String
    var subtitle: String?
    var artwork: URL?
    var backdrop: URL?

    var id: String { ref.key }
}

struct PlaybackProgress: Codable, Hashable, Sendable {
    var item: PlayableItem
    var position: Double
    var duration: Double
    var updated: Date

    var fraction: Double { duration > 0 ? min(position / duration, 1) : 0 }
    var isFinished: Bool { duration > 0 && (fraction > 0.94 || duration - position < 90) }
    var remaining: Double { max(duration - position, 0) }
}

struct PlaybackSession: Identifiable {
    let id = UUID()
    var queue: [PlayableItem]
    var index: Int
    var current: PlayableItem { queue[index] }
}

extension Double {
    /// 5880 → "1:38:00", 75 → "1:15"
    var clock: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let s = Int(self)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 5880 → "1h 38min"
    var humanDuration: String {
        let m = Int(self) / 60
        if m < 60 { return "\(max(m, 1)) min" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)min"
    }
}
