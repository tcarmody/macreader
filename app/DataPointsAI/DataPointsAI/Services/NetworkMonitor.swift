import Foundation
import Network
import Combine

/// Monitors network connectivity status using NWPathMonitor
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    /// Current network connectivity status
    @Published private(set) var isConnected: Bool = true

    /// Whether the connection is expensive (cellular, hotspot)
    @Published private(set) var isExpensive: Bool = false

    /// Whether the connection is constrained (Low Data Mode)
    @Published private(set) var isConstrained: Bool = false

    /// The type of network interface
    @Published private(set) var connectionType: ConnectionType = .unknown

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.datapointsai.networkmonitor")

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case wiredEthernet = "Ethernet"
        case other = "Other"
        case unknown = "Unknown"
    }

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updateStatus(path: path)
            }
        }
        monitor.start(queue: queue)
    }

    private func updateStatus(path: NWPath) {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else if path.usesInterfaceType(.other) {
            connectionType = .other
        } else {
            connectionType = .unknown
        }
    }

    deinit {
        monitor.cancel()
    }
}
