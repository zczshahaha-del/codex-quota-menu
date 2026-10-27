import XCTest
@testable import CodexQuotaMenu

@MainActor
final class QuotaViewModelTests: XCTestCase {
    func testReadFailureQuietlyKeepsCachedValue() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onRateLimits?(result(window: "primary"))
        await settle()
        XCTAssertTrue(model.menuBarTitle.hasPrefix("10%"))
        let title = model.menuBarTitle
        let status = model.accessibilityStatus

        client.onError?("网络不可用")
        await settle()
        XCTAssertEqual(model.menuBarTitle, title)
        XCTAssertEqual(model.accessibilityStatus, status)
        XCTAssertEqual(model.snapshot?.main.primary?.remainingPercent, 10)

        client.onRateLimits?(result(window: "primary"))
        await settle()
        XCTAssertFalse(model.menuBarTitle.contains("⚠︎"))
        XCTAssertFalse(model.isRefreshing)
    }

    func testMalformedResponseKeepsCachedValueAndEndsRefresh() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onRateLimits?(result(window: "primary"))
        await settle()
        client.onRateLimits?([:])
        await settle()
        XCTAssertTrue(model.menuBarTitle.hasPrefix("10%"))
        XCTAssertTrue(model.accessibilityStatus.hasPrefix("Codex 剩余 10%"))
        XCTAssertFalse(model.isRefreshing)
    }

    func testSecondaryOnlySnapshotIsDisplayed() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onRateLimits?(result(window: "secondary"))
        await settle()
        XCTAssertTrue(model.menuBarTitle.hasPrefix("10%"))
        XCTAssertTrue(model.accessibilityStatus.contains("10%"))
        XCTAssertFalse(model.isRefreshing)
    }

    func testRetryKeepsCachedValueWithoutWarning() async {
        let client = CodexAppServerClient(executableProvider: { nil })
        let model = QuotaViewModel(client: client)
        client.onRateLimits?(result(window: "primary"))
        await settle()
        client.onError?("网络不可用")
        await settle()
        model.refresh()
        XCTAssertTrue(model.isRefreshing)
        XCTAssertTrue(model.menuBarTitle.hasPrefix("10%"))
        XCTAssertTrue(model.accessibilityStatus.hasPrefix("Codex 剩余 10%"))
        model.stop()
    }

    func testInitialFailureShowsNeutralPlaceholder() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onError?("网络不可用")
        await settle()
        XCTAssertEqual(model.menuBarTitle, "--%·--")
        XCTAssertEqual(model.accessibilityStatus, "Codex 额度暂无数据")
        XCTAssertFalse(model.isRefreshing)
    }

    func testTodayTokensRefreshIndependentlyOfQuotaConnection() async {
        let reader = TestTokenReader()
        let model = QuotaViewModel(client: CodexAppServerClient(executableProvider: { nil }), tokenUsageReader: reader)
        let first = expectation(description: "initial local usage")
        var observation = model.$dailyTokenUsage.dropFirst().sink { _ in first.fulfill() }
        model.start()
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(model.todayTokens?.total, 1100)
        XCTAssertEqual(model.todayTokenSummary, "0.11万 tokens")
        XCTAssertEqual(model.todayTokenDetail, "输入 0.1万 · 输出 0.01万")
        XCTAssertTrue(model.todayTokenHelp.contains("缓存 800"))
        observation.cancel()

        let second = expectation(description: "manual refresh local usage")
        observation = model.$dailyTokenUsage.dropFirst().sink { _ in second.fulfill() }
        model.refresh()
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(model.todayTokens?.total, 2200)
        observation.cancel()
        model.stop()
    }

    func testYesterdayTokensAreNotDisplayedAsToday() async {
        let reader = TestTokenReader(dayOffset: -86400)
        let model = QuotaViewModel(client: CodexAppServerClient(executableProvider: { nil }), tokenUsageReader: reader)
        let finished = expectation(description: "read yesterday snapshot")
        let observation = model.$dailyTokenUsage.dropFirst().sink { _ in finished.fulfill() }
        model.start()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertNil(model.todayTokens)
        XCTAssertEqual(model.todayTokenSummary, "--")
        observation.cancel()
        model.stop()
    }

    private func result(window: String) -> [String: Any] {
        ["rateLimits": ["limitId": "codex", window: [
            "usedPercent": 90, "windowDurationMins": 10080, "resetsAt": 1800000000,
        ]]]
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

private final class TestTokenReader: DailyTokenUsageReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int64 = 0
    private let dayOffset: TimeInterval

    init(dayOffset: TimeInterval = 0) { self.dayOffset = dayOffset }

    func read(now: Date, calendar: Calendar) throws -> DailyTokenUsage {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return DailyTokenUsage(day: now.addingTimeInterval(dayOffset), usage: TokenUsage(input: 1000 * count, cachedInput: 800 * count, output: 100 * count))
    }
}
