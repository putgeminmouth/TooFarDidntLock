import CoreWLAN
import Combine

class WifiScanner: ObservableObject, CWEventDelegate {
    let logger = Log.Logger("WifiScanner")

    private let wifi: CWWiFiClient
    let didUpdate = PassthroughSubject<WifiScanner, Never>()

    init() throws {
        wifi = CWWiFiClient.shared()
        try wifi.startMonitoringEvent(with: .bssidDidChange)
        try wifi.startMonitoringEvent(with: .ssidDidChange)
        try wifi.startMonitoringEvent(with: .linkDidChange)
        wifi.delegate = self
    }
    
    func bssidDidChangeForWiFiInterface(withName: String) {
        logger.debug("bssidDidChangeForWiFiInterface: \(withName)")
        update()
    }
    func clientConnectionInterrupted() {
        logger.debug("clientConnectionInterrupted")
        update()
    }
    func clientConnectionInvalidated() {
        logger.debug("clientConnectionInvalidated")
        update()
    }
    func linkDidChangeForWiFiInterface(withName: String) {
        logger.debug("linkDidChangeForWiFiInterface: \(withName)")
        update()
    }
    func ssidDidChangeForWiFiInterface(withName: String) {
        logger.debug("linkDidChangeForWiFiInterface: \(withName)")
        update()
    }
    
    private func update() {
        DispatchQueue.main.async {
            self.didUpdate.send(self)
        }
    }
    
    func activeWiFiInterfaces() -> [CWInterface] {
        let client = CWWiFiClient.shared()
        let active = client.interfaces()?.filter{$0.serviceActive()}
        return active ?? []
    }
    
}
