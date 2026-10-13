import SwiftUI

/// Stretchy backdrop header shared by movie and series pages.
struct DetailHeader: View {
    let backdrop: URL?
    let poster: URL?
    let height: CGFloat = 470

    var body: some View {
        GeometryReader { geo in
            let y = geo.frame(in: .scrollView).minY
            RemoteImage(url: backdrop ?? poster, maxPixel: 1400)
                .frame(width: geo.size.width, height: height + max(y, 0))
                .clipped()
                .blur(radius: backdrop == nil ? 18 : 0)
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.7), location: 0.75),
                        .init(color: .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .offset(y: -max(y, 0))
        }
        .frame(height: height)
    }
}

struct PrimaryPlayButton: View {
    let title: String
    var progress: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Label(title, systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                if let progress, progress > 0 {
                    ProgressBar(value: progress)
                        .colorMultiply(.black)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .padding(.top, -8)
                }
            }
            .foregroundStyle(.black)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

struct SquareActionButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(active ? Color.accentColor : .primary)
                Text(label).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(width: 76, height: 58)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Movie

struct MovieDetailView: View {
    @Environment(AppModel.self) private var app
    let movie: Movie
    @State private var details: MovieDetails?
    @State private var showTrailer = false

    private var progress: PlaybackProgress? { app.progress["movie:\(movie.id)"].flatMap { $0.isFinished ? nil : $0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    DetailHeader(backdrop: details?.backdrop, poster: details?.poster ?? movie.poster)
                    VStack(spacing: 10) {
                        Text(movie.title)
                            .font(.system(size: 32, weight: .heavy))
                            .multilineTextAlignment(.center)
                            .shadow(radius: 12)
                        MetaLine(parts: meta, rating: details?.rating ?? movie.rating)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                VStack(alignment: .leading, spacing: 18) {
                    PrimaryPlayButton(title: progress.map { "Continuar · \($0.remaining.humanDuration)" } ?? "Assistir", progress: progress?.fraction) {
                        app.play([app.playable(movie, details: details)])
                    }

                    HStack(spacing: 0) {
                        let fav = app.isFavorite("movie:\(movie.id)")
                        SquareActionButton(symbol: fav ? "checkmark" : "plus", label: "Minha lista", active: fav) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            app.toggleFavorite("movie:\(movie.id)")
                        }
                        if (details?.trailer ?? movie.trailer) != nil {
                            SquareActionButton(symbol: "play.rectangle", label: "Trailer") { showTrailer = true }
                        }
                        if progress != nil {
                            SquareActionButton(symbol: "arrow.counterclockwise", label: "Do início") {
                                app.clearProgress("movie:\(movie.id)")
                                app.play([app.playable(movie, details: details)])
                            }
                        }
                        Spacer()
                    }

                    if let plot = details?.plot ?? movie.plot {
                        Text(plot).font(.body).foregroundStyle(.primary.opacity(0.88))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        credit("Elenco", details?.cast ?? movie.cast)
                        credit("Direção", details?.director ?? movie.director)
                        credit("Gênero", details?.genre ?? movie.genre)
                        credit("País", details?.country)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { details = try? await app.client?.movieDetails(movie.id) }
        .sheet(isPresented: $showTrailer) {
            if let t = details?.trailer ?? movie.trailer { TrailerSheet(youtubeID: t, title: movie.title) }
        }
    }

    private var meta: [String] {
        var parts: [String] = []
        if let y = movie.year { parts.append(String(y)) }
        if let d = details?.duration, d > 0 { parts.append(Double(d).humanDuration) }
        if let g = (details?.genre ?? movie.genre)?.split(separator: ",").first { parts.append(String(g).trimmingCharacters(in: .whitespaces)) }
        if ["mkv", "avi"].contains(movie.ext.lowercased()) { parts.append(movie.ext.uppercased()) }
        return parts
    }

    @ViewBuilder
    private func credit(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            (Text(label + "  ").foregroundStyle(.secondary) + Text(value))
                .font(.subheadline)
                .lineLimit(3)
        }
    }
}

// MARK: - Series

struct SeriesDetailView: View {
    @Environment(AppModel.self) private var app
    let show: Show
    @State private var details: SeriesDetails?
    @State private var season = 1
    @State private var showTrailer = false
    @State private var failed = false

    private var episodes: [Episode] { details?.episodes[season] ?? [] }
    private var allEpisodes: [Episode] { details.map { d in d.seasons.flatMap { d.episodes[$0.id] ?? [] } } ?? [] }

    /// Resume the last-touched episode, or start from the first one.
    private var resumeTarget: (Episode, PlaybackProgress?)? {
        let all = allEpisodes
        let touched = all.compactMap { e in app.progress["episode:\(e.id)"].map { (e, $0) } }.max { $0.1.updated < $1.1.updated }
        if let (e, p) = touched {
            if !p.isFinished { return (e, p) }
            if let i = all.firstIndex(of: e), i + 1 < all.count { return (all[i + 1], nil) }
        }
        return all.first.map { ($0, nil) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottom) {
                    DetailHeader(backdrop: details?.backdrop ?? show.backdrop, poster: show.cover)
                    VStack(spacing: 10) {
                        Text(show.title)
                            .font(.system(size: 32, weight: .heavy))
                            .multilineTextAlignment(.center)
                            .shadow(radius: 12)
                        MetaLine(parts: meta, rating: show.rating)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                VStack(alignment: .leading, spacing: 18) {
                    if let (ep, p) = resumeTarget {
                        PrimaryPlayButton(title: p != nil ? "Continuar T\(ep.season):E\(ep.number)" : (ep == allEpisodes.first ? "Assistir T\(ep.season):E\(ep.number)" : "Próximo: T\(ep.season):E\(ep.number)"), progress: p?.fraction) {
                            play(ep)
                        }
                    } else if details == nil && !failed {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    }

                    HStack(spacing: 0) {
                        let fav = app.isFavorite("series:\(show.id)")
                        SquareActionButton(symbol: fav ? "checkmark" : "plus", label: "Minha lista", active: fav) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            app.toggleFavorite("series:\(show.id)")
                        }
                        if show.trailer != nil {
                            SquareActionButton(symbol: "play.rectangle", label: "Trailer") { showTrailer = true }
                        }
                        Spacer()
                    }

                    if let plot = details?.plot ?? show.plot {
                        Text(plot).font(.body).foregroundStyle(.primary.opacity(0.88))
                    }
                    if let cast = show.cast {
                        (Text("Elenco  ").foregroundStyle(.secondary) + Text(cast)).font(.subheadline).lineLimit(2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                if let details, details.seasons.count > 0 {
                    seasonPicker(details.seasons)
                        .padding(.top, 26)
                        .padding(.bottom, 6)

                    ForEach(episodes) { ep in
                        Button { play(ep) } label: { EpisodeRow(episode: ep, progress: app.progress["episode:\(ep.id)"], fallback: show.backdrop ?? show.cover) }
                            .buttonStyle(PressableStyle(scale: 0.98))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                } else if failed {
                    ContentUnavailableView("Episódios indisponíveis", systemImage: "exclamationmark.triangle", description: Text("O servidor não respondeu. Puxe para tentar de novo."))
                        .padding(.top, 30)
                }
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showTrailer) {
            if let t = show.trailer { TrailerSheet(youtubeID: t, title: show.title) }
        }
    }

    private func load() async {
        do {
            let d = try await app.client?.seriesDetails(show.id)
            details = d
            failed = false
            if let (ep, _) = resumeTarget { season = ep.season } else if let first = d?.seasons.first { season = first.id }
        } catch {
            failed = details == nil
        }
    }

    private func play(_ ep: Episode) {
        let all = allEpisodes
        app.play(all.map { app.playable($0, of: show) }, at: all.firstIndex(of: ep) ?? 0)
    }

    private var meta: [String] {
        var parts: [String] = []
        if let y = show.year { parts.append(String(y)) }
        if let n = details?.seasons.count, n > 0 { parts.append(n == 1 ? "1 temporada" : "\(n) temporadas") }
        if let g = show.genre?.split(separator: ",").first { parts.append(String(g).trimmingCharacters(in: .whitespaces)) }
        return parts
    }

    private func seasonPicker(_ seasons: [Season]) -> some View {
        Group {
            if seasons.count == 1 {
                Text(seasons[0].name).font(.title3.bold()).padding(.horizontal, 20)
            } else {
                ChipBar(chips: seasons.map { .init(id: "\($0.id)", title: $0.name) },
                        selection: Binding(get: { "\(season)" }, set: { season = Int($0) ?? season }))
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let progress: PlaybackProgress?
    let fallback: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                RemoteImage(url: episode.still ?? fallback, maxPixel: 420)
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.callout)
                            .padding(10)
                            .glassCircle()
                    }
                    .overlay(alignment: .bottom) {
                        if let p = progress, p.fraction > 0.01 { ProgressBar(value: p.fraction).padding(6) }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(episode.number). \(episode.title)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let d = episode.duration, d > 0 { Text(Double(d).humanDuration) }
                        if progress?.isFinished == true {
                            Label("Assistido", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let plot = episode.plot {
                Text(plot)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .contentShape(Rectangle())
    }
}
