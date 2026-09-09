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

struct QuotaBucket: Equatable, Identifiable {
    let id: String
    let name: String
    let primary: QuotaWindow?
    let secondary: QuotaWindow?

    var windows: [QuotaWindow] {
        [primary, secondary].compactMap { $0 }
    }
}

struct QuotaSnapshot: Equatable {
    let main: QuotaBucket
    let additional: [QuotaBucket]
    let planType: String?
    let fetchedAt: Date

    var allBuckets: [QuotaBucket] {
        [main] + additional
    }
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
    static func parse(result: [String: Any], fetchedAt: Date = Date()) -> QuotaSnapshot? {
        let legacy = result["rateLimits"] as? [String: Any]
        let bucketMap = result["rateLimitsByLimitId"] as? [String: Any]

        var parsed: [QuotaBucket] = []
        if let bucketMap {
            for (key, rawValue) in bucketMap {
                guard let rawBucket = rawValue as? [String: Any],
                      let bucket = parseBucket(key: key, object: rawBucket)
                else { continue }
                parsed.append(bucket)
            }
        }

        let main: QuotaBucket?
        if let codex = parsed.first(where: { $0.id == "codex" }) {
            main = codex
        } else if let legacy {
            main = parseBucket(key: "codex", object: legacy)
        } else {
            main = parsed.first
        }

        guard let main, !main.windows.isEmpty else { return nil }

        let planType = (legacy?["planType"] as? String)
            ?? (bucketMap?["codex"] as? [String: Any])?["planType"] as? String

        let additional = parsed
            .filter { $0.id != main.id && !$0.windows.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return QuotaSnapshot(
            main: main,
            additional: additional,
            planType: planType,
            fetchedAt: fetchedAt
        )
    }

    private static func parseBucket(key: String, object: [String: Any]) -> QuotaBucket? {
        let id = object["limitId"] as? String ?? key
        let rawName = object["limitName"] as? String
        let name: String

        if let rawName, !rawName.isEmpty {
            name = rawName
        } else if id == "codex" {
            name = "Codex"
        } else {
            name = id
        }

        let primary = parseWindow(object["primary"] as? [String: Any])
        let secondary = parseWindow(object["secondary"] as? [String: Any])

        guard primary != nil || secondary != nil else { return nil }
        return QuotaBucket(id: id, name: name, primary: primary, secondary: secondary)
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
