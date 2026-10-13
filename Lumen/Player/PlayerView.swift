import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(AppModel.self) private var app
    @State private var model: PlayerModel
    @State private var seekFeedback: SeekFeedback?
    @State private var brightnessHUD: CGFloat?
    @State private var brightnessStart: CGFloat = 0
    @State private var zoomHint: VideoGravity?

    init(session: PlaybackSession, app: AppModel) {
        _model = State(initialValue: PlayerModel(session: session, app: app))
    }

    struct SeekFeedback: Equatable {
        var forward: Bool
        var amount: Int
        var id = UUID()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                EngineHost(engine: model.engine, generation: model.engineGeneration)
                    .ignoresSafeArea()

                gestureLayer(width: geo.size.width)

                if let seekFeedback { SeekRipple(feedback: seekFeedback, width: geo.size.width).allowsHitTesting(false) }

                if model.isBuffering && model.error == nil {
                    LoadingIndicator(artwork: model.hasStarted ? nil : (model.item.backdrop ?? model.item.artwork), title: model.hasStarted ? nil : model.item.title)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if model.isLocked {
                    lockOverlay
                } else if model.controlsVisible || model.error != nil {
                    PlayerControls(model: model, app: app)
                        .transition(.opacity)
                }

                if let error = model.error { errorCard(error) }

                if let left = model.upNextCountdown, let next = model.nextItem, !model.isLocked {
                    UpNextCard(item: next, secondsLeft: left) { model.next() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 28).padding(.bottom, model.controlsVisible ? 110 : 34)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if let b = brightnessHUD { SideHUD(symbol: "sun.max.fill", value: b).transition(.opacity) }
                if let zoomHint { ZoomHint(gravity: zoomHint).transition(.scale(scale: 0.9).combined(with: .opacity)) }

                if model.showQueue {
                    QueuePanel(model: model)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.controlsVisible)
            .animation(.spring(duration: 0.35), value: model.showQueue)
            .animation(.easeInOut(duration: 0.2), value: model.isBuffering)
            .animation(.spring(duration: 0.4), value: model.upNextCountdown != nil)
        }
        .statusBarHidden(!model.controlsVisible)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Orientation.lock(.landscape)
            model.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.teardown()
            Orientation.lock(.portrait)
        }
    }

    // MARK: Gestures

    private func gestureLayer(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { e in doubleTap(at: e.location.x, width: width) }
                    .exclusively(before: SpatialTapGesture(count: 1).onEnded { _ in
                        guard !model.isLocked else { return }
                        model.toggleControls()
                    })
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onEnded { v in
                        guard !model.isLocked else { return }
                        let target: VideoGravity = v.magnification > 1 ? .fill : .fit
                        guard target != model.gravity else { return }
                        model.gravity = target
                        flashZoomHint(target)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { v in
                        guard !model.isLocked, v.startLocation.x < width * 0.35,
                              abs(v.translation.height) > abs(v.translation.width) else { return }
                        if brightnessHUD == nil { brightnessStart = UIScreen.main.brightness }
                        let value = min(max(brightnessStart - v.translation.height / 300, 0), 1)
                        UIScreen.main.brightness = value
                        brightnessHUD = value
                    }
                    .onEnded { _ in withAnimation(.easeOut.delay(0.6)) { brightnessHUD = nil } }
            )
    }

    private func doubleTap(at x: CGFloat, width: CGFloat) {
        guard !model.isLocked else { return }
        if model.isLive {
            model.toggleControls()
            return
        }
        let forward = x > width / 2
        var amount = 10
        if let f = seekFeedback, f.forward == forward { amount = f.amount + 10 }
        model.skip(forward ? 10 : -10)
        let fb = SeekFeedback(forward: forward, amount: amount)
        withAnimation(.easeOut(duration: 0.15)) { seekFeedback = fb }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            if seekFeedback?.id == fb.id { withAnimation(.easeOut(duration: 0.3)) { seekFeedback = nil } }
        }
    }

    private func flashZoomHint(_ g: VideoGravity) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(duration: 0.3)) { zoomHint = g }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if zoomHint == g { withAnimation(.easeOut) { zoomHint = nil } }
        }
    }

    // MARK: Overlays

    private var lockOverlay: some View {
        VStack {
            Spacer()
            Button {
                withAnimation { model.isLocked = false }
                model.controlsVisible = true
                model.bumpControls()
            } label: {
                Label("Desbloquear", systemImage: "lock.open.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 30)
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.yellow)
            Text("Não foi possível reproduzir")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack(spacing: 10) {
                Button("Tentar de novo") { model.retry() }
                    .buttonStyle(.borderedProminent)
                if model.engineName != "VLC" {
                    Button("Abrir com VLC") { model.retryWithVLC() }
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .glassCard(cornerRadius: 26)
    }
}

// MARK: - Engine host

struct EngineHost: UIViewRepresentable {
    let engine: PlaybackEngine?
    let generation: Int

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let engineView = engine?.view, engineView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        engineView.frame = container.bounds
        engineView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(engineView)
    }
}

// MARK: - Controls

struct PlayerControls: View {
    @Bindable var model: PlayerModel
    let app: AppModel

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            if model.error == nil { centerTransport }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            GlassIconButton(symbol: "xmark") { app.session = nil }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.item.title)
                    .font(.headline)
                    .lineLimit(1)
                if let sub = model.item.subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)

            HStack(spacing: 8) {
                GlassIconButton(symbol: "lock.fill") {
                    withAnimation { model.isLocked = true; model.controlsVisible = false }
                }
                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .glassCircle()
                if model.engine?.supportsPiP == true {
                    GlassIconButton(symbol: model.pipActive ? "pip.exit" : "pip.enter") { model.togglePiP() }
                        .disabled(!model.pipPossible)
                        .opacity(model.pipPossible ? 1 : 0.4)
                }
                settingsMenu
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            if !model.audioTracks.isEmpty {
                Picker(selection: Binding(get: { model.selectedAudio ?? "" }, set: { model.selectAudio($0) })) {
                    ForEach(model.audioTracks) { Text($0.name).tag($0.id) }
                } label: { Label("Áudio", systemImage: "waveform") }
                .pickerStyle(.menu)
            }
            Picker(selection: Binding(get: { model.selectedSubtitle ?? "off" }, set: { model.selectSubtitle($0 == "off" ? nil : $0) })) {
                Text("Desativadas").tag("off")
                ForEach(model.subtitleTracks) { Text($0.name).tag($0.id) }
            } label: { Label("Legendas", systemImage: "captions.bubble") }
            .pickerStyle(.menu)

            if !model.isLive {
                Picker(selection: $model.rate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0] as [Float], id: \.self) { r in
                        Text(r == 1 ? "Normal" : String(format: "%gx", r)).tag(r)
                    }
                } label: { Label("Velocidade", systemImage: "gauge.with.dots.needle.67percent") }
                .pickerStyle(.menu)
            }

            Picker(selection: $model.gravity) {
                ForEach(VideoGravity.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            } label: { Label("Tela", systemImage: "aspectratio") }
            .pickerStyle(.menu)

            Section("Motor: \(model.engineName)") {
                if model.engineName != "VLC" {
                    Button { model.retryWithVLC() } label: { Label("Reabrir com VLC", systemImage: "arrow.triangle.2.circlepath") }
                } else {
                    Button { model.retry() } label: { Label("Recarregar", systemImage: "arrow.clockwise") }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassCircle()
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .simultaneousGesture(TapGesture().onEnded { model.bumpControls() })
    }

    private var centerTransport: some View {
        HStack(spacing: 64) {
            if model.isLive {
                TransportButton(symbol: "backward.end.fill", size: 26) { model.previous() }
                    .opacity(model.hasPrevious ? 1 : 0.3).disabled(!model.hasPrevious)
            } else {
                TransportButton(symbol: "gobackward.10", size: 30) { model.skip(-10) }
            }

            TransportButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 46) { model.togglePlay() }
                .contentTransition(.symbolEffect(.replace.downUp))
                .opacity(model.isBuffering && !model.hasStarted ? 0 : 1)

            if model.isLive {
                TransportButton(symbol: "forward.end.fill", size: 26) { model.next() }
                    .opacity(model.hasNext ? 1 : 0.3).disabled(!model.hasNext)
            } else {
                TransportButton(symbol: "goforward.10", size: 30) { model.skip(10) }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if model.isLive {
                HStack(spacing: 10) {
                    LiveBadge()
                    Text(model.item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    queueButton(label: "Canais", symbol: "list.bullet")
                }
            } else {
                Scrubber(model: model)
                HStack(spacing: 10) {
                    Spacer()
                    if model.queue.count > 1 { queueButton(label: "Episódios", symbol: "rectangle.stack") }
                    if let next = model.nextItem {
                        Button { model.next() } label: {
                            Label("Próximo", systemImage: "forward.end.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .glassCapsule()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(next.subtitle ?? next.title)
                    }
                }
            }
        }
    }

    private func queueButton(label: String, symbol: String) -> some View {
        Button { model.showQueue = true } label: {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassCapsule()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scrubber

struct Scrubber: View {
    @Bindable var model: PlayerModel
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let dur = max(model.duration, 0.001)
                let progress = CGFloat(min(model.displayPosition / dur, 1))
                let buffered = CGFloat(min(model.buffered / dur, 1))
                let height: CGFloat = dragging ? 10 : 5

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white.opacity(0.35)).frame(width: w * buffered)
                    Capsule().fill(.white).frame(width: max(w * progress, height))
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    if dragging {
                        Text(model.displayPosition.clock)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .glassCapsule()
                            .fixedSize()
                            .offset(x: min(max(w * progress - 30, 0), w - 60), y: -28)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !dragging {
                                withAnimation(.spring(duration: 0.25)) { dragging = true }
                                model.isScrubbing = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            let f = min(max(v.location.x / w, 0), 1)
                            model.scrubPosition = Double(f) * model.duration
                        }
                        .onEnded { _ in
                            model.commitScrub()
                            withAnimation(.spring(duration: 0.25)) { dragging = false }
                        }
                )
                .animation(.spring(duration: 0.25), value: dragging)
            }
            .frame(height: 24)

            HStack {
                Text(model.displayPosition.clock)
                Spacer()
                Text("-" + max(model.duration - model.displayPosition, 0).clock)
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
        }
    }
}

// MARK: - Bits

struct GlassIconButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassCircle()
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 2, height: size * 2)
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.4), radius: 8)
        }
        .buttonStyle(PressableStyle(scale: 0.85))
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct LiveBadge: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.white).frame(width: 7, height: 7)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulse)
            Text("AO VIVO").font(.caption.weight(.heavy)).tracking(0.6)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.red, in: Capsule())
        .onAppear { pulse = true }
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Color.accentColor)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct LoadingIndicator: View {
    let artwork: URL?
    let title: String?
    var body: some View {
        ZStack {
            if let artwork {
                // Overlay on a flexible color so the fill image can't widen the layout.
                Color.black
                    .overlay { RemoteImage(url: artwork, maxPixel: 900).blur(radius: 30) }
                    .overlay(Color.black.opacity(0.55))
                    .clipped()
                    .ignoresSafeArea()
            }
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                if let title {
                    Text(title).font(.headline).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }
}

struct SeekRipple: View {
    let feedback: PlayerView.SeekFeedback
    let width: CGFloat
    var body: some View {
        HStack {
            if feedback.forward { Spacer() }
            ZStack {
                Ellipse()
                    .fill(.white.opacity(0.12))
                    .frame(width: width * 0.42)
                    .offset(x: feedback.forward ? width * 0.1 : -width * 0.1)
                VStack(spacing: 6) {
                    Image(systemName: feedback.forward ? "forward.fill" : "backward.fill")
                        .font(.title2)
                        .symbolEffect(.bounce, value: feedback.amount)
                    Text("\(feedback.amount) s").font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            .frame(maxHeight: .infinity)
            if !feedback.forward { Spacer() }
        }
        .ignoresSafeArea()
        .clipped()
    }
}

struct SideHUD: View {
    let symbol: String
    let value: CGFloat
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
            GeometryReader { g in
                Capsule().fill(.white.opacity(0.25))
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: g.size.width * value) }
            }
            .frame(width: 120, height: 5)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCapsule()
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
    }
}

struct ZoomHint: View {
    let gravity: VideoGravity
    var body: some View {
        Label(gravity.label, systemImage: gravity.symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
    }
}

struct UpNextCard: View {
    let item: PlayableItem
    let secondsLeft: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RemoteImage(url: item.artwork, maxPixel: 300)
                    .frame(width: 112, height: 63)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Próximo episódio em \(Int(secondsLeft.rounded(.up)))s")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.subtitle ?? item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                Image(systemName: "play.circle.fill").font(.title)
            }
            .padding(10)
            .frame(width: 340, alignment: .leading)
            .glassCard(cornerRadius: 18)
        }
        .buttonStyle(PressableStyle())
    }
}

struct QueuePanel: View {
    @Bindable var model: PlayerModel

    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { model.showQueue = false; model.bumpControls() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.isLive ? "Canais" : "Episódios").font(.title3.bold())
                    Spacer()
                    Button { model.showQueue = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(model.queue.enumerated()), id: \.element.id) { i, item in
                                Button { model.jump(to: i) } label: { row(item, current: i == model.index) }
                                    .buttonStyle(.plain)
                                    .id(i)
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 20)
                    }
                    .onAppear { proxy.scrollTo(model.index, anchor: .center) }
                }
            }
            .frame(width: 360)
            .background(.regularMaterial)
        }
        .ignoresSafeArea(edges: .vertical)
    }

    private func row(_ item: PlayableItem, current: Bool) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: item.artwork, maxPixel: 200, contentMode: model.isLive ? .fit : .fill)
                .frame(width: model.isLive ? 52 : 96, height: model.isLive ? 40 : 54)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isLive ? item.title : (item.subtitle ?? item.title))
                    .font(.subheadline.weight(current ? .bold : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if current {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: model.isPlaying)
            }
        }
        .padding(8)
        .background(current ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
