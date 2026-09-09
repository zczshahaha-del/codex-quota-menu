import XCTest
@testable import CodexQuotaMenu

final class QuotaModelsTests: XCTestCase {
    func testCompactResetUsesCalendarDayDistance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let now = date(2026, 9, 9, 17, 0, calendar: calendar)
        let reset = date(2026, 9, 15, 18, 33, calendar: calendar)

        XCTAssertEqual(
            QuotaFormatter.compactReset(until: reset, now: now, calendar: calendar),
            "6d"
        )
    }

    func testCompactResetFallsBackToHoursOnSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let now = date(2026, 9, 9, 17, 0, calendar: calendar)
        let reset = date(2026, 9, 9, 22, 29, calendar: calendar)

        XCTAssertEqual(
            QuotaFormatter.compactReset(until: reset, now: now, calendar: calendar),
            "6h"
        )
    }

    func testParserReadsMainAndAdditionalBuckets() throws {
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
        XCTAssertEqual(snapshot.additional.first?.name, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(snapshot.additional.first?.windows.count, 2)
        XCTAssertEqual(snapshot.additional.first?.primary?.windowName, "5 小时额度")
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
