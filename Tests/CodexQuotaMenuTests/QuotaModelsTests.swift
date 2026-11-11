import XCTest
@testable import CodexQuotaMenu

final class QuotaModelsTests: XCTestCase {
    func testCompactResetUsesElapsedDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let now = date(2026, 9, 9, 17, 0, calendar: calendar)
        let reset = date(2026, 9, 15, 18, 33, calendar: calendar)

        XCTAssertEqual(
            QuotaFormatter.compactReset(until: reset, now: now),
            "6d"
        )
    }

    func testCompactResetFallsBackToHoursOnSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let now = date(2026, 9, 9, 17, 0, calendar: calendar)
        let reset = date(2026, 9, 9, 22, 29, calendar: calendar)

        XCTAssertEqual(
            QuotaFormatter.compactReset(until: reset, now: now),
            "6h"
        )
    }

    func testResetDaysCountFull24HoursInsteadOfCalendarDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = date(2026, 11, 11, 16, 0, calendar: calendar)
        let reset = date(2026, 11, 14, 1, 0, calendar: calendar)
        XCTAssertEqual(QuotaFormatter.compactReset(until: reset, now: now), "2d")
        XCTAssertEqual(QuotaFormatter.compactReset(until: now.addingTimeInterval(23 * 3600), now: now), "23h")
        XCTAssertEqual(QuotaFormatter.compactReset(until: now.addingTimeInterval(48 * 3600), now: now), "2d")
        XCTAssertEqual(QuotaFormatter.compactReset(until: now.addingTimeInterval(24 * 3600), now: now), "1d")
        XCTAssertEqual(QuotaFormatter.compactReset(until: now, now: now), "now")
    }

    func testParserSelectsMainBucketWithUnrelatedModelsPresent() throws {
        let result: [String: Any] = [
            "rateLimits": [
                "limitId": "codex",
                "primary": [
                    "usedPercent": 23,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_789_468_386,
                ],
                "planType": "pro",
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "primary": [
                        "usedPercent": 23,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_789_468_386,
                    ],
                    "planType": "pro",
                ],
                "codex_bengalfox": [
                    "limitId": "codex_bengalfox",
                    "limitName": "GPT-5.3-Codex-Spark",
                    "primary": [
                        "usedPercent": 0,
                        "windowDurationMins": 300,
                        "resetsAt": 1_788_964_140,
                    ],
                    "secondary": [
                        "usedPercent": 0,
                        "windowDurationMins": 10_080,
                        "resetsAt": 1_789_550_940,
                    ],
                ],
            ],
        ]

        let snapshot = try XCTUnwrap(RateLimitParser.parse(result: result))
        XCTAssertEqual(snapshot.main.primary?.remainingPercent, 77)
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.main.primary?.windowName, "7 天额度")
    }

    func testParserKeepsLegacyAndSecondaryWindowFallback() throws {
        let window: [String: Any] = ["usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1789468386]
        let snapshot = try XCTUnwrap(RateLimitParser.parse(result: ["rateLimits": ["secondary": window, "planType": "pro"]]))
        XCTAssertNil(snapshot.main.primary)
        XCTAssertEqual(snapshot.main.secondary?.remainingPercent, 58)
        XCTAssertEqual(snapshot.planType, "pro")
    }

    func testInvalidMainBucketFallsBackToLegacy() throws {
        let window: [String: Any] = ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1789468386]
        let snapshot = try XCTUnwrap(RateLimitParser.parse(result: [
            "rateLimitsByLimitId": ["codex": ["primary": [:]]], "rateLimits": ["primary": window],
        ]))
        XCTAssertEqual(snapshot.main.primary?.remainingPercent, 90)
    }

    func testAlternateMapKeyCanStillIdentifyMainBucket() throws {
        let window: [String: Any] = ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1789468386]
        let snapshot = try XCTUnwrap(RateLimitParser.parse(result: ["rateLimitsByLimitId": ["alias": ["limitId": "codex", "primary": window]]]))
        XCTAssertEqual(snapshot.main.primary?.remainingPercent, 90)
    }

    func testMissingMainBucketUsesAvailableFallback() throws {
        let window: [String: Any] = ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": 1789468386]
        let snapshot = try XCTUnwrap(RateLimitParser.parse(result: ["rateLimitsByLimitId": ["other": ["secondary": window]]]))
        XCTAssertEqual(snapshot.main.secondary?.remainingPercent, 90)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
