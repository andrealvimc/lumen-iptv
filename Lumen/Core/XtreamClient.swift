import Foundation
import Security

enum XtreamError: LocalizedError {
    case invalidServer, unauthorized, http(Int), empty

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Endereço do servidor inválido."
        case .unauthorized: "Usuário ou senha incorretos, ou assinatura expirada."
        case .http(let code): "O servidor respondeu com erro \(code)."
        case .empty: "O servidor não retornou dados."
        }
    }
}

struct Credentials: Codable, Hashable, Sendable {
    var server: String
    var username: String
    var password: String

    /// "example.com:8080/" → "http://example.com:8080"
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        for suffix in ["/player_api.php", "/get.php", "/"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    var cacheKey: String { "\(server)|\(username)".data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_") }
}

enum Action: String, CaseIterable, Sendable {
    case liveCategories = "get_live_categories"
    case live = "get_live_streams"
    case movieCategories = "get_vod_categories"
    case movies = "get_vod_streams"
    case seriesCategories = "get_series_categories"
    case series = "get_series"
}

struct XtreamClient: Sendable {
    let creds: Credentials

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 180
        config.httpAdditionalHeaders = ["User-Agent": "Lumen/1.0 (iPhone; iOS)"]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private func apiURL(_ action: String?, _ extra: [String: String] = [:]) throws -> URL {
        guard var comps = URLComponents(string: creds.server + "/player_api.php") else { throw XtreamError.invalidServer }
        var items = [URLQueryItem(name: "username", value: creds.username), URLQueryItem(name: "password", value: creds.password)]
        if let action { items.append(.init(name: "action", value: action)) }
        items += extra.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        guard let url = comps.url else { throw XtreamError.invalidServer }
        return url
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await Self.session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw http.statusCode == 401 || http.statusCode == 403 ? XtreamError.unauthorized : XtreamError.http(http.statusCode)
        }
        guard !data.isEmpty else { throw XtreamError.empty }
        return data
    }

    func authenticate() async throws -> AccountInfo {
        let data = try await get(try apiURL(nil))
        do { return try JSONDecoder().decode(AccountInfo.self, from: data) }
        catch let e as XtreamError { throw e }
        catch { throw XtreamError.unauthorized }
    }

    func raw(_ action: Action) async throws -> Data { try await get(try apiURL(action.rawValue)) }

    func movieDetails(_ id: Int) async throws -> MovieDetails {
        try JSONDecoder().decode(MovieDetails.self, from: try await get(try apiURL("get_vod_info", ["vod_id": "\(id)"])))
    }

    func seriesDetails(_ id: Int) async throws -> SeriesDetails {
        try JSONDecoder().decode(SeriesDetails.self, from: try await get(try apiURL("get_series_info", ["series_id": "\(id)"])))
    }

    func shortEPG(_ streamID: Int) async throws -> [EPGEntry] {
        try JSONDecoder().decode(EPGResponse.self, from: try await get(try apiURL("get_short_epg", ["stream_id": "\(streamID)", "limit": "4"]))).entries
    }

    // MARK: Stream URLs

    private func stream(_ kind: String, _ id: String, _ ext: String) -> URL {
        URL(string: "\(creds.server)/\(kind)/\(creds.username)/\(creds.password)/\(id).\(ext)")!
    }
    func liveURL(_ id: Int, ext: String = "m3u8") -> URL { stream("live", "\(id)", ext) }
    func movieURL(_ id: Int, ext: String) -> URL { stream("movie", "\(id)", ext) }
    func episodeURL(_ id: String, ext: String) -> URL { stream("series", id, ext) }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.andrealvim.lumen"
    private static let account = "credentials"

    static func save(_ creds: Credentials?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let creds, let data = try? JSONEncoder().encode(creds) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }
}
