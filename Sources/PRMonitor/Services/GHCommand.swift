import Foundation
import os

protocol GHCommandProtocol: Sendable {
    func resolveBinary() async throws -> URL
    func invalidatePath() async
    func run(arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> GHCommand.RunResult
    func runExpectingSuccess(arguments: [String], stdin: Data?, timeout: TimeInterval) async throws -> Data
}

actor GHCommand: GHCommandProtocol {
    static let shared = GHCommand()

    enum GHError: LocalizedError {
        case ghNotFound
        case timeout(TimeInterval)
        case nonZeroExit(code: Int32, stderr: String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .ghNotFound:
                "GitHub CLI not installed. Install with `brew install gh`, then sign in with `gh auth login`."
            case let .timeout(seconds):
                "GitHub CLI timed out after \(Int(seconds))s."
            case let .nonZeroExit(_, stderr):
                stderr.isEmpty ? "GitHub CLI exited with an error." : "GitHub CLI: \(stderr)"
            case let .launchFailed(message):
                "Failed to launch gh: \(message)"
            }
        }
    }

    struct RunResult {
        let exitCode: Int32
        let stdout: Data
        let stderr: String
    }

    private static let probeOrder: [String] = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    private var cachedPath: URL?

    func resolveBinary() throws -> URL {
        if let cachedPath { return cachedPath }
        let fm = FileManager.default
        for candidate in Self.probeOrder where fm.isExecutableFile(atPath: candidate) {
            let url = URL(fileURLWithPath: candidate)
            cachedPath = url
            return url
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/gh"
                if fm.isExecutableFile(atPath: candidate) {
                    let url = URL(fileURLWithPath: candidate)
                    cachedPath = url
                    return url
                }
            }
        }
        throw GHError.ghNotFound
    }

    func invalidatePath() {
        cachedPath = nil
    }

    func run(arguments: [String], stdin: Data? = nil, timeout: TimeInterval = 30) async throws -> RunResult {
        let binary = try resolveBinary()
        return try await Self.runProcess(binary: binary, arguments: arguments, stdin: stdin, timeout: timeout)
    }

    func runExpectingSuccess(arguments: [String], stdin: Data? = nil, timeout: TimeInterval = 30) async throws -> Data {
        let result = try await run(arguments: arguments, stdin: stdin, timeout: timeout)
        guard result.exitCode == 0 else {
            throw GHError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
    }

    // MARK: - Subprocess execution (nonisolated to allow concurrent runs)

    private static func runProcess(
        binary: URL,
        arguments: [String],
        stdin: Data?,
        timeout: TimeInterval
    ) async throws -> RunResult {
        let env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
            "USER": ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            "LANG": "en_US.UTF-8",
        ]

        let box = ProcessBox()
        let process = box.process
        process.executableURL = binary
        process.arguments = arguments
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe? = stdin != nil ? Pipe() : nil
        if let stdinPipe {
            process.standardInput = stdinPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let stdoutCarrier = DataCarrier()
        let stderrCarrier = DataCarrier()
        let drainGroup = DispatchGroup()

        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutCarrier.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrCarrier.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }

        if let stdin, let stdinPipe {
            let writeHandle = stdinPipe.fileHandleForWriting
            DispatchQueue.global(qos: .utility).async {
                try? writeHandle.write(contentsOf: stdin)
                try? writeHandle.close()
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RunResult, Error>) in
                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    if !Task.isCancelled {
                        box.markTimedOut()
                        box.terminate()
                    }
                }

                process.terminationHandler = { proc in
                    timeoutTask.cancel()
                    drainGroup.wait()
                    let stderrString = String(data: stderrCarrier.data, encoding: .utf8) ?? ""
                    if box.didTimeout {
                        cont.resume(throwing: GHError.timeout(timeout))
                    } else {
                        cont.resume(returning: RunResult(
                            exitCode: proc.terminationStatus,
                            stdout: stdoutCarrier.data,
                            stderr: stderrString
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    timeoutTask.cancel()
                    process.terminationHandler = nil
                    cont.resume(throwing: GHError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

// MARK: - Sendable wrappers

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
    private let timedOut = OSAllocatedUnfairLock(initialState: false)

    func markTimedOut() {
        timedOut.withLock { $0 = true }
    }

    var didTimeout: Bool {
        timedOut.withLock { $0 }
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

private final class DataCarrier: @unchecked Sendable {
    var data = Data()
}
