import CoreWLAN
import Combine

// defining equality on uuid here can break stuff in swiftui+debouncer......
struct MonitoredWifiDevice: Equatable {
    enum ConnectionState {
        case connected
        case reconnecting
        case disconnected
    }

    let bssid: String
    var ssid: String?
    var noiseMeasurement: Double
    var lastSeenRSSI: Double
    var lastSeenAt: Date
    @EquatableIgnore var connectRetriesRemaining: Int
    @EquatableIgnore var connectionState: ConnectionState
}

class WifiScanner: ObservableObject, CWEventDelegate {
    let logger = Log.Logger("WifiScanner")

    private static let runloop = DispatchQueue.global(qos: .background)
    
    private let wifi: CWWiFiClient
    private let timeToLive: TimeInterval
    private var updateTimerCancellable: (any Cancellable)? = nil
    fileprivate var monitored = [String: MonitoredWifiDevice]()
    let didUpdate = PassthroughSubject<[MonitoredWifiDevice], Never>()

    init(timeToLive: TimeInterval) throws {
        wifi = CWWiFiClient.shared()
        self.timeToLive = timeToLive
        
        // wifi networks don't update often, though it can take a few scans
        // to pick up new ones, so we try to balance here
//        updateTimer = Timed(interval: 5, dispatch: WifiScanner.runloop.)
//        updateTimerCancellable = updateTimer.sink{_ in self.onUpdateTimer()}
//        updateTimerCancellable = WifiScanner.runloop.schedule(after: .init(.now()), interval: 1, {self.onUpdateTimer()})

        wifi.delegate = self
        try wifi.startMonitoringEvent(with: .bssidDidChange)
        try wifi.startMonitoringEvent(with: .ssidDidChange)
        try wifi.startMonitoringEvent(with: .linkDidChange)
        startScanning()
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
//            self.didUpdate.send(self)
        }
    }
    
    func onUpdateTimer() {
        let results: [CWNetwork] = (wifi.interfaces() ?? []).flatMap{
            // TODO at least log errors?
            // scan seems to return random slices of what's available
            let cached = (try? Array($0.scanForNetworks(withSSID: nil))) ?? []
            // can't do much without bssid at least
            return cached.filter{$0.bssid != nil}
        }

        let addedNetworks = results.filter{r in !monitored.contains{m in m.key == r.bssid}}
        let changedNetworks = results.filter{r in monitored.contains{m in m.key == r.bssid}}

        let now = Date.now
        
        let addedDevices = addedNetworks.map{ a in
            let device = MonitoredWifiDevice(
                bssid: a.bssid!,
                ssid: a.ssid,
                noiseMeasurement: Double(a.noiseMeasurement),
                lastSeenRSSI: Double(a.rssiValue),
                lastSeenAt: now,
                connectRetriesRemaining: 0,
                connectionState: .disconnected)
            return device
        }
        
        let changedDevices = changedNetworks.compactMap{ c in
            let original = monitored.first{$0.key == c.bssid}!.value
            var current = original
            current.ssid = c.ssid ?? current.ssid // if it got lost, better to keep previous info
            current.noiseMeasurement = Double(c.noiseMeasurement)
            current.lastSeenRSSI = Double(c.rssiValue)
            current.lastSeenAt = now
            
            if current != original {
                return .some(current)
            } else {
                return nil
            }
        }
        
        let updates = (addedDevices + changedDevices)
            .filter{$0.lastSeenAt.distance(to: now) < timeToLive}
            .reduce([:]) { acc, next in
                acc.mergeRight([next.bssid: next])
            }

        let monitoredUpdate = monitored.mergeRight(updates)

        let equal = monitored == monitoredUpdate
        
        monitored = monitoredUpdate
        
        if !equal {
            DispatchQueue.main.async {
                self.didUpdate.send(Array(updates.values))
            }
        }
    }
    
    func startScanning() {
        logger.log("startScanning")
        updateTimerCancellable = WifiScanner.runloop.schedule(after: .init(.now()), interval: 1, {self.onUpdateTimer()})
    }

    func activeWiFiInterfaces() -> [CWInterface] {
        let client = CWWiFiClient.shared()
        let active = client.interfaces()?.filter{$0.serviceActive()}
        return active ?? []
    }
    
}

class WifiMonitor: ObservableObject {
    typealias Monitored = (data: WifiMonitorData, cancellable: Cancellable)
    private typealias Monitor = (monitorId: UUID, deviceId: String, data: WifiMonitorData)
    
    static func updateMonitorData(monitorData: WifiMonitorData, update: MonitoredWifiDevice) {
        func tail(_ arr: [Tuple2<Date, Double>]) -> [Tuple2<Date, Double>] {
            return arr.filter{$0.a.distance(to: Date()) < 60}.suffix(1000)
        }

        let smoothingFunc = monitorData.smoothingFunc!

        let rssiSmoothedSample = smoothingFunc.update(measurement: monitorData.rssiRawSamples.last?.b ?? 0)
        
        monitorData.rssiRawSamples = tail(monitorData.rssiRawSamples + [Tuple2(update.lastSeenAt, update.lastSeenRSSI)])
        assert(monitorData.rssiRawSamples.count < 2 || zip(monitorData.rssiRawSamples, monitorData.rssiRawSamples.dropFirst()).allSatisfy { current, next in current.a <= next.a }, "\( zip(monitorData.rssiRawSamples, monitorData.rssiRawSamples.dropFirst()).map{"\($0.0.a);\($0.1.a)"})")
        
        monitorData.rssiSmoothedSamples = tail(monitorData.rssiSmoothedSamples + [Tuple2(update.lastSeenAt, rssiSmoothedSample)])
        assert(monitorData.rssiSmoothedSamples.count < 2 || zip(monitorData.rssiSmoothedSamples, monitorData.rssiSmoothedSamples.dropFirst()).allSatisfy { current, next in current.a <= next.a })
        
        if let referenceRSSIAtOneMeter = monitorData.referenceRSSIAtOneMeter,
           var distanceSmoothedSamples = monitorData.distanceSmoothedSamples {
            distanceSmoothedSamples = tail(distanceSmoothedSamples + [Tuple2(update.lastSeenAt, rssiDistance(referenceAtOneMeter: referenceRSSIAtOneMeter, current: rssiSmoothedSample))])
            assert(distanceSmoothedSamples.count < 2 || zip(distanceSmoothedSamples, distanceSmoothedSamples.dropFirst()).allSatisfy { current, next in current.a <= next.a })
            monitorData.distanceSmoothedSamples = distanceSmoothedSamples
        }
    }

    static func recalculate(monitorData: WifiMonitorData) {
        let smoothingFunc = monitorData.smoothingFunc!

        monitorData.rssiSmoothedSamples = monitorData.rssiRawSamples.map{Tuple2($0.a, smoothingFunc.update(measurement: $0.b))}
        
        if let referenceRSSIAtOneMeter = monitorData.referenceRSSIAtOneMeter {
            monitorData.distanceSmoothedSamples = monitorData.rssiSmoothedSamples.map{Tuple2($0.a, rssiDistance(referenceAtOneMeter: referenceRSSIAtOneMeter, current: $0.b))}
        }
    }
    
    static func initSmoothingFunc(initialRSSI: Double, processNoise: Double = 0.1) -> KalmanFilter {
        return KalmanFilter(initialState: initialRSSI, initialCovariance: 2.01, processNoise: processNoise, measurementNoise: 20.01)
    }
    
    private let wifiScanner: WifiScanner
    private var cancellable: Cancellable? = nil
    private var monitors = [Monitor]()
    
    init(wifiScanner: WifiScanner) {
        self.wifiScanner = wifiScanner
        cancellable = wifiScanner.didUpdate.sink { self.onWifiScannerUpdate($0) }
    }
    
    func startMonitoring(_ bssid: String, referenceRSSIAtOneMeter: Double? = nil) -> Monitored {
        let monitorId = UUID()
        let monitor: Monitor = (
            monitorId: monitorId,
            deviceId: bssid,
            data: WifiMonitorData()
        )
        if let referenceRSSIAtOneMeter = referenceRSSIAtOneMeter {
            monitor.data.distanceSmoothedSamples = []
            monitor.data.referenceRSSIAtOneMeter = referenceRSSIAtOneMeter
        }
        let cancellable = AnyCancellable {
            self.monitors.removeAll{$0.monitorId == monitorId}
        }
        monitors.append(monitor)
        return (data: monitor.data, cancellable: cancellable)
    }

//    func stopMonitoring(_ id: UUID) {
//        monitors.removeAll{$0.monitorId == }
//    }
//
    func dataFor(deviceId: String) -> [WifiMonitorData] {
        monitors.filter{$0.deviceId == deviceId}.map{$0.data}
    }
    
    func onWifiScannerUpdate(_ updates: [MonitoredWifiDevice]) {
        func tail(_ arr: [Tuple2<Date, Double>]) -> [Tuple2<Date, Double>] {
            return arr.filter{$0.a.distance(to: Date()) < 60}.suffix(1000)
        }

        for update in updates {
            for monitorData in monitors.filter{$0.deviceId == update.bssid}.map{$0.data} {
                if monitorData.smoothingFunc == nil {
                    monitorData.smoothingFunc = WifiMonitor.initSmoothingFunc(initialRSSI: update.lastSeenRSSI)
                }
                
                WifiMonitor.updateMonitorData(monitorData: monitorData, update: update)
            }
        }
    }
    
}
