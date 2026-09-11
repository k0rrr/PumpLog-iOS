import SwiftUI
import WebKit

struct Phase1Body3DView: View {
    let activeGroups: Set<Phase1MuscleGroup>

    var body: some View {
        Phase1AnatomyWebView(activeGroups: activeGroups)
            .frame(height: 410)
            .background(
                RadialGradient(
                    colors: [Color(red: 0.16, green: 0.17, blue: 0.19), Color(red: 0.05, green: 0.05, blue: 0.06)],
                    center: .top,
                    startRadius: 10,
                    endRadius: 390
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topLeading) {
                Text("3D BODY")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(14)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("ドラッグで回転、ピンチで拡大できます")
    }

    private var accessibilityDescription: String {
        guard !activeGroups.isEmpty else {
            return "3Dボディモデル。負荷の記録はありません"
        }
        let names = activeGroups.map(\.title).sorted().joined(separator: "、")
        return "3Dボディモデル。負荷部位: \(names)"
    }
}

private struct Phase1AnatomyWebView: UIViewRepresentable {
    let activeGroups: Set<Phase1MuscleGroup>

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()

        if let bundleURL = Bundle.main.url(forResource: "BodyAnatomyLicensed", withExtension: "bundle") {
            let schemeHandler = Phase1BodyBundleSchemeHandler(bundleURL: bundleURL)
            context.coordinator.schemeHandler = schemeHandler
            configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "pump")
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isAccessibilityElement = false

        context.coordinator.webView = webView
        context.coordinator.pendingGroups = activeGroups
        loadViewer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingGroups = activeGroups
        context.coordinator.sendGroupsIfReady()
    }

    private func loadViewer(in webView: WKWebView) {
        guard Bundle.main.url(forResource: "BodyAnatomyLicensed", withExtension: "bundle") != nil else {
            webView.loadHTMLString(
                "<html><body style='background:transparent;color:#999;font:14px -apple-system;display:flex;align-items:center;justify-content:center;height:100%'>人体モデルを読み込めませんでした</body></html>",
                baseURL: nil
            )
            return
        }

        // A custom local scheme keeps the HTML module imports same-origin in
        // WKWebView. Loading the nested bundle directly as file:// is rejected
        // by WebKit's cross-origin policy when Three.js imports its modules.
        guard let entryURL = URL(string: "pump://body/index.html") else { return }
        webView.load(URLRequest(url: entryURL))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var schemeHandler: Phase1BodyBundleSchemeHandler?
        var pendingGroups: Set<Phase1MuscleGroup> = []
        private var isReady = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            sendGroupsIfReady()
        }

        func sendGroupsIfReady() {
            guard isReady, let webView else { return }
            let groupNames = pendingGroups.map(\.rawValue).sorted()
            guard
                let data = try? JSONSerialization.data(withJSONObject: groupNames),
                let json = String(data: data, encoding: .utf8)
            else { return }
            // The page's ES module can finish after WKWebView reports the
            // document load. Queue the groups in that case so the viewer
            // applies them as soon as its function is defined.
            webView.evaluateJavaScript("window.pumpLogSetActiveGroups ? window.pumpLogSetActiveGroups(\(json)) : (window.pumpLogPendingGroups = \(json))")
        }
    }
}

private final class Phase1BodyBundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let bundleURL: URL
    private let queue = DispatchQueue(label: "com.pumplog.body-bundle", qos: .userInitiated)

    init(bundleURL: URL) {
        self.bundleURL = bundleURL.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "PumpLogBody", code: 1))
            return
        }

        let relativePath = requestURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = bundleURL.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(bundleURL.path + "/"), let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "PumpLogBody", code: 2))
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: data.count,
            textEncodingName: fileURL.pathExtension == "html" || fileURL.pathExtension == "js" ? "utf-8" : nil
        )
        queue.async {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html"
        case "js": return "text/javascript"
        case "css": return "text/css"
        case "glb": return "model/gltf-binary"
        case "wasm": return "application/wasm"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
