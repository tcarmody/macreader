import Foundation

// MARK: - Server Management
extension AppState {

    /// Connect to the hosted backend. (The app no longer runs an embedded local
    /// server — it talks to the shared Railway backend so featuring, reading
    /// state, etc. are visible to every user.)
    func startServer() async {
        serverError = nil
        guard await connect() else { return }
        await loadInitialData()
    }

    /// Health-check the hosted backend and start periodic checks. Returns whether
    /// the connection is healthy. Fast — does not refresh feeds/articles.
    @discardableResult
    private func connect() async -> Bool {
        await checkServerHealth()
        guard serverRunning else {
            // Unreachable or missing/invalid API key — surfaced via serverStatus.
            // The user can set the backend API key in Settings, then reconnect.
            if case .unhealthy = serverStatus {} else {
                serverStatus = .unhealthy(error: "Can't reach the backend. Check the API key in Settings → AI.")
            }
            return false
        }
        startHealthChecks()
        return true
    }

    /// Load feeds/articles/settings and refresh. Potentially slow (server-side
    /// feed refresh), so callers that gate UI on completion should not await it.
    private func loadInitialData() async {
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
    /// reconnect. The (potentially long) data refresh runs in the background so
    /// callers — e.g. a settings sheet — return promptly and don't hang.
    func restartServer() async {
        serverStatus = .checking
        apiClient = APIClient()
        guard await connect() else { return }
        Task { await self.loadInitialData() }
    }

    /// Persist a new backend API key and rebuild the API client to use it.
    /// Does NOT reconnect/refresh — call `startServer()` (e.g. in a detached
    /// Task) afterwards so the UI never blocks on a long feed refresh.
    func updateBackendAPIKey(_ key: String) throws {
        try KeychainService.shared.saveBackendAPIKey(key)
        apiClient = APIClient()
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
