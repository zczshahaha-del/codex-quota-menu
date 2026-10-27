import Combine
import Foundation

@MainActor
final class QuotaViewModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var isRefreshing = true
    @Published private(set) var dailyTokenUsage: DailyTokenUsage?

    private let client: CodexAppServerClient
    private let tokenUsageReader: DailyTokenUsageReading
    private let tokenQueue = DispatchQueue(label: "CodexQuotaMenu.dailyTokens", qos: .utility)
    private var tokenRefreshInFlight = false
    private var tokenRefreshGeneration = UUID()
    private var refreshTimer: Timer?
    private var started = false

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        tokenUsageReader: DailyTokenUsageReading = DailyTokenUsageReader()
    ) {
        self.client = client
        self.tokenUsageReader = tokenUsageReader

        client.onRateLimits = { [weak self] result in
            Task { @MainActor in
                self?.accept(result)
            }
        }

        client.onError = { [weak self] _ in
            Task { @MainActor in
                self?.isRefreshing = false
            }
        }
    }

    var displayWindow: QuotaWindow? {
        snapshot?.main.primary ?? snapshot?.main.secondary
    }

    var todayTokens: TokenUsage? {
        guard let dailyTokenUsage, Calendar.current.isDateInToday(dailyTokenUsage.day) else { return nil }
        return dailyTokenUsage.usage
    }

    var todayTokenSummary: String {
        guard let usage = todayTokens else { return "--" }
        return "\(TokenUsageFormatter.compact(usage.total)) tokens"
    }

    var todayTokenDetail: String {
        guard let usage = todayTokens else { return "本机 Codex" }
        return "输入 \(TokenUsageFormatter.compact(usage.input)) · 输出 \(TokenUsageFormatter.compact(usage.output))"
    }

    var todayTokenHelp: String {
        guard let usage = todayTokens else { return "本机 Codex 今日用量" }
        return "本机 Codex · 今日午夜起\n合计 \(TokenUsageFormatter.exact(usage.total)) tokens\n输入 \(TokenUsageFormatter.exact(usage.input))（含缓存 \(TokenUsageFormatter.exact(usage.cachedInput))）\n输出 \(TokenUsageFormatter.exact(usage.output))"
    }

    var menuBarTitle: String {
        guard let window = displayWindow else {
            return isRefreshing ? "…" : "--%·--"
        }

        return "\(window.remainingPercent)%·\(QuotaFormatter.compactReset(until: window.resetsAt))"
    }

    var accessibilityStatus: String {
        guard let window = displayWindow else {
            return isRefreshing ? "正在读取 Codex 额度" : "Codex 额度暂无数据"
        }

        return "Codex 剩余 \(window.remainingPercent)%，\(QuotaFormatter.compactReset(until: window.resetsAt)) 后重置"
    }

    func start() {
        guard !started else { return }
        started = true
        isRefreshing = true
        client.start()
        refreshTokenUsage()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        isRefreshing = true
        client.refresh()
        refreshTokenUsage()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        started = false
        tokenRefreshGeneration = UUID()
        tokenRefreshInFlight = false
        client.stop()
    }

    private func refreshTokenUsage() {
        guard started, !tokenRefreshInFlight else { return }
        tokenRefreshInFlight = true
        let generation = tokenRefreshGeneration
        let reader = tokenUsageReader
        let now = Date()
        let calendar = Calendar.current
        tokenQueue.async { [weak self] in
            let result = try? reader.read(now: now, calendar: calendar)
            Task { @MainActor [weak self] in
                guard let self, self.started, self.tokenRefreshGeneration == generation else { return }
                self.tokenRefreshInFlight = false
                if let result, result != self.dailyTokenUsage { self.dailyTokenUsage = result }
            }
        }
    }

    private func accept(_ result: [String: Any]) {
        guard let parsed = RateLimitParser.parse(result: result) else {
            isRefreshing = false
            return
        }

        snapshot = parsed
        isRefreshing = false
    }
}
