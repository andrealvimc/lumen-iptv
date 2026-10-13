import Foundation
import Observation
import UIKit

enum EnginePreference: String, CaseIterable, Identifiable, Codable {
    case automatic, native, vlc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Automático"
        case .native: "Nativo (AVPlayer)"
        case .vlc: "VLC"
        }
    }
}

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    private(set) var credentials: Credentials?
    private(set) var account: AccountInfo?
    private(set) var phase: Phase = .idle
    private(set) var isRefreshing = false

    private(set) var liveCategories: [Category] = []
    private(set) var channels: [Channel] = []
    private(set) var movieCategories: [Category] = []
    private(set) var movies: [Movie] = []
    private(set) var seriesCategories: [Category] = []
    private(set) var series: [Show] = []

    private(set) var channelsByCategory: [String: [Channel]] = [:]
    private(set) var moviesByCategory: [String: [Movie]] = [:]
    private(set) var seriesByCategory: [String: [Show]] = [:]
    private(set) var recentMovies: [Movie] = []
    private(set) var recentSeries: [Show] = []

    private(set) var favorites: Set<String> = []
    private(set) var progress: [String: PlaybackProgress] = [:]
    private(set) var recentChannels: [Int] = []

    var session: PlaybackSession?

    var enginePreference: EnginePreference {
        didSet { defaults.set(enginePreference.rawValue, forKey: "engine") }
    }
    var autoplayNext: Bool {
        didSet { defaults.set(autoplayNext, forKey: "autoplayNext") }
    }

    private let defaults = UserDefaults.standard
    private var movieIndex: [Int: Movie] = [:]
    private var seriesIndex: [Int: Show] = [:]
    private var channelIndex: [Int: Channel] = [:]

    var client: XtreamClient? { credentials.map(XtreamClient.init) }

    init() {
        enginePreference = EnginePreference(rawValue: defaults.string(forKey: "engine") ?? "") ?? .automatic
        autoplayNext = defaults.object(forKey: "autoplayNext") as? Bool ?? true
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        recentChannels = defaults.array(forKey: "recentChannels") as? [Int] ?? []
        if let data = defaults.data(forKey: "progress"), let p = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) {
            progress = p
        }
        credentials = Keychain.load()
        #if DEBUG
        // Dev convenience: SIMCTL_CHILD_LUMEN_SERVER/USER/PASS sign in without typing.
        let env = ProcessInfo.processInfo.environment
        if credentials == nil, let s = env["LUMEN_SERVER"], let u = env["LUMEN_USER"], let p = env["LUMEN_PASS"] {
            Task { try? await signIn(server: s, username: u, password: p) }
            return
        }
        #endif
        if credentials != nil { Task { await bootstrap() } }
    }

    // MARK: - Session

    func signIn(server: String, username: String, password: String) async throws {
        let creds = Credentials(server: Credentials.normalize(server), username: username.trimmingCharacters(in: .whitespaces), password: password.trimmingCharacters(in: .whitespaces))
        let info = try await XtreamClient(creds: creds).authenticate()
        Keychain.save(creds)
        credentials = creds
        account = info
        await bootstrap()
    }

    func signOut() {
        if let c = credentials { try? FileManager.default.removeItem(at: cacheDirectory(c)) }
        Keychain.save(nil)
        credentials = nil
        account = nil
        phase = .idle
        liveCategories = []; channels = []; movieCategories = []; movies = []; seriesCategories = []; series = []
        index()
    }

    func bootstrap() async {
        guard let creds = credentials else { return }
        if account == nil { Task { account = try? await XtreamClient(creds: creds).authenticate() } }

        let cached = await Task.detached(priority: .userInitiated) { Self.loadCatalog(from: Self.cacheDirectory(creds)) }.value
        if let cached {
            apply(cached)
            phase = .ready
            let age = Date().timeIntervalSince(cached.date)
            if age > 60 * 60 * 6 { Task { await refresh() } }
        } else {
            phase = .loading
            await refresh()
        }
    }

    func refresh() async {
        guard let creds = credentials, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if phase != .ready { phase = .loading }
        do {
            let client = XtreamClient(creds: creds)
            var raws: [Action: Data] = [:]
            try await withThrowingTaskGroup(of: (Action, Data).self) { group in
                for action in Action.allCases { group.addTask { (action, try await client.raw(action)) } }
                for try await (a, d) in group { raws[a] = d }
            }
            let dir = cacheDirectory(creds)
            let catalog = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                for (a, d) in raws { try d.write(to: dir.appendingPathComponent(a.rawValue + ".json")) }
                guard let c = Self.loadCatalog(from: dir) else { throw XtreamError.empty }
                return c
            }.value
            apply(catalog)
            phase = .ready
        } catch {
            if phase != .ready { phase = .failed(error.localizedDescription) }
        }
    }

    private struct Catalog: Sendable {
        var date: Date
        var liveCategories: [Category], channels: [Channel]
        var movieCategories: [Category], movies: [Movie]
        var seriesCategories: [Category], series: [Show]
    }

    nonisolated private static func cacheDirectory(_ c: Credentials) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("catalog/\(c.cacheKey)")
    }
    private func cacheDirectory(_ c: Credentials) -> URL { Self.cacheDirectory(c) }

    nonisolated private static func loadCatalog(from dir: URL) -> Catalog? {
        let dec = JSONDecoder()
        func load<T: Decodable>(_ a: Action, _ t: T.Type) -> [T]? {
            guard let d = try? Data(contentsOf: dir.appendingPathComponent(a.rawValue + ".json")) else { return nil }
            return (try? dec.decode(Lossy<T>.self, from: d))?.items
        }
        guard let movies = load(.movies, Movie.self), let channels = load(.live, Channel.self), let series = load(.series, Show.self) else { return nil }
        let date = (try? dir.appendingPathComponent(Action.movies.rawValue + ".json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return Catalog(date: date,
                       liveCategories: load(.liveCategories, Category.self) ?? [], channels: channels,
                       movieCategories: load(.movieCategories, Category.self) ?? [], movies: movies,
                       seriesCategories: load(.seriesCategories, Category.self) ?? [], series: series)
    }

    private func apply(_ c: Catalog) {
        channels = c.channels
        movies = c.movies
        series = c.series
        // Keep only categories that actually contain something, in the provider's order.
        channelsByCategory = Dictionary(grouping: channels) { $0.categoryID ?? "" }
        moviesByCategory = Dictionary(grouping: movies) { $0.categoryID ?? "" }
        seriesByCategory = Dictionary(grouping: series) { $0.categoryID ?? "" }
        liveCategories = c.liveCategories.filter { channelsByCategory[$0.id] != nil }
        movieCategories = c.movieCategories.filter { moviesByCategory[$0.id] != nil }
        seriesCategories = c.seriesCategories.filter { seriesByCategory[$0.id] != nil }
        recentMovies = Array(movies.sorted { $0.added > $1.added }.prefix(40))
        recentSeries = Array(series.sorted { $0.modified > $1.modified }.prefix(40))
        index()
        let scale = UIScreen.main.scale
        Task {
            await ImagePipeline.shared.prefetch(featured.compactMap(\.backdrop), maxPixel: 1400)
            await ImagePipeline.shared.prefetch(recentMovies.prefix(12).compactMap(\.poster), maxPixel: 118 * scale)
            await ImagePipeline.shared.prefetch(recentSeries.prefix(12).compactMap(\.cover), maxPixel: 118 * scale)
        }
    }

    private func index() {
        movieIndex = Dictionary(movies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        seriesIndex = Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        channelIndex = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func movie(_ id: Int) -> Movie? { movieIndex[id] }
    func show(_ id: Int) -> Show? { seriesIndex[id] }
    func channel(_ id: Int) -> Channel? { channelIndex[id] }

    var featured: [Show] { Array(recentSeries.filter { $0.backdrop != nil && $0.plot != nil }.prefix(8)) }

    // MARK: - Favorites

    func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    func toggleFavorite(_ key: String) {
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        defaults.set(Array(favorites), forKey: "favorites")
    }

    var favoriteChannels: [Channel] { channels.filter { favorites.contains("live:\($0.id)") } }
    var favoriteMovies: [Movie] { movies.filter { favorites.contains("movie:\($0.id)") } }
    var favoriteSeries: [Show] { series.filter { favorites.contains("series:\($0.id)") } }
    var recentChannelList: [Channel] { recentChannels.compactMap { channelIndex[$0] } }

    // MARK: - Progress

    var continueWatching: [PlaybackProgress] {
        var seenSeries = Set<Int>()
        return progress.values
            .filter { !$0.isFinished && $0.position > 30 }
            .sorted { $0.updated > $1.updated }
            .filter { p in
                guard case .episode(_, _, let sid, _, _) = p.item.ref else { return true }
                return seenSeries.insert(sid).inserted
            }
    }

    func saveProgress(_ item: PlayableItem, position: Double, duration: Double) {
        guard !item.ref.isLive, duration > 0, position.isFinite else { return }
        progress[item.id] = PlaybackProgress(item: item, position: position, duration: duration, updated: .now)
        persistProgress()
    }

    func clearProgress(_ key: String) {
        progress[key] = nil
        persistProgress()
    }

    private func persistProgress() {
        if let d = try? JSONEncoder().encode(progress) { defaults.set(d, forKey: "progress") }
    }

    // MARK: - Playback

    func url(for ref: MediaRef, preferTS: Bool = false) -> URL? {
        guard let client else { return nil }
        switch ref {
        case .live(let id): return client.liveURL(id, ext: preferTS ? "ts" : "m3u8")
        case .movie(let id, let ext): return client.movieURL(id, ext: ext)
        case .episode(let id, let ext, _, _, _): return client.episodeURL(id, ext: ext)
        }
    }

    func play(_ queue: [PlayableItem], at index: Int = 0) {
        guard queue.indices.contains(index) else { return }
        if case .live(let id) = queue[index].ref { noteChannel(id) }
        session = PlaybackSession(queue: queue, index: index)
    }

    func noteChannel(_ id: Int) {
        recentChannels.removeAll { $0 == id }
        recentChannels.insert(id, at: 0)
        recentChannels = Array(recentChannels.prefix(20))
        defaults.set(recentChannels, forKey: "recentChannels")
    }

    func playable(_ c: Channel) -> PlayableItem {
        PlayableItem(ref: .live(c.id), title: c.name, subtitle: liveCategories.first { $0.id == c.categoryID }?.name, artwork: c.logo)
    }

    func playable(_ m: Movie, details: MovieDetails? = nil) -> PlayableItem {
        PlayableItem(ref: .movie(m.id, ext: details?.ext ?? m.ext), title: m.title, subtitle: m.year.map(String.init), artwork: m.poster, backdrop: details?.backdrop)
    }

    func playable(_ e: Episode, of show: Show) -> PlayableItem {
        PlayableItem(ref: .episode(e.id, ext: e.ext, seriesID: show.id, season: e.season, number: e.number),
                     title: show.title, subtitle: "T\(e.season):E\(e.number) · \(e.title)", artwork: e.still ?? show.cover, backdrop: show.backdrop)
    }
}
