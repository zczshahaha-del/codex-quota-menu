import Foundation
import Darwin

struct TokenUsage: Equatable, Sendable {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var output: Int64 = 0

    var total: Int64 { input + output }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: lhs.input + rhs.input, cachedInput: lhs.cachedInput + rhs.cachedInput, output: lhs.output + rhs.output)
    }

    func subtracting(_ previous: Self) -> Self {
        Self(input: max(0, input - previous.input), cachedInput: max(0, cachedInput - previous.cachedInput), output: max(0, output - previous.output))
    }

    init(input: Int64 = 0, cachedInput: Int64 = 0, output: Int64 = 0) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
    }

    init?(json: [String: Any]?) {
        guard let json,
              let input = Self.count(json["input_tokens"]),
              let output = Self.count(json["output_tokens"])
        else { return nil }
        self.init(input: input, cachedInput: Self.count(json["cached_input_tokens"]) ?? 0, output: output)
    }

    private static func count(_ value: Any?) -> Int64? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue >= 0, value.doubleValue < Double(Int64.max),
              value.doubleValue.rounded(.towardZero) == value.doubleValue
        else { return nil }
        return value.int64Value
    }
}

struct DailyTokenUsage: Equatable, Sendable {
    let day: Date
    let usage: TokenUsage
}

protocol DailyTokenUsageReading: Sendable {
    func read(now: Date, calendar: Calendar) throws -> DailyTokenUsage
}

/// Reads only usage metadata from local rollouts. Cache stays in memory; conversation text is never stored.
final class DailyTokenUsageReader: DailyTokenUsageReading, @unchecked Sendable {
    private struct FileState {
        var identity: String
        var modifiedAt: Date
        var offset: UInt64 = 0
        var pending = Data()
        var skippingLongLine = false
        var sessionID: String
        var createdAt: Date?
        var previous: TokenUsage?
        var previousAt: Date?
        var recordedTotals: Set<Int64> = []
        var events: [String: TokenUsage] = [:]
        var fallbackKeys: [Int64: String] = [:]
        var revision = 0

        mutating func setEvent(_ usage: TokenUsage?, for key: String) {
            guard events[key] != usage else { return }
            events[key] = usage
            revision += 1
        }

        mutating func updateBaseline(_ usage: TokenUsage, at timestamp: Date, mayReset: Bool) {
            guard timestamp >= (previousAt ?? .distantPast),
                  previous == nil || usage.total >= previous!.total || mayReset else { return }
            if let previous, usage.total < previous.total {
                recordedTotals.removeAll(keepingCapacity: true)
            }
            previous = usage
            previousAt = timestamp
        }
    }

    private struct DirectoryState {
        let identity: String
        let modifiedAt: Date
        let directories: [URL]
        let files: [URL]
    }

    private let root: URL
    private let fileManager: FileManager
    // Protects the incremental cache and date formatters across callers.
    private let lock = NSLock()
    private var day: DateInterval?
    private var files: [URL: FileState] = [:]
    private var directories: [URL: DirectoryState] = [:]
    private var cachedUsage: TokenUsage?
    private let dateParser = ISO8601DateFormatter()
    private let plainDateParser = ISO8601DateFormatter()

    init(root: URL = DailyTokenUsageReader.codexHome(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    static func codexHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    func read(now: Date = Date(), calendar: Calendar = .current) throws -> DailyTokenUsage {
        lock.lock()
        defer { lock.unlock() }
        guard let interval = calendar.dateInterval(of: .day, for: now) else {
            throw CocoaError(.fileReadUnknown)
        }
        if day != interval {
            files.removeAll()
            cachedUsage = nil
            day = interval
        }

        let urls = try rolloutFiles()
        var needsAggregation = cachedUsage == nil || files.count != urls.count || urls.contains { files[$0] == nil }
        var current: [URL: FileState] = [:]
        for url in urls {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
            let identity = "\(attributes[.systemNumber] ?? 0):\(attributes[.systemFileNumber] ?? 0)"
            var state = files[url] ?? FileState(identity: identity, modifiedAt: modifiedAt, sessionID: url.lastPathComponent)
            if state.identity != identity || size < state.offset || (size == state.offset && modifiedAt != state.modifiedAt) {
                state = FileState(identity: identity, modifiedAt: modifiedAt, sessionID: url.lastPathComponent)
                needsAggregation = true
            }
            // Untouched historical files cannot contain today's newly written usage.
            // Keep offset zero so a resumed old session gets its baseline scanned later.
            if size > state.offset && modifiedAt >= interval.start {
                try append(url: url, state: &state, interval: interval)
            }
            state.modifiedAt = modifiedAt
            if files[url]?.revision != state.revision { needsAggregation = true }
            current[url] = state
        }
        files = current

        // Response IDs also deduplicate copied/forked and active/archived rollouts.
        if needsAggregation {
            var events: [String: TokenUsage] = [:]
            for state in files.values {
                for (key, usage) in state.events {
                    if let existing = events[key], existing.total >= usage.total { continue }
                    events[key] = usage
                }
            }
            cachedUsage = events.values.reduce(TokenUsage(), +)
        }
        return DailyTokenUsage(day: interval.start, usage: cachedUsage ?? TokenUsage())
    }

    private func rolloutFiles() throws -> [URL] {
        var result: [URL] = []
        var foundDirectory = false
        var visited: Set<URL> = []

        func collect(_ directory: URL) throws {
            visited.insert(directory)
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            let identity = "\(attributes[.systemNumber] ?? 0):\(attributes[.systemFileNumber] ?? 0)"
            let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
            let listing: DirectoryState
            if let cached = directories[directory], cached.identity == identity, cached.modifiedAt == modifiedAt {
                listing = cached
            } else {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
                let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                var subdirectories: [URL] = []
                var rollouts: [URL] = []
                for url in entries {
                    let values = try url.resourceValues(forKeys: keys)
                    guard values.isSymbolicLink != true else { continue }
                    if values.isDirectory == true { subdirectories.append(url) }
                    else if values.isRegularFile == true && url.pathExtension == "jsonl" { rollouts.append(url) }
                }
                listing = DirectoryState(identity: identity, modifiedAt: modifiedAt, directories: subdirectories, files: rollouts)
                directories[directory] = listing
            }
            result.append(contentsOf: listing.files)
            for child in listing.directories { try collect(child) }
        }

        for name in ["sessions", "archived_sessions"] {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            foundDirectory = true
            try collect(directory)
        }
        directories = directories.filter { visited.contains($0.key) }
        guard foundDirectory else { throw CocoaError(.fileNoSuchFile) }
        return result
    }

    private func append(url: URL, state: inout FileState, interval: DateInterval) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: state.offset)
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            state.offset += UInt64(chunk.count)
            chunk.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var start = 0
                while let pointer = memchr(base.advanced(by: start), 10, chunk.count - start) {
                    let newline = base.distance(to: UnsafeRawPointer(pointer))
                    if !state.skippingLongLine {
                        if state.pending.isEmpty {
                            consume(chunk[start..<newline], state: &state, interval: interval)
                        } else {
                            state.pending.append(chunk[start..<newline])
                            consume(state.pending, state: &state, interval: interval)
                        }
                    }
                    state.pending.removeAll(keepingCapacity: false)
                    state.skippingLongLine = false
                    start = newline + 1
                }
                if !state.skippingLongLine {
                    state.pending.append(chunk[start...])
                    // Usage lines are small; avoid retaining large conversation/tool-result lines.
                    if state.pending.count > 2 * 1024 * 1024 {
                        state.pending.removeAll(keepingCapacity: false)
                        state.skippingLongLine = true
                    }
                }
            }
        }
    }

    private func consume(_ line: Data, state: inout FileState, interval: DateInterval) {
        guard line.range(of: Data("\"token_count\"".utf8)) != nil
                || line.range(of: Data("\"token_usage_record\"".utf8)) != nil
                || line.range(of: Data("\"session_meta\"".utf8)) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return }

        if type == "session_meta" {
            state.sessionID = payload["id"] as? String ?? state.sessionID
            state.createdAt = date(payload["timestamp"] as? String)
            return
        }
        guard let timestamp = date(object["timestamp"] as? String) else { return }
        let belongsToToday = timestamp >= interval.start && timestamp < interval.end
            && timestamp >= (state.createdAt ?? .distantPast)

        if type == "token_usage_record",
           let responseID = payload["response_id"] as? String, !responseID.isEmpty,
           let usage = TokenUsage(json: payload["usage"] as? [String: Any]),
           let cumulative = TokenUsage(json: payload["thread_token_usage"] as? [String: Any]) {
            let key = "response:\(responseID)"
            if let fallback = state.fallbackKeys.removeValue(forKey: cumulative.total) {
                state.setEvent(nil, for: fallback)
            }
            state.updateBaseline(cumulative, at: timestamp, mayReset: state.events[key] == nil && cumulative == usage)
            if belongsToToday {
                state.recordedTotals.insert(cumulative.total)
                if state.events[key] == nil || usage.total > state.events[key]!.total { state.setEvent(usage, for: key) }
            }
            return
        }

        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let cumulative = TokenUsage(json: info["total_token_usage"] as? [String: Any])
        else { return }
        let key = "legacy:\(state.sessionID):\(timestamp.timeIntervalSince1970):\(cumulative.total)"
        guard !state.recordedTotals.contains(cumulative.total), state.events[key] == nil,
              timestamp >= (state.previousAt ?? .distantPast) else { return }
        let last = TokenUsage(json: info["last_token_usage"] as? [String: Any])
        let delta: TokenUsage
        if let previous = state.previous {
            if cumulative.total == previous.total { return }
            if cumulative.total < previous.total {
                // A restarted counter is counted only when this really is its first request.
                guard cumulative == last else { return }
                state.recordedTotals.removeAll(keepingCapacity: true)
                delta = cumulative
            } else {
                delta = cumulative.subtracting(previous)
            }
        } else {
            // A resumed/forked file may begin with inherited cumulative usage.
            delta = last ?? cumulative
        }
        state.previous = cumulative
        state.previousAt = timestamp
        guard belongsToToday, delta.total > 0 else { return }
        state.setEvent(delta, for: key)
        state.fallbackKeys[cumulative.total] = key
    }

    private func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return dateParser.date(from: text) ?? plainDateParser.date(from: text)
    }
}

enum TokenUsageFormatter {
    static func compact(_ count: Int64) -> String {
        let usesYi = count >= 100_000_000
        let divisor: Double = usesYi ? 100_000_000 : 10_000
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let value = formatter.string(from: NSNumber(value: Double(count) / divisor)) ?? "0"
        return "\(value)\(usesYi ? "亿" : "万")"
    }

    static func exact(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }
}
