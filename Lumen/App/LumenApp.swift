import SwiftUI

@main
struct LumenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(.accentColor)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.mask
    }
}

enum Orientation {
    static var mask: UIInterfaceOrientationMask = .portrait

    @MainActor
    static func lock(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        // Every controller in the presentation chain has to re-query, or iOS ignores the request.
        var vc = scene.keyWindow?.rootViewController
        while let current = vc {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if app.credentials == nil {
                LoginView()
                    .transition(.opacity)
            } else {
                switch app.phase {
                case .ready:
                    MainTabs()
                        .transition(.opacity)
                case .failed(let message):
                    FailureView(message: message)
                default:
                    LoadingCatalogView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: app.credentials == nil)
        .animation(.easeInOut(duration: 0.35), value: app.phase)
        .fullScreenCover(item: $app.session) { session in
            PlayerView(session: session, app: app)
                .environment(app)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app
    @State private var tab = "home"

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: "home") { HomeView() } label: { tabLabel("Início", "house") }
            Tab(value: "live") { LiveView() } label: { tabLabel("Ao Vivo", "play.tv") }
            Tab(value: "movies") { MoviesView() } label: { tabLabel("Filmes", "film") }
            Tab(value: "series") { SeriesView() } label: { tabLabel("Séries", "square.stack") }
            Tab(value: "search", role: .search) { SearchView() }
        }
        .minimizingTabBar()
        #if DEBUG
        .task {
            if let t = ProcessInfo.processInfo.environment["LUMEN_TAB"] { tab = t }
            // Dev convenience for screenshots: LUMEN_PLAY=<n> opens the n-th live channel.
            if let n = ProcessInfo.processInfo.environment["LUMEN_PLAY"].flatMap(Int.init), app.channels.indices.contains(n) {
                try? await Task.sleep(for: .seconds(1))
                app.play(app.channels.map(app.playable), at: n)
            }
        }
        #endif
    }
}

/// Thin outline glyphs read lighter than the default filled tab symbols.
private func tabLabel(_ title: String, _ symbol: String) -> some View {
    Label(title, systemImage: symbol).environment(\.symbolVariants, .none)
}

struct LoadingCatalogView: View {
    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 84)
            ProgressView().controlSize(.large)
            Text("Carregando sua biblioteca…")
                .font(.headline)
            Text("Na primeira vez pode levar alguns segundos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct FailureView: View {
    @Environment(AppModel.self) private var app
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Não foi possível carregar", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Tentar de novo") { Task { await app.refresh() } }
                .buttonStyle(.borderedProminent)
            Button("Sair da conta", role: .destructive) { app.signOut() }
        }
    }
}
