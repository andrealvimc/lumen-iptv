import SwiftUI
import WebKit

/// In-app YouTube trailer, presented as a sheet over the detail page.
struct TrailerSheet: View {
    let youtubeID: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trailer").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(title).font(.headline).lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .glassCircle()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            YouTubePlayer(id: youtubeID)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .background(Color.black)
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
    }
}

struct YouTubePlayer: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:#000;height:100%}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&autoplay=1&rel=0&modestbranding=1&hl=pt-BR"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
        // YouTube refuses embeds without an https origin/referrer (error 153).
        web.loadHTMLString(html, baseURL: URL(string: "https://lumen.app"))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
