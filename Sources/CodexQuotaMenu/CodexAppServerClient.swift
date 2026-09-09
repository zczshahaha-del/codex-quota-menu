import Foundation

final class CodexAppServerClient {
    var onRateLimits: (([String: Any]) -> Void)?
    var onError: ((String) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private let queue = DispatchQueue(label: "codex-quota.app-server")
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var initialized = false
    private var initializeRequestID: Int?
    private var rateLimitRequestIDs = Set<Int>()
    private var nextRequestID = 1
    private var stopping = false

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.process == nil {
                self.startLocked()
            } else if self.initialized {
                self.requestRateLimitsLocked()
            }
        }
    }

    func stop() {
        queue.sync {
            stopping = true
            outputHandle?.readabilityHandler = nil
            errorHandle?.readabilityHandler = nil
            inputHandle?.closeFile()
            if let process, process.isRunning {
                process.terminate()
            }
            clearProcessLocked()
        }
    }

    private func startLocked() {
        guard process == nil else { return }
        stopping = false

        guard let codexURL = Self.findCodexExecutable() else {
            reportError("找不到 Codex。请先安装或打开 ChatGPT/Codex 应用。")
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = codexURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        errorHandle = errorPipe.fileHandleForReading
        outputBuffer.removeAll(keepingCapacity: true)
        errorBuffer.removeAll(keepingCapacity: true)
        initialized = false

        outputHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.consumeOutputLocked(data)
            }
        }

        errorHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.errorBuffer.append(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.queue.async {
                guard let self else { return }
                let shouldReport = !self.stopping && terminatedProcess.terminationStatus != 0
                let stderr = String(data: self.errorBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.clearProcessLocked()
                self.onConnectionChanged?(false)

                if shouldReport {
                    self.reportError(stderr?.isEmpty == false ? stderr! : "Codex 后台连接已停止。")
                }
            }
        }

        do {
            try process.run()
            self.process = process
            onConnectionChanged?(true)
            sendInitializeLocked()
        } catch {
            clearProcessLocked()
            reportError("无法启动 Codex：\(error.localizedDescription)")
        }
    }

    private func sendInitializeLocked() {
        let requestID = allocateRequestIDLocked()
        initializeRequestID = requestID
        sendLocked([
            "method": "initialize",
            "id": requestID,
            "params": [
                "clientInfo": [
                    "name": "codex_quota_menu",
                    "title": "Codex Quota Menu",
                    "version": "0.3.1",
                ],
            ],
        ])
    }

    private func requestRateLimitsLocked() {
        guard initialized else { return }
        let requestID = allocateRequestIDLocked()
        rateLimitRequestIDs.insert(requestID)
        sendLocked([
            "method": "account/rateLimits/read",
            "id": requestID,
        ])
    }

    private func allocateRequestIDLocked() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func sendLocked(_ object: [String: Any]) {
        guard let inputHandle else { return }

        do {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try inputHandle.write(contentsOf: data)
        } catch {
            reportError("发送 Codex 请求失败：\(error.localizedDescription)")
        }
    }

    private func consumeOutputLocked(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])

        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }

            handleMessageLocked(object)
        }
    }

    private func handleMessageLocked(_ message: [String: Any]) {
        if let id = Self.integer(message["id"]), id == initializeRequestID {
            initializeRequestID = nil
            if let error = Self.errorMessage(from: message) {
                reportError(error)
                return
            }

            initialized = true
            sendLocked(["method": "initialized", "params": [:]])
            requestRateLimitsLocked()
            return
        }

        if let id = Self.integer(message["id"]), rateLimitRequestIDs.remove(id) != nil {
            if let result = message["result"] as? [String: Any] {
                onRateLimits?(result)
            } else if let error = Self.errorMessage(from: message) {
                reportError(error)
            } else {
                reportError("Codex 返回了无法识别的额度数据。")
            }
            return
        }

        if message["method"] as? String == "account/rateLimits/updated" {
            requestRateLimitsLocked()
        }
    }

    private func clearProcessLocked() {
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
        process = nil
        initialized = false
        initializeRequestID = nil
        rateLimitRequestIDs.removeAll()
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
    }

    private func reportError(_ message: String) {
        onError?(message)
    }

    private static func findCodexExecutable() -> URL? {
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["CODEX_BINARY"], !override.isEmpty {
            candidates.append(override)
        }

        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path
                .split(separator: ":")
                .map { String($0) + "/codex" })
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func errorMessage(from message: [String: Any]) -> String? {
        guard let error = message["error"] as? [String: Any] else { return nil }
        return error["message"] as? String ?? "Codex 请求失败。"
    }
}
