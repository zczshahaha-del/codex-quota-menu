import Combine
import Foundation

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = true
    @Published private(set) var isConnected = false
    @Published private(set) var errorMessage: String?

    private let client: CodexAppServerClient
    private var refreshTimer: Timer?
    private var started = false

    init(client: CodexAppServerClient = CodexAppServerClient()) {
        self.client = client

        client.onRateLimits = { [weak self] result in
            Task { @MainActor in
                self?.accept(result)
            }
        }

        client.onError = { [weak self] message in
            Task { @MainActor in
                self?.isRefreshing = false
                self?.errorMessage = message
            }
        }

        client.onConnectionChanged = { [weak self] connected in
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
    }

    var menuBarTitle: String {
        guard let window = snapshot?.main.primary else {
            return isRefreshing ? "…" : "--%·--"
        }

        return "\(window.remainingPercent)%·\(QuotaFormatter.compactReset(until: window.resetsAt))"
    }

    var accessibilityStatus: String {
        guard let window = snapshot?.main.primary else {
            return errorMessage ?? "正在读取 Codex 额度"
        }

        return "Codex 剩余 \(window.remainingPercent)%，\(QuotaFormatter.compactReset(until: window.resetsAt)) 后重置"
    }

    func start() {
        guard !started else { return }
        started = true
        isRefreshing = true
        client.start()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        isRefreshing = true
        errorMessage = nil
        client.refresh()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        client.stop()
    }

    private func accept(_ result: [String: Any]) {
        guard let parsed = RateLimitParser.parse(result: result) else {
            isRefreshing = false
            errorMessage = "Codex 没有返回可显示的额度窗口。"
            return
        }

        snapshot = parsed
        isRefreshing = false
        errorMessage = nil
    }
}
