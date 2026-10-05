import XCTest
@testable import CodexQuotaMenu

final class CodexAppServerClientTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testRefreshRecoversAfterInitializationError() throws {
        let executable = try fixture("""
        case "$line" in
          *'"initialize"'*)
            if [ ! -e "$0.started" ]; then
              touch "$0.started"
              printf '{"id":%s,"error":{"message":"initialization failed"}}\\n' "$id"
            else
              printf '{"id":%s,"result":{}}\\n' "$id"
            fi ;;
          *rateLimits*) reply "$id" 90 ;;
        esac
        """)
        let client = CodexAppServerClient(executableProvider: { executable })
        defer { client.stop() }
        let failed = expectation(description: "initialization error")
        let recovered = expectation(description: "fresh quota after reconnect")
        client.onError = { _ in failed.fulfill() }
        client.onRateLimits = { _ in recovered.fulfill() }
        client.start()
        wait(for: [failed], timeout: 2)
        client.refresh()
        wait(for: [recovered], timeout: 2)
    }

    func testOverlappingRefreshDoesNotSendAnotherRequest() throws {
        let executable = try fixture("""
        case "$line" in
          *'"initialize"'*) printf '{"id":%s,"result":{}}\\n' "$id" ;;
          *rateLimits*)
            printf 'read\\n' >> "$0.requests"
            (sleep 0.3; reply "$id" 89) & ;;
        esac
        """)
        let client = CodexAppServerClient(executableProvider: { executable })
        defer { client.stop() }
        let connected = expectation(description: "connected")
        let quota = expectation(description: "quota")
        quota.assertForOverFulfill = false
        client.onConnectionChanged = { if $0 { connected.fulfill() } }
        client.onRateLimits = { _ in quota.fulfill() }
        client.start()
        wait(for: [connected], timeout: 2)
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: executable.path + ".requests"), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        client.refresh()
        client.refresh()
        wait(for: [quota], timeout: 2)
        let requests = try String(contentsOfFile: executable.path + ".requests", encoding: .utf8)
        XCTAssertEqual(requests.split(separator: "\n").count, 1)
    }

    func testTimeoutAllowsRetryForInitializationAndQuotaRead() throws {
        for method in ["initialize", "rateLimits"] {
            let executable = try fixture("""
            case "$line" in
              *'"initialize"'*)
                if [ '\(method)' = 'initialize' ] && [ ! -e "$0.started" ]; then
                  touch "$0.started"
                else
                  printf '{"id":%s,"result":{}}\\n' "$id"
                fi ;;
              *rateLimits*)
                if [ '\(method)' = 'rateLimits' ] && [ ! -e "$0.started" ]; then
                  touch "$0.started"
                else
                  reply "$id" 90
                fi ;;
            esac
            """)
            let client = CodexAppServerClient(executableProvider: { executable }, requestTimeout: 0.5)
            let timedOut = expectation(description: "\(method) timeout")
            let recovered = expectation(description: "\(method) retry")
            client.onError = { message in
                XCTAssertTrue(message.contains("超时"))
                timedOut.fulfill()
            }
            client.onRateLimits = { _ in recovered.fulfill() }
            client.start()
            wait(for: [timedOut], timeout: 3)
            client.refresh()
            wait(for: [recovered], timeout: 3)
            client.stop()
        }
    }

    func testLateDuplicateDoesNotOverwriteNewerRead() throws {
        let executable = try fixture("""
        case "$line" in
          *'"initialize"'*) printf '{"id":%s,"result":{}}\\n' "$id" ;;
          *rateLimits*)
            if [ -z "$first_id" ]; then
              first_id=$id
              reply "$id" 89
            else
              reply "$id" 90
              reply "$first_id" 89
            fi ;;
        esac
        """)
        let client = CodexAppServerClient(executableProvider: { executable })
        defer { client.stop() }
        let latest = expectation(description: "only latest read accepted")
        let extra = expectation(description: "no stale response delivered")
        extra.isInverted = true
        var count = 0
        client.onRateLimits = { result in
            count += 1
            if count == 1 {
                client.refresh()
            } else if count == 2 {
                XCTAssertEqual(RateLimitParser.parse(result: result)?.main.primary?.remainingPercent, 10)
                latest.fulfill()
            } else {
                extra.fulfill()
            }
        }
        client.start()
        wait(for: [latest], timeout: 2)
        wait(for: [extra], timeout: 0.3)
    }

    private func fixture(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("fake-codex-" + UUID().uuidString)
        let script = """
        #!/bin/sh
        reply() {
          printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":%s,"windowDurationMins":10080,"resetsAt":1800000000}}}}\\n' "$1" "$2"
        }
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\\1/')
          \(body)
        done
        wait
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
