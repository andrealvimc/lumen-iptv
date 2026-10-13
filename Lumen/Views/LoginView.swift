import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case server, user, pass }

    private var canSubmit: Bool { !server.isEmpty && !username.isEmpty && !password.isEmpty && !isLoading }

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        BrandMark(size: 92)
                        Text("Lumen")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("Seus canais, filmes e séries,\ndo jeito que deveriam ser.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 70)

                    VStack(spacing: 0) {
                        field("Servidor", text: $server, symbol: "server.rack", placeholder: "http://exemplo.com:8080", field: .server)
                            .keyboardType(.URL)
                        Divider().padding(.leading, 52)
                        field("Usuário", text: $username, symbol: "person.fill", placeholder: "Usuário", field: .user)
                        Divider().padding(.leading, 52)
                        HStack {
                            field("Senha", text: $password, symbol: "key.fill", placeholder: "Senha", field: .pass, secure: !showPassword)
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                            }
                            .padding(.trailing, 16)
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button(action: submit) {
                        ZStack {
                            Text("Entrar").opacity(isLoading ? 0 : 1)
                            if isLoading { ProgressView().tint(.black) }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.black)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .disabled(!canSubmit)
                    .opacity(canSubmit || isLoading ? 1 : 0.5)

                    Text("Compatível com servidores Xtream Codes. Seus dados ficam só no Keychain deste iPhone.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeInOut, value: error)
        .onSubmit {
            switch focus {
            case .server: focus = .user
            case .user: focus = .pass
            default: submit()
            }
        }
    }

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(red: 0.55, green: 0.28, blue: 0.2).opacity(0.55), .clear], center: .init(x: 0.5, y: 0.12), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.4).opacity(0.5), .clear], center: .init(x: 0.1, y: 0.9), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, symbol: String, placeholder: String, field: Field, secure: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(field == .pass ? .go : .next)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .accessibilityLabel(label)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        isLoading = true
        error = nil
        Task {
            do {
                try await app.signIn(server: server, username: username, password: password)
            } catch {
                self.error = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isLoading = false
        }
    }
}
