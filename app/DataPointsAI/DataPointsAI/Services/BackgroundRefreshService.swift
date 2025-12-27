import Foundation
import AppKit
import Combine

/// Background refresh interval options (similar to NetNewsWire)
enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case manually = 0
    case every10Minutes = 600
    case every30Minutes = 1800
    case everyHour = 3600
    case every2Hours = 7200
    case every4Hours = 14400
    case every8Hours = 28800

    var id: Int { rawValue }

    var inSeconds: TimeInterval {
        TimeInterval(rawValue)
    }

    var label: String {
        switch self {
        case .manually: return "Manually"
        case .every10Minutes: return "Every 10 Minutes"
        case .every30Minutes: return "Every 30 Minutes"
        case .everyHour: return "Every Hour"
        case .every2Hours: return "Every 2 Hours"
        case .every4Hours: return "Every 4 Hours"
        case .every8Hours: return "Every 8 Hours"
        }
    }
}

/// Service that manages automatic background refresh of feeds
/// Inspired by NetNewsWire's AccountRefreshTimer implementation
@MainActor
final class BackgroundRefreshService: ObservableObject {

    static let shared = BackgroundRefreshService()

    // MARK: - Published Properties

    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastRefreshDate: Date?

    // MARK: - Private Properties

    private var timer: Timer?
    private var refreshInterval: RefreshInterval = .every30Minutes
    private weak var appState: AppState?

    // Track app lifecycle
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadSettings()
        setupNotifications()
    }

    // MARK: - Public Methods

    /// Configure the service with the app state
    func configure(with appState: AppState) {
        self.appState = appState
        update()
    }

    /// Update the timer based on current settings
    func update() {
        invalidate()

        guard refreshInterval != .manually else {
            return
        }

        let interval = refreshInterval.inSeconds
        let lastRefresh = lastRefreshDate ?? Date.distantPast
        var fireDate = lastRefresh.addingTimeInterval(interval)

        // If the fire date is in the past, schedule for now + interval
        if fireDate < Date() {
            fireDate = Date().addingTimeInterval(interval)
        }

        scheduleTimer(fireDate: fireDate)
    }

    /// Set a new refresh interval
    func setRefreshInterval(_ interval: RefreshInterval) {
        refreshInterval = interval
        saveSettings()
        update()
    }

    /// Get the current refresh interval
    func getRefreshInterval() -> RefreshInterval {
        refreshInterval
    }

    /// Force a refresh now (called when waking from sleep or on timer fire)
    func timedRefresh() {
        guard !isRefreshing else { return }

        Task {
            await performRefresh()
        }
    }

    /// Invalidate and stop the timer
    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    /// Handle timers that should have fired while app was inactive
    func fireOldTimer() {
        guard refreshInterval != .manually else { return }

        let lastRefresh = lastRefreshDate ?? Date.distantPast
        let fireDate = lastRefresh.addingTimeInterval(refreshInterval.inSeconds)

        if fireDate < Date() {
            timedRefresh()
        }
    }

    // MARK: - Private Methods

    private func scheduleTimer(fireDate: Date) {
        timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.timedRefresh()
            }
        }

        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func performRefresh() async {
        guard let appState = appState else { return }

        isRefreshing = true

        do {
            try await appState.refreshFeeds()
            lastRefreshDate = Date()
            saveSettings()
        } catch {
            print("Background refresh failed: \(error.localizedDescription)")
        }

        isRefreshing = false

        // Schedule next refresh
        update()
    }

    private func setupNotifications() {
        // Handle system wake from sleep
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.fireOldTimer()
                }
            }
            .store(in: &cancellables)

        // Handle app becoming active
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.fireOldTimer()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    private func loadSettings() {
        if let rawValue = UserDefaults.standard.object(forKey: "backgroundRefreshInterval") as? Int,
           let interval = RefreshInterval(rawValue: rawValue) {
            refreshInterval = interval
        }

        if let lastRefresh = UserDefaults.standard.object(forKey: "lastBackgroundRefresh") as? Date {
            lastRefreshDate = lastRefresh
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(refreshInterval.rawValue, forKey: "backgroundRefreshInterval")
        if let lastRefreshDate = lastRefreshDate {
            UserDefaults.standard.set(lastRefreshDate, forKey: "lastBackgroundRefresh")
        }
    }
}
