#if !os(tvOS)
import SwiftUI
@preconcurrency import WebKit
import os.log

private let log = Logger(subsystem: "Moonlight", category: "PairingWebView")

struct PairingWebView: View {
    let url: URL
    var onCancel: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                ProxiedWebView(url: url, isLoading: $isLoading, loadError: $loadError)
                    .ignoresSafeArea()
                if isLoading {
                    ProgressView()
                }
                if let error = loadError {
                    ContentUnavailableView {
                        Label("Connection Failed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    }
                }
            }
            .navigationTitle("Pair with Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - UIViewRepresentable

private struct ProxiedWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> NavigationCoordinator {
        NavigationCoordinator(isLoading: $isLoading, loadError: $loadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let host = url.host ?? ""
        let schemeHandler = TLSProxySchemeHandler(trustedHost: host)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: TLSProxySchemeHandler.scheme)

        let viewportScript = WKUserScript(
            source: """
                var meta = document.querySelector('meta[name="viewport"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, viewport-fit=cover';
                """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(viewportScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.underPageBackgroundColor = .black

        #if DEBUG
        webView.isInspectable = true
        #endif

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.scheme = TLSProxySchemeHandler.scheme
        let proxyURL = components.url!

        log.info("Loading via scheme handler: \(proxyURL.absoluteString)")
        webView.load(URLRequest(url: proxyURL))

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

// MARK: - WKNavigationDelegate

private final class NavigationCoordinator: NSObject, WKNavigationDelegate {
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    init(isLoading: Binding<Bool>, loadError: Binding<String?>) {
        self._isLoading = isLoading
        self._loadError = loadError
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log.info("didStartProvisionalNavigation")
        isLoading = true
        loadError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.info("didFinish, URL: \(webView.url?.absoluteString ?? "nil")")
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        log.error("didFailProvisionalNavigation: code=\(nsError.code) \(error.localizedDescription)")
        isLoading = false
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        log.error("didFail: code=\(nsError.code) \(error.localizedDescription)")
        isLoading = false
        loadError = error.localizedDescription
    }
}

// MARK: - TLS Proxy Scheme Handler

private final class TLSProxySchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "moonlight-pair"

    private let trustedHost: String
    private let session: URLSession
    private let trustDelegate: TrustAllCertsDelegate
    private var activeTasks: [Int: Task<Void, Never>] = [:]
    private let lock = NSLock()

    init(trustedHost: String) {
        self.trustedHost = trustedHost
        self.trustDelegate = TrustAllCertsDelegate()
        // Session without delegate — trust is handled per-task via async data(for:delegate:)
        self.session = URLSession(configuration: .ephemeral)
        super.init()
        log.info("SchemeHandler created for host: \(trustedHost)")
    }

    deinit {
        session.invalidateAndCancel()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard var components = URLComponents(url: urlSchemeTask.request.url!, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        components.scheme = "https"
        guard let httpsURL = components.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        var request = URLRequest(url: httpsURL)
        request.httpMethod = urlSchemeTask.request.httpMethod
        request.httpBody = urlSchemeTask.request.httpBody
        urlSchemeTask.request.allHTTPHeaderFields?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let taskID = urlSchemeTask.hash
        log.info("Proxy: \(request.httpMethod ?? "GET") \(httpsURL.absoluteString)")

        nonisolated(unsafe) let schemeTask = urlSchemeTask
        let session = self.session
        let delegate = self.trustDelegate

        let task = Task {
            do {
                let (data, response) = try await session.data(for: request, delegate: delegate)

                guard !Task.isCancelled else { return }

                schemeTask.didReceive(response)
                schemeTask.didReceive(data)
                schemeTask.didFinish()
                log.info("Proxy: completed \(httpsURL.lastPathComponent) (\(data.count) bytes)")
            } catch is CancellationError {
                // Cancelled by stop, do nothing
            } catch {
                guard !Task.isCancelled else { return }
                log.error("Proxy error: \(error.localizedDescription)")
                schemeTask.didFailWithError(error)
            }
        }

        lock.lock()
        activeTasks[taskID] = task
        lock.unlock()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let taskID = urlSchemeTask.hash
        lock.lock()
        let task = activeTasks.removeValue(forKey: taskID)
        lock.unlock()
        task?.cancel()
    }
}

// MARK: - Per-Task URLSession Delegate (disables TLS certificate validation)

private final class TrustAllCertsDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        log.info("TLS challenge: method=\(challenge.protectionSpace.authenticationMethod) host=\(challenge.protectionSpace.host)")

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            log.info("Accepting certificate for \(challenge.protectionSpace.host)")
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
#endif
