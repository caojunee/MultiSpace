import SwiftUI
import WebKit
import UIKit
import Combine

private enum WebAlert: Identifiable {
    case clear
    case copied
    var id: Int {
        switch self {
        case .clear: return 0
        case .copied: return 1
        }
    }
}

// MARK: - 浏览器状态

final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var title = ""
    @Published var urlText = ""
    @Published var errorMessage: String?

    weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    func attach(_ webView: WKWebView) {
        self.webView = webView
        observations.removeAll()
        observations.append(webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.progress = wv.estimatedProgress }
        })
        observations.append(webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.title = wv.title ?? "" }
        })
        observations.append(webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.urlText = wv.url?.absoluteString ?? "" }
        })
        observations.append(webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.isLoading = wv.isLoading }
        })
    }

    private func sync(from webView: WKWebView) {
        DispatchQueue.main.async { [weak self] in
            self?.canGoBack = webView.canGoBack
            self?.canGoForward = webView.canGoForward
            self?.urlText = webView.url?.absoluteString ?? ""
            self?.title = webView.title ?? ""
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        sync(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync(from: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = error.localizedDescription }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.errorMessage = error.localizedDescription }
    }
}

// MARK: - WKWebView 封装

struct IsolatedWebView: UIViewRepresentable {
    let space: Space
    let desktopMode: Bool
    @ObservedObject var model: BrowserModel

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    final class Coordinator {
        var lastDesktop: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 关键：每个空间一份独立、持久化的网站数据仓库
        config.websiteDataStore = DataStoreCache.shared.store(for: space.storeID)
        config.defaultWebpagePreferences.preferredContentMode = desktopMode ? .desktop : .mobile
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = model
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = desktopMode ? Self.desktopUA : nil
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false

        model.attach(webView)
        context.coordinator.lastDesktop = desktopMode

        if let url = URL(string: normalizedURL(space.urlString)) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastDesktop != desktopMode else { return }
        context.coordinator.lastDesktop = desktopMode
        webView.customUserAgent = desktopMode ? Self.desktopUA : nil
        webView.reload()
    }
}

// MARK: - 空间页面

struct WebSpaceScreen: View {
    let space: Space
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spaceStore: SpaceStore
    @StateObject private var model = BrowserModel()
    @State private var desktopMode = false
    @State private var alertItem: WebAlert?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                } else {
                    Divider().frame(height: 2)
                }
                IsolatedWebView(space: space, desktopMode: desktopMode, model: model)
                    .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle(space.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("桌面模式", isOn: $desktopMode)
                        Button {
                            UIPasteboard.general.string = model.urlText
                            alertItem = .copied
                        } label: {
                            Label("复制当前网址", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) { alertItem = .clear } label: {
                            Label("清除本空间网站数据", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.canGoBack)
                    Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canGoForward)
                    Spacer()
                    Text(shortHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .alert(item: $alertItem) { kind in
                switch kind {
                case .clear:
                    return Alert(
                        title: Text("清除网站数据"),
                        message: Text("这会退出该空间里所有网站的登录状态，其他空间不受影响。"),
                        primaryButton: .destructive(Text("清除")) {
                            spaceStore.resetWebsiteData(for: space) { model.reload() }
                        },
                        secondaryButton: .cancel()
                    )
                case .copied:
                    return Alert(
                        title: Text("已复制"),
                        message: Text(model.urlText),
                        dismissButton: .default(Text("好"))
                    )
                }
            }
        }
    }

    private var shortHost: String {
        guard let url = URL(string: model.urlText), let host = url.host else {
            return space.site.name
        }
        return host
    }
}
