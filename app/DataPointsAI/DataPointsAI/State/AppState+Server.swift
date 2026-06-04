import Foundation

// MARK: - Server Management
extension AppState {

    /// Connect to the hosted backend. (The app no longer runs an embedded local
    /// server — it talks to the shared Railway backend so featuring, reading
    /// state, etc. are visible to every user.)
    func startServer() async {
        serverError = nil
        await checkServerHealth()
        guard serverRunning else {
            // Unreachable or missing/invalid API key — surfaced via serverStatus.
            // The user can set the backend API key in Settings, then reconnect.
            if case .unhealthy = serverStatus {} else {
                serverStatus = .unhealthy(error: "Can't reach the backend. Check the API key in Settings → AI.")
            }
            return
        }
        startHealthChecks()
        await refresh()
        await archiveOldArticlesIfEnabled()
        try? await refreshFeeds()
        backgroundRefreshService.configure(with: self)
    }

    func stopServer() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        backgroundRefreshService.invalidate()
        serverRunning = false
        serverStatus = .unknown
    }

    /// Re-create the API client (picking up any backend API key change) and
    /// reconnect to the hosted backend.
    func restartServer() async {
        serverStatus = .checking
        apiClient = APIClient()
        await startServer()
    }

    /// Save a new backend API key and reconnect.
    func updateBackendAPIKey(_ key: String) async throws {
        try KeychainService.shared.saveBackendAPIKey(key)
        await restartServer()
    }

    func checkServerHealth() async {
        serverStatus = .checking
        do {
            let status = try await apiClient.healthCheck()
            if status.isHealthy {
                serverStatus = .healthy(summarizationEnabled: status.summarizationEnabled)
                serverRunning = true
                serverError = nil
            } else {
                serverStatus = .unhealthy(error: "Server reported unhealthy status")
            }
        } catch {
            serverStatus = .unhealthy(error: error.localizedDescription)
        }
    }

    internal func startHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await checkServerHealth()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}
