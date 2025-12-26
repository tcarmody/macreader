import Foundation

// MARK: - Server Management
extension AppState {

    func startServer() async {
        serverError = nil
        do {
            try await server.start()
            serverRunning = true
            startHealthChecks()
            await refresh()
            await archiveOldArticlesIfEnabled()
            try? await refreshFeeds()
        } catch {
            serverError = error.localizedDescription
            serverRunning = false
            serverStatus = .unhealthy(error: error.localizedDescription)
        }
    }

    func stopServer() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        server.stop()
        serverRunning = false
        serverStatus = .unknown
    }

    func restartServer() async {
        serverStatus = .checking
        do {
            try await server.restart()
            serverRunning = true
            await checkServerHealth()
        } catch {
            serverStatus = .unhealthy(error: error.localizedDescription)
            serverError = error.localizedDescription
        }
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
