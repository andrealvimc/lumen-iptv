import SwiftUI
import ImageIO

/// Memory + disk cached image loader that downsamples to the size actually displayed.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 600 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 8
        config.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: config)
    }()
    /// Hosts that time out on this network (some Brazilian ISPs/carriers block TMDB); served via proxy instead.
    private var blockedHosts: Set<String> = []

    init() { memory.totalCostLimit = 120 << 20 }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(url.absoluteString)#\(Int(maxPixel))"
        if let img = memory.object(forKey: key as NSString) { return img }
        if let task = inflight[key] { return await task.value }
        let remote = Self.optimized(url, maxPixel: maxPixel)
        let host = remote.host() ?? ""
        let viaProxy = blockedHosts.contains(host)
        // Detached so network + decode run in parallel instead of serialising on this actor.
        let task = Task.detached(priority: .userInitiated) { [session] () -> UIImage? in
            if !viaProxy {
                do {
                    let (data, _) = try await session.data(from: remote)
                    return Self.downsample(data, maxPixel: maxPixel)
                } catch let error as URLError where Self.isUnreachable(error) {
                    await ImagePipeline.shared.markBlocked(host)
                } catch {
                    return nil
                }
            }
            guard let proxied = Self.proxy(remote, maxPixel: maxPixel),
                  let (data, _) = try? await session.data(from: proxied) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        inflight[key] = task
        let img = await task.value
        inflight[key] = nil
        if let img { memory.setObject(img, forKey: key as NSString, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4)) }
        return img
    }

    nonisolated func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        memory.object(forKey: "\(url.absoluteString)#\(Int(maxPixel))" as NSString)
    }

    /// TMDB serves every size; ask for the smallest one that still looks sharp, over HTTPS/2.
    nonisolated private static func optimized(_ url: URL, maxPixel: CGFloat) -> URL {
        guard url.host()?.contains("tmdb.org") == true else { return url }
        var s = url.absoluteString.replacingOccurrences(of: "http://", with: "https://")
        let size = maxPixel <= 200 ? "w185" : maxPixel <= 400 ? "w342" : maxPixel <= 800 ? "w780" : "w1280"
        if let r = s.range(of: #"/t/p/[^/]+/"#, options: .regularExpression) { s.replaceSubrange(r, with: "/t/p/\(size)/") }
        return URL(string: s) ?? url
    }

    private func markBlocked(_ host: String) { blockedHosts.insert(host) }

    nonisolated private static func isUnreachable(_ e: URLError) -> Bool {
        [.timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .secureConnectionFailed, .dnsLookupFailed].contains(e.code)
    }

    /// wsrv.nl fetches and resizes the image from its own network.
    nonisolated private static func proxy(_ url: URL, maxPixel: CGFloat) -> URL? {
        var c = URLComponents(string: "https://wsrv.nl/")
        c?.queryItems = [.init(name: "url", value: url.absoluteString), .init(name: "w", value: "\(Int(maxPixel))"), .init(name: "we", value: "1")]
        return c?.url
    }

    func prefetch(_ urls: [URL], maxPixel: CGFloat) {
        for url in urls.prefix(40) { Task { _ = await image(for: url, maxPixel: maxPixel) } }
    }

    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var maxPixel: CGFloat = 600
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
            let loaded = await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

extension RemoteImage where Placeholder == Color {
    init(url: URL?, maxPixel: CGFloat = 600, contentMode: ContentMode = .fill) {
        self.init(url: url, maxPixel: maxPixel, contentMode: contentMode) { Color(white: 0.12) }
    }
}
