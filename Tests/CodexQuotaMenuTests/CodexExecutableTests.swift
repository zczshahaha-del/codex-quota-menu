import XCTest
@testable import CodexQuotaMenu

final class CodexExecutableTests: XCTestCase {
    func testFindsBundledCodexWithoutShellPath() {
        for app in ["ChatGPT", "Codex"] {
            let path = "/Applications/\(app).app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
            XCTAssertEqual(resolve(available: [path]), path)
        }
    }

    func testKeepsLegacyInstallLocations() {
        for path in [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ] {
            XCTAssertEqual(resolve(available: [path]), path)
        }
    }

    func testExplicitOverrideTakesPriority() {
        let override = "/custom/codex"
        XCTAssertEqual(resolve(
            environment: ["CODEX_BINARY": override],
            available: [override, "/Applications/ChatGPT.app/Contents/Resources/codex"]
        ), override)
    }

    func testInvalidOverrideFallsBackToExecutableOnPath() {
        XCTAssertEqual(resolve(
            environment: ["CODEX_BINARY": "/missing/codex", "PATH": "/missing:/custom/bin"],
            available: ["/custom/bin/codex"]
        ), "/custom/bin/codex")
    }

    func testReturnsNilWhenNoExecutableExists() {
        XCTAssertNil(resolve(available: []))
    }

    private func resolve(environment: [String: String] = [:], available: Set<String>) -> String? {
        CodexAppServerClient.findCodexExecutable(
            environment: environment,
            isExecutable: { available.contains($0) }
        )?.path
    }
}
