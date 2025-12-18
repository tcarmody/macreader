import Foundation

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

        // Start the process
        let process = Process()
        process.executableURL = venvPython
        process.arguments = [
            "-m", "uvicorn",
            "server:app",
            "--host", "127.0.0.1",
            "--port", String(port)
        ]
        process.currentDirectoryURL = backendDir

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

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
        // Method 1: Check relative to current working directory
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if isValidProjectPath(cwd) {
            return cwd
        }

        // Method 2: Check parent of current directory
        let parent = cwd.deletingLastPathComponent()
        if isValidProjectPath(parent) {
            return parent
        }

        // Method 3: When running from Xcode, look relative to bundle
        if let bundlePath = Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent() {
            if isValidProjectPath(bundlePath) {
                return bundlePath
            }
        }

        // Method 4: Look in user's home directory under common workspace names
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let possibleNames = ["macreader", "rss-reader", "RSSReader"]
        let possibleParents = ["Workspace", "Projects", "Developer", "Code", "src"]

        for parent in possibleParents {
            for name in possibleNames {
                let path = homeDir.appendingPathComponent(parent).appendingPathComponent(name)
                if isValidProjectPath(path) {
                    return path
                }
            }
        }

        // Method 5: Check directly in home directory
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
enum ServerError: Error, LocalizedError {
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
