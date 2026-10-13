import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 72
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
            .fill(
                RadialGradient(colors: [Color(red: 0.62, green: 0.33, blue: 0.28), Color(red: 0.12, green: 0.08, blue: 0.2)],
                               center: .center, startRadius: 0, endRadius: size * 0.7)
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.4, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.7), Color(red: 1, green: 0.68, blue: 0.36)], startPoint: .top, endPoint: .bottom))
                    .offset(x: size * 0.04)
                    .shadow(color: .orange.opacity(0.6), radius: size * 0.12)
            }
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}

struct PosterCard: View {
    let title: String
    let image: URL?
    var width: CGFloat = 118
    var rating: Double?
    var progress: Double?
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemoteImage(url: image, maxPixel: width * 3) {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.18), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .overlay(alignment: .bottom) {
                if let progress, progress > 0 {
                    ProgressBar(value: progress).padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let rating, rating >= 7 {
                    Text(String(format: "%.1f", rating))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .glassCapsule()
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            if showsTitle {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
    }
}

struct WideCard: View {
    let title: String
    let subtitle: String?
    let image: URL?
    var width: CGFloat = 260
    var progress: Double?
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemoteImage(url: image, maxPixel: width * 2.5)
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .padding(14)
                        .glassCircle()
                }
                .overlay(alignment: .bottom) {
                    if let progress { ProgressBar(value: progress).padding(10) }
                }
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .glassCapsule()
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.white.opacity(0.3))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: g.size.width * min(max(value, 0.03), 1))
                }
        }
        .frame(height: 4)
    }
}

struct ChannelLogo: View {
    let url: URL?
    let name: String
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color(white: 0.14))
            .frame(width: size, height: size)
            .overlay {
                RemoteImage(url: url, maxPixel: size * 3, contentMode: .fit) {
                    Text(initials)
                        .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(size * 0.12)
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }

    private var initials: String {
        name.split(separator: " ").filter { $0.first?.isLetter == true }.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

struct Shelf<Item: Identifiable, Card: View, Destination: View>: View {
    let title: String
    let items: [Item]
    @ViewBuilder var destination: () -> Destination
    @ViewBuilder var card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.title2, weight: .bold))
                    .tracking(-0.3)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if Destination.self != EmptyView.self {
                    NavigationLink {
                        destination()
                    } label: {
                        Text("Ver tudo")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { card($0) }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

extension Shelf where Destination == EmptyView {
    init(title: String, items: [Item], @ViewBuilder card: @escaping (Item) -> Card) {
        self.title = title
        self.items = items
        self.destination = { EmptyView() }
        self.card = card
    }
}

struct ChipBar: View {
    struct Chip: Identifiable, Hashable { let id: String; let title: String; var symbol: String? }
    let chips: [Chip]
    @Binding var selection: String
    @Namespace private var ns

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        let selected = chip.id == selection
                        Button {
                            withAnimation(.spring(duration: 0.3)) { selection = chip.id }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack(spacing: 5) {
                                if let s = chip.symbol { Image(systemName: s).font(.caption.weight(.bold)) }
                                Text(chip.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(selected ? .black : .primary)
                            .background {
                                if selected {
                                    Capsule().fill(.white).matchedGeometryEffect(id: "chip", in: ns)
                                } else {
                                    Capsule().fill(Color(white: 0.16))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(chip.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: selection) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
    }
}

struct MetaLine: View {
    let parts: [String]
    var rating: Double?
    var body: some View {
        HStack(spacing: 6) {
            if let rating {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                }
                if !parts.isEmpty { Text("·") }
            }
            Text(parts.joined(separator: " · ")).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

struct PosterGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder var card: (Item) -> Card
    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(items) { card($0) }
        }
        .padding(.horizontal, 16)
    }
}
