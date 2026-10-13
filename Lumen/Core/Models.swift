import Foundation

// MARK: - Lenient decoding helpers (Xtream panels mix strings, ints and nulls freely)

extension KeyedDecodingContainer {
    func string(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func int(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = string(key) { return Int(s) ?? Double(s).map { Int($0) } }
        return nil
    }

    func double(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = string(key) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    func strings(_ key: Key) -> [String] {
        if let a = try? decodeIfPresent([String?].self, forKey: key) { return a.compactMap { $0 }.filter { !$0.isEmpty } }
        if let s = string(key) { return [s] }
        return []
    }
}

/// Decodes an array, silently dropping elements that fail to decode.
struct Lossy<T: Decodable>: Decodable {
    let items: [T]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        out.reserveCapacity(c.count ?? 0)
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { out.append(v) } else { _ = try? c.decode(Skip.self) }
        }
        items = out
    }
    private struct Skip: Decodable {}
}

private func url(_ s: String?) -> URL? {
    guard let s, !s.isEmpty else { return nil }
    return URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["%"])) ?? s)
}

extension String {
    /// Lowercased, accent-free key used for search.
    var searchKey: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "pt_BR")) }

    /// "Filme (2021)" → 2021
    var trailingYear: Int? {
        guard let r = range(of: #"\((19|20)\d{2}\)"#, options: .regularExpression) else { return nil }
        return Int(self[r].dropFirst().dropLast())
    }

    /// Strips a trailing "(2021)" from a title.
    var withoutYear: String {
        replacingOccurrences(of: #"\s*\((19|20)\d{2}\)\s*$"#, with: "", options: .regularExpression)
    }
}

// MARK: - Catalog

struct Category: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let name: String

    init(id: String, name: String) { self.id = id; self.name = name }

    enum K: String, CodingKey { case category_id, category_name }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        guard let id = c.string(.category_id) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no id")) }
        self.id = id
        name = c.string(.category_name) ?? "Sem nome"
    }
}

struct Channel: Identifiable, Hashable, Decodable, Sendable {
    let id: Int
    let num: Int
    let name: String
    let logo: URL?
    let categoryID: String?
    let epgID: String?
    let hasArchive: Bool
    let searchKey: String

    enum K: String, CodingKey { case stream_id, num, name, stream_icon, category_id, epg_channel_id, tv_archive }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        guard let id = c.int(.stream_id) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no id")) }
        self.id = id
        num = c.int(.num) ?? 0
        name = c.string(.name) ?? "Canal \(id)"
        logo = url(c.string(.stream_icon))
        categoryID = c.string(.category_id)
        epgID = c.string(.epg_channel_id)
        hasArchive = (c.int(.tv_archive) ?? 0) == 1
        searchKey = name.searchKey
    }
}

struct Movie: Identifiable, Hashable, Decodable, Sendable {
    let id: Int
    let name: String
    let poster: URL?
    let rating: Double?
    let categoryID: String?
    let ext: String
    let added: Int
    let plot: String?
    let genre: String?
    let cast: String?
    let director: String?
    let year: Int?
    let trailer: String?
    let searchKey: String

    var title: String { name.withoutYear }

    enum K: String, CodingKey { case stream_id, name, title, stream_icon, rating, category_id, container_extension, added, plot, genre, cast, director, year, release_date, youtube_trailer }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        guard let id = c.int(.stream_id) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no id")) }
        self.id = id
        name = c.string(.name) ?? c.string(.title) ?? "Filme \(id)"
        poster = url(c.string(.stream_icon))
        let r = c.double(.rating)
        rating = (r ?? 0) > 0 ? r : nil
        categoryID = c.string(.category_id)
        ext = c.string(.container_extension) ?? "mp4"
        added = c.int(.added) ?? 0
        plot = c.string(.plot)
        genre = c.string(.genre)
        cast = c.string(.cast)
        director = c.string(.director)
        year = c.int(.year) ?? c.string(.release_date).flatMap { Int($0.prefix(4)) } ?? name.trailingYear
        trailer = c.string(.youtube_trailer)
        searchKey = name.searchKey
    }
}

struct Show: Identifiable, Hashable, Decodable, Sendable {
    let id: Int
    let name: String
    let cover: URL?
    let backdrop: URL?
    let plot: String?
    let genre: String?
    let cast: String?
    let director: String?
    let rating: Double?
    let categoryID: String?
    let modified: Int
    let year: Int?
    let trailer: String?
    let searchKey: String

    var title: String { name.withoutYear }

    enum K: String, CodingKey { case series_id, name, title, cover, backdrop_path, plot, genre, cast, director, rating, category_id, last_modified, releaseDate, release_date, year, youtube_trailer }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        guard let id = c.int(.series_id) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no id")) }
        self.id = id
        name = c.string(.name) ?? c.string(.title) ?? "Série \(id)"
        cover = url(c.string(.cover))
        backdrop = url(c.strings(.backdrop_path).first)
        plot = c.string(.plot)
        genre = c.string(.genre)
        cast = c.string(.cast)
        director = c.string(.director)
        let r = c.double(.rating)
        rating = (r ?? 0) > 0 ? r : nil
        categoryID = c.string(.category_id)
        modified = c.int(.last_modified) ?? 0
        year = c.int(.year) ?? (c.string(.releaseDate) ?? c.string(.release_date)).flatMap { Int($0.prefix(4)) } ?? name.trailingYear
        trailer = c.string(.youtube_trailer)
        searchKey = name.searchKey
    }
}

// MARK: - Details

struct MovieDetails: Decodable, Sendable {
    var backdrop: URL?
    var poster: URL?
    var plot: String?
    var cast: String?
    var director: String?
    var genre: String?
    var country: String?
    var duration: Int?
    var rating: Double?
    var releaseDate: String?
    var trailer: String?
    var ext: String?

    enum Root: String, CodingKey { case info, movie_data }
    enum Info: String, CodingKey { case backdrop_path, movie_image, cover_big, plot, description, cast, actors, director, genre, country, duration_secs, rating, releasedate, release_date, youtube_trailer }
    enum MD: String, CodingKey { case container_extension }

    init(from d: Decoder) throws {
        let root = try d.container(keyedBy: Root.self)
        if let i = try? root.nestedContainer(keyedBy: Info.self, forKey: .info) {
            backdrop = url(i.strings(.backdrop_path).first)
            poster = url(i.string(.cover_big) ?? i.string(.movie_image))
            plot = i.string(.plot) ?? i.string(.description)
            cast = i.string(.cast) ?? i.string(.actors)
            director = i.string(.director)
            genre = i.string(.genre)
            country = i.string(.country)
            duration = i.int(.duration_secs)
            rating = i.double(.rating)
            releaseDate = i.string(.releasedate) ?? i.string(.release_date)
            trailer = i.string(.youtube_trailer)
        }
        if let m = try? root.nestedContainer(keyedBy: MD.self, forKey: .movie_data) {
            ext = m.string(.container_extension)
        }
    }
}

struct Season: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let cover: URL?
    let overview: String?
}

struct Episode: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let number: Int
    let season: Int
    let title: String
    let ext: String
    let still: URL?
    let plot: String?
    let duration: Int?

    enum K: String, CodingKey { case id, episode_num, season, title, container_extension, info }
    enum I: String, CodingKey { case movie_image, plot, duration_secs }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        guard let id = c.string(.id) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "no id")) }
        self.id = id
        number = c.int(.episode_num) ?? 0
        season = c.int(.season) ?? 1
        ext = c.string(.container_extension) ?? "mp4"
        let info = try? c.nestedContainer(keyedBy: I.self, forKey: .info)
        still = url(info?.string(.movie_image))
        plot = info?.string(.plot)
        duration = info?.int(.duration_secs)
        // Panels usually prefix titles with "Show - S01E01 - "; keep only the episode name.
        let raw = c.string(.title) ?? "Episódio \(number)"
        if let r = raw.range(of: #"S\d+E\d+\s*-\s*"#, options: .regularExpression) {
            let rest = raw[r.upperBound...].trimmingCharacters(in: .whitespaces)
            title = rest.isEmpty ? "Episódio \(number)" : rest
        } else {
            title = raw
        }
    }
}

struct SeriesDetails: Decodable, Sendable {
    var seasons: [Season] = []
    var episodes: [Int: [Episode]] = [:]
    var backdrop: URL?
    var plot: String?

    enum Root: String, CodingKey { case seasons, episodes, info }
    enum S: String, CodingKey { case season_number, name, cover, cover_big, overview }
    enum Info: String, CodingKey { case backdrop_path, plot }

    init(from d: Decoder) throws {
        let root = try d.container(keyedBy: Root.self)
        var eps: [Episode] = []
        if let dict = try? root.decode([String: Lossy<Episode>].self, forKey: .episodes) {
            eps = dict.values.flatMap(\.items)
        } else if let arr = try? root.decode([Lossy<Episode>].self, forKey: .episodes) {
            eps = arr.flatMap(\.items)
        }
        episodes = Dictionary(grouping: eps, by: \.season).mapValues { $0.sorted { $0.number < $1.number } }

        var meta: [Int: Season] = [:]
        if var arr = try? root.nestedUnkeyedContainer(forKey: .seasons) {
            while !arr.isAtEnd {
                guard let s = try? arr.nestedContainer(keyedBy: S.self) else { break }
                if let n = s.int(.season_number) {
                    meta[n] = Season(id: n, name: s.string(.name) ?? "Temporada \(n)", cover: url(s.string(.cover_big) ?? s.string(.cover)), overview: s.string(.overview))
                }
            }
        }
        seasons = episodes.keys.sorted().map { n in
            let m = meta[n]
            let name = (m?.name).flatMap { $0.lowercased().hasPrefix("season") ? nil : $0 } ?? "Temporada \(n)"
            return Season(id: n, name: name, cover: m?.cover, overview: m?.overview)
        }
        if let i = try? root.nestedContainer(keyedBy: Info.self, forKey: .info) {
            backdrop = url(i.strings(.backdrop_path).first)
            plot = i.string(.plot)
        }
    }
}

// MARK: - Account

struct AccountInfo: Decodable, Sendable {
    let status: String
    let expires: Date?
    let maxConnections: Int?
    let activeConnections: Int?
    let isTrial: Bool
    let timezone: String?

    enum Root: String, CodingKey { case user_info, server_info }
    enum U: String, CodingKey { case auth, status, exp_date, max_connections, active_cons, is_trial }
    enum S: String, CodingKey { case timezone }

    init(from d: Decoder) throws {
        let root = try d.container(keyedBy: Root.self)
        let u = try root.nestedContainer(keyedBy: U.self, forKey: .user_info)
        guard (u.int(.auth) ?? 0) == 1 else { throw XtreamError.unauthorized }
        status = u.string(.status) ?? "Active"
        expires = u.double(.exp_date).map { Date(timeIntervalSince1970: $0) }
        maxConnections = u.int(.max_connections)
        activeConnections = u.int(.active_cons)
        isTrial = (u.int(.is_trial) ?? 0) == 1
        timezone = (try? root.nestedContainer(keyedBy: S.self, forKey: .server_info))?.string(.timezone)
    }
}

struct EPGEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date

    func progress(at now: Date = .now) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }
}

struct EPGResponse: Decodable {
    let entries: [EPGEntry]
    enum Root: String, CodingKey { case epg_listings }
    enum E: String, CodingKey { case id, title, start_timestamp, stop_timestamp }
    init(from d: Decoder) throws {
        let root = try d.container(keyedBy: Root.self)
        var out: [EPGEntry] = []
        if var arr = try? root.nestedUnkeyedContainer(forKey: .epg_listings) {
            while !arr.isAtEnd {
                guard let e = try? arr.nestedContainer(keyedBy: E.self) else { break }
                guard let start = e.double(.start_timestamp), let stop = e.double(.stop_timestamp) else { continue }
                let raw = e.string(.title) ?? ""
                let title = Data(base64Encoded: raw).flatMap { String(data: $0, encoding: .utf8) } ?? raw
                out.append(EPGEntry(id: e.string(.id) ?? UUID().uuidString, title: title, start: .init(timeIntervalSince1970: start), end: .init(timeIntervalSince1970: stop)))
            }
        }
        entries = out
    }
}
