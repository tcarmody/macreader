import Foundation
import Combine

/// Manages the Python backend process lifecycle
@MainActor
class PythonServer: ObservableObject {
    @Published var isRunning = false
    @Published var error: String?

    private var process: Process?
    private let port: Int
    private let apiClient: APIClient

    init(port: Int = 5005) {
        self.port = port
        self.apiClient = APIClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
    }

    func start() async throws {
        guard !isRunning else { return }

        // Always kill any existing server to ensure we run with latest code
        // This prevents stale code issues when the backend is modified
        if await isPortInUse() {
            print("🔄 Killing existing server on port \(port) to ensure fresh code...")
            await killProcessOnPort()
            // Give the OS time to release the port
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Find Python and project paths
        guard let projectPath = findProjectPath() else {
            throw ServerError.projectNotFound
        }

        let venvPython = projectPath.appendingPathComponent("rss_venv/bin/python")
        let backendDir = projectPath.appendingPathComponent("backend")

        guard FileManager.default.fileExists(atPath: venvPython.path) else {
            throw ServerError.pythonNotFound(venvPython.path)
        }

        guard FileManager.default.fileExists(atPath: backendDir.appendingPathComponent("server.py").path) else {
            throw ServerError.serverNotFound(backendDir.path)
        }

        // Start the process from the project root, using backend.server:app
        let process = Process()
        process.executableURL = venvPython
        process.arguments = [
            "-m", "uvicorn",
            "backend.server:app",
            "--host", "127.0.0.1",
            "--port", String(port)
        ]
        process.currentDirectoryURL = projectPath  // Run from project root, not backend dir

        // Set up environment with API keys from Keychain
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"

        // Inject API keys from Keychain
        let apiKeys = KeychainService.shared.getEnvironmentVariables()
        for (key, value) in apiKeys {
            env[key] = value
        }

        if apiKeys.isEmpty {
            print("⚠️ No API keys configured in Keychain")
        } else {
            print("🔑 Loaded \(apiKeys.count) API key(s) from Keychain")
        }

        process.environment = env

        print("🐍 Starting Python server...")
        print("🐍 Python: \(venvPython.path)")
        print("🐍 Project dir: \(projectPath.path)")
        print("🐍 Arguments: \(process.arguments ?? [])")

        // Capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📝 Python: \(output)", terminator: "")
            }
        }

        do {
            try process.run()
            self.process = process

            // Wait for server to be ready
            try await waitForServer()
            isRunning = true
            error = nil

        } catch {
            self.error = "Failed to start server: \(error.localizedDescription)"
            throw error
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }

    /// Restart the server with fresh code
    func restart() async throws {
        print("🔄 Restarting Python server...")
        stop()
        // Kill any lingering processes
        await killProcessOnPort()
        try await Task.sleep(nanoseconds: 500_000_000)
        try await start()
    }

    /// Check if an existing server is already running and healthy
    private func isExistingServerHealthy() async -> Bool {
        do {
            let status = try await apiClient.healthCheck()
            return status.isHealthy
        } catch {
            return false
        }
    }

    /// Check if something is using the port (even if not responding to health checks)
    private func isPortInUse() async -> Bool {
        let portNumber = port
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["-ti", ":\(portNumber)"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: !output.isEmpty)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Kill any process using the configured port
    private func killProcessOnPort() async {
        let portNumber = port
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let findProcess = Process()
                findProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                findProcess.arguments = ["-ti", ":\(portNumber)"]

                let pipe = Pipe()
                findProcess.standardOutput = pipe
                findProcess.standardError = FileHandle.nullDevice

                do {
                    try findProcess.run()
                    findProcess.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty {
                        let pids = output.components(separatedBy: .newlines)
                        for pid in pids where !pid.isEmpty {
                            print("🔪 Killing process on port \(portNumber): PID \(pid)")
                            let killProcess = Process()
                            killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
                            killProcess.arguments = ["-9", pid]
                            try? killProcess.run()
                            killProcess.waitUntilExit()
                        }
                    }
                } catch {
                    print("⚠️ Could not kill process on port: \(error)")
                }
                continuation.resume()
            }
        }
    }

    private func waitForServer(timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                let status = try await apiClient.healthCheck()
                if status.isHealthy {
                    return
                }
            } catch {
                // Server not ready yet
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        throw ServerError.timeout(timeout)
    }

    private func findProjectPath() -> URL? {
        // Method 1: Direct known path (most reliable when running from Xcode)
        let knownPath = URL(fileURLWithPath: "/Users/tim/Workspace/macreader")
        if isValidProjectPath(knownPath) {
            return knownPath
        }

        // Method 2: Check relative to current working directory
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if isValidProjectPath(cwd) {
            return cwd
        }

        // Method 3: Check parent of current directory
        let parent = cwd.deletingLastPathComponent()
        if isValidProjectPath(parent) {
            return parent
        }

        // Method 4: When running from Xcode, look relative to bundle
        if let bundlePath = Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent() {
            if isValidProjectPath(bundlePath) {
                return bundlePath
            }
        }

        // Method 5: Look in user's home directory under common workspace names
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let possibleNames = ["macreader", "rss-reader", "RSSReader", "DataPointsAI"]
        let possibleParents = ["Workspace", "Projects", "Developer", "Code", "src"]

        for parent in possibleParents {
            for name in possibleNames {
                let path = homeDir.appendingPathComponent(parent).appendingPathComponent(name)
                if isValidProjectPath(path) {
                    return path
                }
            }
        }

        // Method 6: Check directly in home directory
        for name in possibleNames {
            let path = homeDir.appendingPathComponent(name)
            if isValidProjectPath(path) {
                return path
            }
        }

        return nil
    }

    private func isValidProjectPath(_ path: URL) -> Bool {
        let serverPath = path.appendingPathComponent("backend/server.py")
        return FileManager.default.fileExists(atPath: serverPath.path)
    }

    deinit {
        process?.terminate()
    }
}

/// Errors from server management
enum ServerError: Error, LocalizedError, Sendable {
    case projectNotFound
    case pythonNotFound(String)
    case serverNotFound(String)
    case timeout(TimeInterval)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Could not find project directory. Make sure you're running from the project root."
        case .pythonNotFound(let path):
            return "Python virtual environment not found at \(path). Run 'make setup' first."
        case .serverNotFound(let path):
            return "Server script not found at \(path)"
        case .timeout(let seconds):
            return "Server did not start within \(Int(seconds)) seconds"
        case .startFailed(let message):
            return "Failed to start server: \(message)"
        }
    }
}
