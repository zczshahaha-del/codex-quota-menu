import Foundation

struct QuotaWindow: Equatable {
    let usedPercent: Double
    let windowDurationMinutes: Int
    let resetsAt: Date

    var remainingPercent: Int {
        let remaining = Int((100 - usedPercent).rounded())
        return min(100, max(0, remaining))
    }

    var windowName: String {
        if windowDurationMinutes >= 1_440 {
            let days = max(1, windowDurationMinutes / 1_440)
            return "\(days) 天额度"
        }

        if windowDurationMinutes >= 60 {
            let hours = max(1, windowDurationMinutes / 60)
            return "\(hours) 小时额度"
        }

        return "\(windowDurationMinutes) 分钟额度"
    }
}

struct QuotaBucket: Equatable {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
}

struct QuotaSnapshot: Equatable {
    let main: QuotaBucket
    let planType: String?
}

enum QuotaFormatter {
    static func compactReset(
        until resetDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let seconds = resetDate.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }

        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: resetDate)
        let calendarDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        if calendarDays > 0 {
            return "\(calendarDays)d"
        }

        if seconds >= 3_600 {
            return "\(max(1, Int(ceil(seconds / 3_600))))h"
        }

        return "\(max(1, Int(ceil(seconds / 60))))m"
    }

    static func resetDetail(until resetDate: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: resetDate)
    }
}

enum RateLimitParser {
    static func parse(result: [String: Any]) -> QuotaSnapshot? {
        let legacy = result["rateLimits"] as? [String: Any]
        let bucketMap = result["rateLimitsByLimitId"] as? [String: Any]

        // Select only the displayed bucket; do not build unused model lists.
        let codex = bucketMap?["codex"] as? [String: Any]
            ?? bucketMap?.values.lazy.compactMap { $0 as? [String: Any] }.first { $0["limitId"] as? String == "codex" }
        for candidate in [codex, legacy] {
            if let object = candidate, let main = parseBucket(object) {
                return QuotaSnapshot(main: main, planType: legacy?["planType"] as? String ?? object["planType"] as? String)
            }
        }
        // Keep a deterministic fallback when the main bucket is unavailable.
        for key in bucketMap?.keys.sorted() ?? [] {
            if let object = bucketMap?[key] as? [String: Any], let main = parseBucket(object) {
                return QuotaSnapshot(main: main, planType: object["planType"] as? String)
            }
        }
        return nil
    }

    private static func parseBucket(_ object: [String: Any]) -> QuotaBucket? {
        let primary = parseWindow(object["primary"] as? [String: Any])
        let secondary = parseWindow(object["secondary"] as? [String: Any])

        guard primary != nil || secondary != nil else { return nil }
        return QuotaBucket(primary: primary, secondary: secondary)
    }

    private static func parseWindow(_ object: [String: Any]?) -> QuotaWindow? {
        guard let object,
              let usedPercent = number(object["usedPercent"]),
              let duration = number(object["windowDurationMins"]),
              let resetTimestamp = number(object["resetsAt"])
        else { return nil }

        return QuotaWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: Int(duration),
            resetsAt: Date(timeIntervalSince1970: resetTimestamp)
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }
}
