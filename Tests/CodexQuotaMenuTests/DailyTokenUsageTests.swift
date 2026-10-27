import Foundation
import XCTest
@testable import CodexQuotaMenu

final class DailyTokenUsageTests: XCTestCase {
    private var root: URL!
    private var reader: DailyTokenUsageReader!
    private var calendar: Calendar!
    private let now = ISO8601DateFormatter().date(from: "2026-10-08T04:00:00Z")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        reader = DailyTokenUsageReader(root: root)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testCountsTodaysDeltasInLocalTimeWithoutAddingCacheOrReasoningTwice() throws {
        try write("sessions/a.jsonl", lines: [
            event("2026-10-07T15:59:00Z", input: 100, output: 10),
            event("2026-10-07T16:01:00Z", input: 400, output: 40, cached: 200),
            event("2026-10-08T03:00:00Z", input: 900, output: 80, cached: 500),
            event("2026-10-08T03:01:00Z", input: 900, output: 80, cached: 500),
        ])
        XCTAssertEqual(try read().usage, TokenUsage(input: 800, cachedInput: 500, output: 70))
    }

    func testStructuredRecordsAndMirroredEventsAreCountedOnceAcrossCopies() throws {
        let lines = [
            record("r1", time: "2026-10-08T01:00:00Z", input: 100, output: 20),
            event("2026-10-08T01:00:00Z", input: 100, output: 20),
            record("r2", time: "2026-10-08T01:01:00Z", input: 200, output: 30, cumulativeInput: 300, cumulativeOutput: 50),
            event("2026-10-08T01:01:00Z", input: 300, output: 50),
        ]
        try write("sessions/a.jsonl", lines: lines)
        try write("archived_sessions/copy.jsonl", lines: lines)
        XCTAssertEqual(try read().usage, TokenUsage(input: 300, output: 50))
    }

    func testLegacyEventBeforeStructuredRecordIsNotCountedTwice() throws {
        try write("sessions/a.jsonl", lines: [
            event("2026-10-08T01:00:00Z", input: 100, output: 20),
            record("r1", time: "2026-10-08T01:00:00Z", input: 100, output: 20),
        ])
        XCTAssertEqual(try read().usage.total, 120)
    }

    func testReplayedEarlierStructuredRequestDoesNotRewindBaseline() throws {
        let first = record("r1", time: "2026-10-08T01:00:00Z", input: 100, output: 10)
        let latest = event("2026-10-08T01:01:00Z", input: 300, output: 30)
        try write("sessions/a.jsonl", lines: [
            first, event("2026-10-08T01:00:00Z", input: 100, output: 10),
            record("r2", time: "2026-10-08T01:01:00Z", input: 200, output: 20, cumulativeInput: 300, cumulativeOutput: 30),
            latest, first, latest,
        ])
        XCTAssertEqual(try read().usage.total, 330)
    }

    func testReplayedOlderMirroredEventDoesNotCountAsCounterRestart() throws {
        let first = event("2026-10-08T01:00:00Z", input: 100, output: 10)
        try write("sessions/a.jsonl", lines: [
            record("r1", time: "2026-10-08T01:00:00Z", input: 100, output: 10), first,
            record("r2", time: "2026-10-08T01:01:00Z", input: 200, output: 20, cumulativeInput: 300, cumulativeOutput: 30),
            event("2026-10-08T01:01:00Z", input: 300, output: 30), first,
        ])
        XCTAssertEqual(try read().usage.total, 330)
    }

    func testCounterRestartStillCountsNewRequests() throws {
        try write("sessions/a.jsonl", lines: [
            record("r1", time: "2026-10-08T01:00:00Z", input: 1000, output: 100),
            record("r2", time: "2026-10-08T01:01:00Z", input: 100, output: 10),
            event("2026-10-08T01:02:00Z", input: 1000, output: 100),
        ])
        XCTAssertEqual(try read().usage.total, 2200)
    }

    func testUnchangedDirectoriesAreReusedAndNewNestedSessionIsDiscovered() throws {
        let manager = CountingFileManager()
        reader = DailyTokenUsageReader(root: root, fileManager: manager)
        try write("sessions/a.jsonl", lines: [record("r1", time: "2026-10-08T01:00:00Z", input: 100, output: 10)])
        XCTAssertEqual(try read().usage.total, 110)
        let firstCount = manager.enumerationCount
        XCTAssertGreaterThan(firstCount, 0)
        XCTAssertEqual(try read().usage.total, 110)
        XCTAssertEqual(manager.enumerationCount, firstCount)

        try write("sessions/2026/10/08/new.jsonl", lines: [record("r2", time: "2026-10-08T02:00:00Z", input: 200, output: 20)])
        XCTAssertEqual(try read().usage.total, 330)
        XCTAssertGreaterThan(manager.enumerationCount, firstCount)
        let updatedCount = manager.enumerationCount
        XCTAssertEqual(try read().usage.total, 330)
        XCTAssertEqual(manager.enumerationCount, updatedCount)
    }

    func testArchivingAndRemovingSessionUpdatesCachedSummary() throws {
        let source = try write("sessions/a.jsonl", lines: [record("r1", time: "2026-10-08T01:00:00Z", input: 100, output: 10)])
        XCTAssertEqual(try read().usage.total, 110)
        let archived = root.appendingPathComponent("archived_sessions/a.jsonl")
        try FileManager.default.createDirectory(at: archived.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: archived)
        XCTAssertEqual(try read().usage.total, 110)
        try FileManager.default.removeItem(at: archived)
        XCTAssertEqual(try read().usage.total, 0)
    }

    func testIncludesArchivedSessionsAndIndependentChildUsage() throws {
        try write("sessions/a.jsonl", lines: [record("a", time: "2026-10-08T01:00:00Z", input: 100, output: 20)])
        try write("archived_sessions/b.jsonl", lines: [record("b", time: "2026-10-08T01:00:00Z", input: 200, output: 40)])
        XCTAssertEqual(try read().usage.total, 360)
    }

    func testForkIgnoresCopiedHistoryBeforeCreation() throws {
        try write("sessions/fork.jsonl", lines: [
            ["type": "session_meta", "payload": ["id": "fork", "timestamp": "2026-10-08T02:00:00Z", "forked_from_id": "parent"]],
            event("2026-10-08T01:00:00Z", input: 100, output: 10),
            event("2026-10-08T03:00:00Z", input: 300, output: 30),
        ])
        XCTAssertEqual(try read().usage, TokenUsage(input: 200, output: 20))
    }

    func testFirstEventUsesLastRequestRatherThanInheritedCumulativeTotal() throws {
        var line = event("2026-10-08T01:00:00Z", input: 1000, output: 100)
        var payload = line["payload"] as! [String: Any]
        var info = payload["info"] as! [String: Any]
        info["last_token_usage"] = usage(input: 100, output: 10)
        payload["info"] = info
        line["payload"] = payload
        try write("sessions/a.jsonl", lines: [line])
        XCTAssertEqual(try read().usage.total, 110)
    }

    func testIncrementalReadWaitsForCompleteLineAndDoesNotRepeatPreviousUsage() throws {
        let url = try write("sessions/a.jsonl", lines: [event("2026-10-08T01:00:00Z", input: 100, output: 10)])
        XCTAssertEqual(try read().usage.total, 110)
        let second = try JSONSerialization.data(withJSONObject: event("2026-10-08T02:00:00Z", input: 300, output: 30))
        try append(second.prefix(second.count / 2), to: url)
        XCTAssertEqual(try read().usage.total, 110)
        var remaining = Data(second.suffix(second.count - second.count / 2))
        remaining.append(10)
        try append(remaining, to: url)
        XCTAssertEqual(try read().usage.total, 330)
        XCTAssertEqual(try read().usage.total, 330)
    }

    func testDayRolloverKeepsPreviousDayOnlyAsBaseline() throws {
        let url = try write("sessions/a.jsonl", lines: [
            event("2026-10-08T15:59:00Z", input: 100, output: 10),
            event("2026-10-08T16:01:00Z", input: 300, output: 30),
        ])
        XCTAssertEqual(try read().usage.total, 110)
        let tomorrow = now.addingTimeInterval(86400)
        try FileManager.default.setAttributes([.modificationDate: tomorrow], ofItemAtPath: url.path)
        XCTAssertEqual(try reader.read(now: tomorrow, calendar: calendar).usage.total, 220)
    }

    func testResumedHistoricalFileGetsItsPreviousDayBaseline() throws {
        let url = try write("sessions/a.jsonl", lines: [event("2026-10-07T10:00:00Z", input: 100, output: 10)])
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-86400)], ofItemAtPath: url.path)
        XCTAssertEqual(try read().usage.total, 0)
        var data = try JSONSerialization.data(withJSONObject: event("2026-10-08T01:00:00Z", input: 300, output: 30))
        data.append(10)
        try append(data, to: url)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        XCTAssertEqual(try read().usage.total, 220)
    }

    func testFileReplacementRebuildsCachedState() throws {
        try write("sessions/a.jsonl", lines: [event("2026-10-08T01:00:00Z", input: 1000, output: 100)])
        XCTAssertEqual(try read().usage.total, 1100)
        try write("sessions/a.jsonl", lines: [event("2026-10-08T01:00:00Z", input: 100, output: 10)])
        XCTAssertEqual(try read().usage.total, 110)
    }

    func testMissingRecordsAreUnavailableButEmptySessionsAreZero() throws {
        XCTAssertEqual(try read().usage.total, 0)
        let missing = DailyTokenUsageReader(root: root.appendingPathComponent("missing"))
        XCTAssertThrowsError(try missing.read(now: now, calendar: calendar))
        try write("sessions/a.jsonl", lines: [["type": "event_msg", "timestamp": "bad", "payload": ["type": "token_count", "info": NSNull()]]])
        XCTAssertEqual(try read().usage.total, 0)
    }

    func testLargeConversationLineIsSkippedWithoutLosingFollowingUsage() throws {
        let url = try write("sessions/a.jsonl", lines: [])
        var data = Data(repeating: 65, count: 3 * 1024 * 1024)
        data.append(10)
        data.append(try JSONSerialization.data(withJSONObject: event("2026-10-08T01:00:00Z", input: 100, output: 10)))
        data.append(10)
        try append(data, to: url)
        XCTAssertEqual(try read().usage.total, 110)
    }

    func testDisplayFormatsShortAndExactCounts() {
        XCTAssertEqual(TokenUsageFormatter.compact(0), "0万")
        XCTAssertEqual(TokenUsageFormatter.compact(999), "0.1万")
        XCTAssertEqual(TokenUsageFormatter.compact(10000), "1万")
        XCTAssertEqual(TokenUsageFormatter.compact(12345), "1.23万")
        XCTAssertEqual(TokenUsageFormatter.compact(12345678), "1234.57万")
        XCTAssertEqual(TokenUsageFormatter.compact(99990000), "9999万")
        XCTAssertTrue(TokenUsageFormatter.compact(99999999).hasSuffix("万"))
        XCTAssertEqual(TokenUsageFormatter.compact(100000000), "1亿")
        XCTAssertEqual(TokenUsageFormatter.compact(123456789), "1.23亿")
        XCTAssertEqual(TokenUsageFormatter.exact(12345678), "12,345,678")
    }

    private func read() throws -> DailyTokenUsage { try reader.read(now: now, calendar: calendar) }

    @discardableResult
    private func write(_ path: String, lines: [[String: Any]]) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for line in lines {
            data.append(try JSONSerialization.data(withJSONObject: line))
            data.append(10)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func usage(input: Int64, output: Int64, cached: Int64 = 0) -> [String: Any] {
        ["input_tokens": input, "output_tokens": output, "cached_input_tokens": cached,
         "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }

    private func event(_ time: String, input: Int64, output: Int64, cached: Int64 = 0) -> [String: Any] {
        let counts = usage(input: input, output: output, cached: cached)
        return ["timestamp": time, "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": counts, "last_token_usage": counts]]]
    }

    private func record(_ id: String, time: String, input: Int64, output: Int64, cumulativeInput: Int64? = nil, cumulativeOutput: Int64? = nil) -> [String: Any] {
        ["timestamp": time, "type": "token_usage_record", "payload": ["response_id": id,
         "usage": usage(input: input, output: output),
         "thread_token_usage": usage(input: cumulativeInput ?? input, output: cumulativeOutput ?? output)]]
    }
}

private final class CountingFileManager: FileManager, @unchecked Sendable {
    private(set) var enumerationCount = 0

    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        enumerationCount += 1
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
