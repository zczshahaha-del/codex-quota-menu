import XCTest
@testable import CodexQuotaMenu

@MainActor
final class QuotaViewModelTests: XCTestCase {
    func testReadFailureMarksCachedValueAsStale() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onConnectionChanged?(true)
        client.onRateLimits?(result(window: "primary"))
        await settle()
        XCTAssertTrue(model.menuBarTitle.hasPrefix("10%"))

        client.onError?("网络不可用")
        await settle()
        XCTAssertTrue(model.menuBarTitle.contains("⚠︎"))
        XCTAssertTrue(model.accessibilityStatus.contains("过期"))
        XCTAssertEqual(model.snapshot?.main.primary?.remainingPercent, 10)

        client.onRateLimits?(result(window: "primary"))
        await settle()
        XCTAssertFalse(model.menuBarTitle.contains("⚠︎"))
        XCTAssertNil(model.errorMessage)
    }

    func testDisconnectedSnapshotIsMarkedStale() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onConnectionChanged?(true)
        client.onRateLimits?(result(window: "primary"))
        await settle()
        client.onConnectionChanged?(false)
        await settle()
        XCTAssertTrue(model.menuBarTitle.contains("⚠︎"))
    }

    func testSecondaryOnlySnapshotIsDisplayed() async {
        let client = CodexAppServerClient()
        let model = QuotaViewModel(client: client)
        client.onConnectionChanged?(true)
        client.onRateLimits?(result(window: "secondary"))
        await settle()
        XCTAssertTrue(model.menuBarTitle.hasPrefix("10%"))
        XCTAssertTrue(model.accessibilityStatus.contains("10%"))
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.errorMessage)
    }

    func testRetryKeepsStaleWarningUntilSuccessfulResponse() async {
        let client = CodexAppServerClient(executableProvider: { nil })
        let model = QuotaViewModel(client: client)
        client.onConnectionChanged?(true)
        client.onRateLimits?(result(window: "primary"))
        await settle()
        client.onError?("网络不可用")
        await settle()
        model.refresh()
        XCTAssertTrue(model.isRefreshing)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.errorMessage, "网络不可用")
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
