import SwiftUI

struct LiveView: View {
    @Environment(AppModel.self) private var app
    @State private var selection = "all"
    @State private var query = ""

    private var chips: [ChipBar.Chip] {
        var c: [ChipBar.Chip] = [.init(id: "all", title: "Todos")]
        if !app.favoriteChannels.isEmpty { c.append(.init(id: "fav", title: "Favoritos", symbol: "star.fill")) }
        if !app.recentChannels.isEmpty { c.append(.init(id: "recent", title: "Recentes", symbol: "clock")) }
        return c + app.liveCategories.map { .init(id: $0.id, title: $0.name.capitalized) }
    }

    private var channels: [Channel] {
        let base: [Channel] = switch selection {
        case "all": app.channels
        case "fav": app.favoriteChannels
        case "recent": app.recentChannelList
        default: app.channelsByCategory[selection] ?? []
        }
        guard !query.isEmpty else { return base }
        let q = query.searchKey
        return base.filter { $0.searchKey.contains(q) }
    }

    var body: some View {
        NavigationStack {
            let list = channels
            List {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, channel in
                    Button { app.play(list.map(app.playable), at: i) } label: {
                        ChannelRow(channel: channel, category: categoryName(channel))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.08))
                    .swipeActions(edge: .trailing) { favoriteButton(channel) }
                    .contextMenu { favoriteButton(channel) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Nenhum canal aqui" : "Nada encontrado", systemImage: "tv.slash")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ChipBar(chips: chips, selection: $selection)
                    .background(.bar)
            }
            .navigationTitle("Ao Vivo")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar canal")
            .refreshable { await app.refresh() }
        }
    }

    private func categoryName(_ c: Channel) -> String? {
        guard selection == "all" || selection == "fav" || selection == "recent" else { return nil }
        return app.liveCategories.first { $0.id == c.categoryID }?.name.capitalized
    }

    @ViewBuilder
    private func favoriteButton(_ c: Channel) -> some View {
        let fav = app.isFavorite("live:\(c.id)")
        Button { app.toggleFavorite("live:\(c.id)") } label: {
            Label(fav ? "Remover favorito" : "Favoritar", systemImage: fav ? "star.slash" : "star.fill")
        }
        .tint(.yellow)
    }
}

struct ChannelRow: View {
    @Environment(AppModel.self) private var app
    let channel: Channel
    let category: String?
    @State private var now: EPGEntry?

    var body: some View {
        HStack(spacing: 14) {
            ChannelLogo(url: channel.logo, name: channel.name, size: 58)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if app.isFavorite("live:\(channel.id)") {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                if let now {
                    Text(now.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    ProgressBar(value: now.progress()).frame(width: 120)
                } else if let category {
                    Text(category).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .task(id: channel.id) {
            guard channel.epgID != nil, let client = app.client else { return }
            now = await EPGCache.shared.current(for: channel.id, client: client)
        }
    }
}

actor EPGCache {
    static let shared = EPGCache()
    private var store: [Int: [EPGEntry]] = [:]

    func current(for id: Int, client: XtreamClient) async -> EPGEntry? {
        if store[id] == nil {
            store[id] = (try? await client.shortEPG(id)) ?? []
        }
        let now = Date()
        return store[id]?.first { $0.start <= now && $0.end > now }
    }
}
