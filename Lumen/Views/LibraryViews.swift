import SwiftUI

// MARK: - Movies

struct MoviesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    Shelf(title: "Adicionados recentemente", items: app.recentMovies) {
                        MediaGridScreen(title: "Adicionados recentemente", movies: app.recentMovies)
                    } card: { movieCard($0, width: 140) }

                    ForEach(app.movieCategories) { cat in
                        let items = app.moviesByCategory[cat.id] ?? []
                        Shelf(title: cat.name.capitalized, items: Array(items.prefix(20))) {
                            MediaGridScreen(title: cat.name.capitalized, movies: items)
                        } card: { movieCard($0) }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Filmes")
            .refreshable { await app.refresh() }
            .withMediaDestinations()
        }
    }

    private func movieCard(_ m: Movie, width: CGFloat = 118) -> some View {
        NavigationLink(value: m) {
            PosterCard(title: m.title, image: m.poster, width: width, rating: m.rating, progress: app.progress["movie:\(m.id)"]?.fraction)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Series

struct SeriesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    Shelf(title: "Atualizadas recentemente", items: app.recentSeries) {
                        MediaGridScreen(title: "Atualizadas recentemente", shows: app.recentSeries)
                    } card: { showCard($0, width: 140) }

                    ForEach(app.seriesCategories) { cat in
                        let items = app.seriesByCategory[cat.id] ?? []
                        Shelf(title: cat.name.capitalized, items: Array(items.prefix(20))) {
                            MediaGridScreen(title: cat.name.capitalized, shows: items)
                        } card: { showCard($0) }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Séries")
            .refreshable { await app.refresh() }
            .withMediaDestinations()
        }
    }

    private func showCard(_ s: Show, width: CGFloat = 118) -> some View {
        NavigationLink(value: s) { PosterCard(title: s.title, image: s.cover, width: width, rating: s.rating) }
            .buttonStyle(PressableStyle())
    }
}

// MARK: - Full grid

struct MediaGridScreen: View {
    let title: String
    var movies: [Movie] = []
    var shows: [Show] = []
    @State private var sort = Sort.default
    @State private var query = ""

    enum Sort: String, CaseIterable { case `default` = "Padrão", recent = "Mais recentes", rating = "Melhor avaliados", name = "A–Z" }

    var body: some View {
        ScrollView {
            if !movies.isEmpty {
                PosterGrid(items: sorted(movies, added: \.added)) { m in
                    NavigationLink(value: m) { PosterCard(title: m.title, image: m.poster, width: 110, rating: m.rating) }
                        .buttonStyle(PressableStyle())
                }
            } else {
                PosterGrid(items: sorted(shows, added: \.modified)) { s in
                    NavigationLink(value: s) { PosterCard(title: s.title, image: s.cover, width: 110, rating: s.rating) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
        .contentMargins(.vertical, 12)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Filtrar")
        .toolbar {
            Menu {
                Picker("Ordenar", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
        }
    }

    private func sorted<T: Identifiable>(_ items: [T], added: KeyPath<T, Int>) -> [T] where T: Searchable {
        let filtered = query.isEmpty ? items : items.filter { $0.searchKey.contains(query.searchKey) }
        switch sort {
        case .default: return filtered
        case .recent: return filtered.sorted { $0[keyPath: added] > $1[keyPath: added] }
        case .rating: return filtered.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        case .name: return filtered.sorted { $0.searchKey < $1.searchKey }
        }
    }
}

protocol Searchable {
    var searchKey: String { get }
    var score: Double? { get }
}
extension Movie: Searchable { var score: Double? { rating } }
extension Show: Searchable { var score: Double? { rating } }

extension View {
    func withMediaDestinations() -> some View {
        navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
            .navigationDestination(for: Show.self) { SeriesDetailView(show: $0) }
    }
}

// MARK: - Search

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var results = Results()

    struct Results { var channels: [Channel] = []; var movies: [Movie] = []; var shows: [Show] = [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.isEmpty {
                    ContentUnavailableView("Busque em tudo", systemImage: "magnifyingglass", description: Text("Canais, filmes e séries em um só lugar."))
                        .padding(.top, 80)
                } else if results.channels.isEmpty && results.movies.isEmpty && results.shows.isEmpty {
                    ContentUnavailableView.search(text: query).padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !results.channels.isEmpty {
                            Shelf(title: "Canais", items: results.channels) { c in
                                Button { app.play(results.channels.map(app.playable), at: results.channels.firstIndex(of: c) ?? 0) } label: {
                                    VStack(spacing: 8) {
                                        ChannelLogo(url: c.logo, name: c.name, size: 84)
                                        Text(c.name).font(.caption.weight(.medium)).lineLimit(1).frame(width: 84)
                                    }
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                        if !results.movies.isEmpty {
                            Shelf(title: "Filmes", items: results.movies) { m in
                                NavigationLink(value: m) { PosterCard(title: m.title, image: m.poster, rating: m.rating) }.buttonStyle(PressableStyle())
                            }
                        }
                        if !results.shows.isEmpty {
                            Shelf(title: "Séries", items: results.shows) { s in
                                NavigationLink(value: s) { PosterCard(title: s.title, image: s.cover, rating: s.rating) }.buttonStyle(PressableStyle())
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Buscar")
            .searchable(text: $query, prompt: "Filmes, séries e canais")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                let q = query.searchKey
                guard q.count >= 2 else { results = Results(); return }
                let (c, m, s) = (app.channels, app.movies, app.series)
                results = await Task.detached(priority: .userInitiated) {
                    Results(channels: Array(c.filter { $0.searchKey.contains(q) }.prefix(30)),
                            movies: Array(m.filter { $0.searchKey.contains(q) }.prefix(40)),
                            shows: Array(s.filter { $0.searchKey.contains(q) }.prefix(40)))
                }.value
            }
            .withMediaDestinations()
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        BrandMark(size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.credentials?.username ?? "—").font(.headline)
                            Text(app.credentials.flatMap { URL(string: $0.server)?.host() } ?? "").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    if let acc = app.account {
                        LabeledContent("Status", value: acc.status == "Active" ? "Ativa" : acc.status)
                        if let exp = acc.expires {
                            LabeledContent("Expira em", value: exp.formatted(date: .long, time: .omitted))
                        }
                        if let max = acc.maxConnections {
                            LabeledContent("Telas simultâneas", value: "\(acc.activeConnections ?? 0) de \(max)")
                        }
                    }
                }

                Section("Biblioteca") {
                    LabeledContent("Canais", value: app.channels.count.formatted())
                    LabeledContent("Filmes", value: app.movies.count.formatted())
                    LabeledContent("Séries", value: app.series.count.formatted())
                    Button {
                        Task { await app.refresh() }
                    } label: {
                        HStack {
                            Text("Atualizar agora")
                            Spacer()
                            if app.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(app.isRefreshing)
                }

                Section {
                    Picker("Player", selection: $app.enginePreference) {
                        ForEach(EnginePreference.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Reproduzir próximo episódio", isOn: $app.autoplayNext)
                } header: {
                    Text("Reprodução")
                } footer: {
                    Text("No modo automático, o Lumen usa o player nativo da Apple (PiP, AirPlay, menor consumo de bateria) e troca para o VLC sozinho quando o formato não é suportado.")
                }

                Section {
                    Button("Sair da conta", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("OK") { dismiss() }.fontWeight(.semibold) }
            .confirmationDialog("Sair da conta?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sair", role: .destructive) { dismiss(); app.signOut() }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
