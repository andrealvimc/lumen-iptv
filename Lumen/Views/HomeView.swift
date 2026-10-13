import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    if !app.featured.isEmpty { HeroCarousel(shows: app.featured) }

                    if !app.continueWatching.isEmpty {
                        Shelf(title: "Continuar assistindo", items: app.continueWatching.map(ProgressRow.init)) { row in
                            ContinueCard(progress: row.progress)
                        }
                    }

                    if !app.recentChannelList.isEmpty || !app.favoriteChannels.isEmpty {
                        let chans = app.favoriteChannels.isEmpty ? app.recentChannelList : app.favoriteChannels
                        Shelf(title: app.favoriteChannels.isEmpty ? "Canais recentes" : "Seus canais", items: chans) { c in
                            Button { app.play(chans.map(app.playable), at: chans.firstIndex(of: c) ?? 0) } label: {
                                VStack(spacing: 8) {
                                    ChannelLogo(url: c.logo, name: c.name, size: 84)
                                    Text(c.name).font(.caption.weight(.medium)).lineLimit(1).frame(width: 84)
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }

                    Shelf(title: "Filmes adicionados", items: app.recentMovies) {
                        MediaGridScreen(title: "Filmes adicionados", movies: app.recentMovies)
                    } card: { m in
                        NavigationLink(value: m) { PosterCard(title: m.title, image: m.poster, rating: m.rating) }
                            .buttonStyle(PressableStyle())
                    }

                    Shelf(title: "Séries em destaque", items: app.recentSeries) {
                        MediaGridScreen(title: "Séries em destaque", shows: app.recentSeries)
                    } card: { s in
                        NavigationLink(value: s) { PosterCard(title: s.title, image: s.cover, rating: s.rating) }
                            .buttonStyle(PressableStyle())
                    }

                    if !app.favoriteMovies.isEmpty {
                        Shelf(title: "Minha lista · Filmes", items: app.favoriteMovies) { m in
                            NavigationLink(value: m) { PosterCard(title: m.title, image: m.poster) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                    if !app.favoriteSeries.isEmpty {
                        Shelf(title: "Minha lista · Séries", items: app.favoriteSeries) { s in
                            NavigationLink(value: s) { PosterCard(title: s.title, image: s.cover) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .ignoresSafeArea(edges: app.featured.isEmpty ? [] : .top)
            .refreshable { await app.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .padding(6)
                            .glassCircle()
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .withMediaDestinations()
        }
    }
}

struct ProgressRow: Identifiable {
    let progress: PlaybackProgress
    var id: String { progress.item.id }
}

struct ContinueCard: View {
    @Environment(AppModel.self) private var app
    let progress: PlaybackProgress

    var body: some View {
        Button { app.play([progress.item]) } label: {
            WideCard(title: progress.item.title,
                     subtitle: progress.item.subtitle.map { "\($0) · \(progress.remaining.humanDuration) restantes" } ?? "\(progress.remaining.humanDuration) restantes",
                     image: progress.item.backdrop ?? progress.item.artwork,
                     width: 250,
                     progress: progress.fraction)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(role: .destructive) { app.clearProgress(progress.item.id) } label: {
                Label("Remover de Continuar", systemImage: "xmark.circle")
            }
        }
    }
}

struct HeroCarousel: View {
    @Environment(AppModel.self) private var app
    let shows: [Show]
    @State private var page: Int? = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(shows.enumerated()), id: \.element.id) { i, show in
                        HeroPage(show: show)
                            .frame(width: w)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    ForEach(shows.indices, id: \.self) { i in
                        Capsule()
                            .fill(.white.opacity(i == (page ?? 0) ? 1 : 0.35))
                            .frame(width: i == (page ?? 0) ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(duration: 0.3), value: page)
                .padding(.bottom, 4)
            }
        }
        .frame(height: 560)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                withAnimation(.easeInOut(duration: 0.6)) { page = ((page ?? 0) + 1) % max(shows.count, 1) }
            }
        }
    }
}

struct HeroPage: View {
    @Environment(AppModel.self) private var app
    let show: Show

    var body: some View {
        NavigationLink(value: show) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: show.backdrop ?? show.cover, maxPixel: 1400)
                    .frame(height: 560)
                    .clipped()
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.25),
                            .init(color: .clear, location: 0.45),
                            .init(color: .black.opacity(0.85), location: 0.82),
                            .init(color: .black, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }

                VStack(spacing: 12) {
                    Text(show.title)
                        .font(.system(size: 34, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(radius: 10)
                    MetaLine(parts: [show.year.map(String.init), show.genre?.split(separator: ",").first.map(String.init)].compactMap { $0 }, rating: show.rating)
                    HStack(spacing: 12) {
                        Label("Assistir", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(width: 150, height: 46)
                            .background(.white, in: Capsule())
                        Image(systemName: app.isFavorite("series:\(show.id)") ? "checkmark" : "plus")
                            .font(.headline)
                            .frame(width: 46, height: 46)
                            .glassCircle()
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                app.toggleFavorite("series:\(show.id)")
                            }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .buttonStyle(.plain)
    }
}
