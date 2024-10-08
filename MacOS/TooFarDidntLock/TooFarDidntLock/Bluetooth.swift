import SwiftUI
import Combine
import Foundation
import CoreLocation
import CoreBluetooth
import OSLog

struct MonitoredPeripheral {
    enum ConnectionState {
        case connected
        case reconnecting
        case disconnected
    }
        
    let id: UUID
    let name: String?
    // call it transmitPower not txPower as the latter sometimes means "referencePowerAtOneMeter"...
    let transmitPower: Double?
    var lastSeenRSSI: Double
    var lastSeenAt: Date
    var connectRetriesRemaining: Int
    var connectionState: ConnectionState
}

class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    let logger = Log.Logger("BluetoothScanner")

    fileprivate var centralManager: CBCentralManager!
    private var timeToLive: TimeInterval
    fileprivate var cwPeripherals = [UUID: CBPeripheral]()
    fileprivate var monitoredPeripherals = [UUID: MonitoredPeripheral]()
    fileprivate var connections = [UUID: BluetoothActiveConnectionDelegate]()
    let didUpdate = PassthroughSubject<MonitoredPeripheral, Never>()
    let didDisconnect = PassthroughSubject<UUID, Never>()

    var peripherals: [MonitoredPeripheral] {
        Array(monitoredPeripherals.values)
    }
    
    init(timeToLive: TimeInterval) {
        self.timeToLive = timeToLive
        
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
        
    func startScanning() {
        logger.log("startScanning")
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func stopScanning() {
        logger.log("stopScanning")
        centralManager.stopScan()
    }
    
    func connect(maintainConnectionTo uuid: UUID) -> Void? {
        guard var device = monitoredPeripherals[uuid],
              let peripheral = cwPeripherals[uuid]
        else { return nil }
        // i don't think this is required but it gives more immediate feedback and avoids logs
        guard !connections.keys.contains(uuid)
        else { return () }
        // could not get CBConnectPeripheralOptionEnableAutoReconnect working
        connections[uuid] = BluetoothActiveConnectionDelegate(scanner: self, identifier: uuid)
        device.connectRetriesRemaining = 1
        monitoredPeripherals[uuid] = device
        centralManager.connect(peripheral)
        return ()
    }

    func disconnect(uuid: UUID) {
        connections.removeValue(forKey: uuid)?.close()
        if var device = monitoredPeripherals[uuid],
           let peripheral = cwPeripherals[uuid] {
            device.connectRetriesRemaining = 0
            monitoredPeripherals[uuid] = device
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            logger.error("Bluetooth is not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let existing = monitoredPeripherals[peripheral.identifier]
        
        // only log named peripherals because it gets pretty spammy
        if existing == nil && peripheral.name != nil {
            logger.debug("Discovered \(peripheral.identifier); name=\(peripheral.name ?? "")")
        }
        
        let now = Date()
        
        // assume update list will never have timedout elements
        cwPeripherals[peripheral.identifier] = peripheral
        let update = MonitoredPeripheral(
            id: peripheral.identifier,
            name: peripheral.name,
            transmitPower: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Double,
            lastSeenRSSI: RSSI.doubleValue,
            lastSeenAt: now,
            connectRetriesRemaining: existing?.connectRetriesRemaining ?? 0,
            connectionState: existing?.connectionState ?? .disconnected
        )
        
        monitoredPeripherals = monitoredPeripherals.merging([update.id: update]){(_,u) in u}.filter{$0.value.lastSeenAt.distance(to: now) < timeToLive}
        cwPeripherals = cwPeripherals.filter{monitoredPeripherals[$0.key] != nil}
        didUpdate.send(update)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let conn = connections.first(where: {$0.key == peripheral.identifier}) {
            conn.value.centralManager(central, didConnect: peripheral)
        } else {
            logger.info("Connected to \(peripheral.identifier); name=\(peripheral.name ?? "")")

        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        if let conn = connections.first(where: {$0.key == peripheral.identifier}) {
            conn.value.centralManager(central, didFailToConnect: peripheral, error: error)
        } else {
            logger.info("Failed to connect to \(peripheral.identifier), error=\(error)")

        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        if let conn = connections.first(where: {$0.key == peripheral.identifier}) {
            conn.value.centralManager(central, didDisconnectPeripheral: peripheral, timestamp: timestamp, isReconnecting: isReconnecting, error: error)
        } else {
            // code=7 : The specified device has disconnected from us.
            logger.info("Disconnected from \(peripheral.identifier), isReconnecting=\(isReconnecting), error=\(error)")
        }
    }
}

class BluetoothActiveConnectionDelegate: Equatable {
    static func == (lhs: BluetoothActiveConnectionDelegate, rhs: BluetoothActiveConnectionDelegate) -> Bool {
        return lhs === rhs
    }
    
    let logger = Log.Logger("BluetoothActiveConnectionDelegate")

    private weak var scanner: BluetoothScanner?
    private var identifier: UUID
    // Given the intention of maintaining an active connection,
    // We use a fairly agressive timeout.
    // TODO: bump the config up a few levels, possible to the user
    // CBCentralManager doesn't have an explicit timeout, but it will
    // eventually give up without notification.
    // We don't rely on the scanner's TTL since that serves a more general purpose.
    private let timeout = Timed(interval: 10)
    private var timeoutCancellable: AnyCancellable?
    let didDisconnect = PassthroughSubject<UUID, Never>()

    init(scanner: BluetoothScanner, identifier: UUID) {
        self.scanner = scanner
        self.identifier = identifier
        self.timeoutCancellable = timeout.sink(receiveValue: timeoutFired)
    }
    
    func close() {
        if var device = scanner?.monitoredPeripherals[identifier] {
            device.connectionState = .disconnected
            scanner?.monitoredPeripherals[device.id] = device
            scanner?.didUpdate.send(device)
        }

        timeoutCancellable?.cancel()
        timeoutCancellable = nil
        scanner?.connections.removeValue(forKey: identifier)
        scanner?.disconnect(uuid: identifier)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard var device = scanner?.monitoredPeripherals[peripheral.identifier]
        else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        logger.info("Connected to \(peripheral.identifier)")
        device.connectRetriesRemaining = 1
        device.connectionState = .connected
        timeout.stop()
        scanner?.monitoredPeripherals[device.id] = device
        assert(scanner?.connections[device.id] == self)
        scanner?.didUpdate.send(device)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        logger.info("Failed to connect to \(peripheral.identifier), error=\(error)")
        handleDisconnect(peripheral: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        // code=7 : "The specified device has disconnected from us"
        // code=13 : "Peer failed to respond to ATT value indication" (seems to happen on "soft" re-enable of bluetooth on iOS)
        logger.info("Disconnected from \(peripheral.identifier), isReconnecting=\(isReconnecting), error=\(error)")
        handleDisconnect(peripheral: peripheral)
    }
    
    private func handleDisconnect(peripheral: CBPeripheral) {
        let device = scanner?.monitoredPeripherals[peripheral.identifier]
        if device?.connectRetriesRemaining ?? 0 > 0 {
            if var device = device {
                device.connectRetriesRemaining -= 1
                device.connectionState = .reconnecting
                scanner?.monitoredPeripherals[device.id] = device
                scanner?.didUpdate.send(device)
            }
            timeout.restart()
            logger.info("Reconnecting to \(peripheral.identifier), retriesRemaining=\(device?.connectRetriesRemaining ?? -1)")
            scanner?.centralManager.connect(peripheral)
        } else {
            self.close()
            self.didDisconnect.send(peripheral.identifier)
        }
    }
    
    private func timeoutFired(date: Date) {
        logger.info("Timed out to \(self.identifier)")
        self.close()
        self.didDisconnect.send(identifier)
    }
}

class BluetoothMonitor: ObservableObject {
    typealias Monitored = (data: BluetoothMonitorData, cancellable: Cancellable)
    private typealias Monitor = (monitorId: UUID, deviceId: UUID, data: BluetoothMonitorData)
    
    static func updateMonitorData(monitorData: BluetoothMonitorData, update: MonitoredPeripheral) {
        func tail(_ arr: [DataSample]) -> [DataSample] {
            return arr.filter{$0.date.distance(to: Date()) < signalDataRetentionPeriod}.suffix(1000)
        }

        let smoothingFunc = monitorData.smoothingFunc!

        let rssiSmoothedSample = smoothingFunc.update(measurement: update.lastSeenRSSI)
        
        monitorData.rssiRawSamples = tail(monitorData.rssiRawSamples + [DataSample(update.lastSeenAt, update.lastSeenRSSI)])
        assert(monitorData.rssiRawSamples.count < 2 || zip(monitorData.rssiRawSamples, monitorData.rssiRawSamples.dropFirst()).allSatisfy { current, next in current.date <= next.date }, "\( zip(monitorData.rssiRawSamples, monitorData.rssiRawSamples.dropFirst()).map{"\($0.0.date.timeIntervalSince1970);\($0.1.date.timeIntervalSince1970)"})")
        
        monitorData.rssiSmoothedSamples = tail(monitorData.rssiSmoothedSamples + [DataSample(update.lastSeenAt, rssiSmoothedSample)])
        assert(monitorData.rssiSmoothedSamples.count < 2 || zip(monitorData.rssiSmoothedSamples, monitorData.rssiSmoothedSamples.dropFirst()).allSatisfy { current, next in current.date <= next.date })
        
        if let referenceRSSIAtOneMeter = monitorData.referenceRSSIAtOneMeter,
           var distanceSmoothedSamples = monitorData.distanceSmoothedSamples,
           let environmentalPathLoss = monitorData.environmentalPathLoss {
            distanceSmoothedSamples = tail(distanceSmoothedSamples + [DataSample(update.lastSeenAt, rssiDistance(referenceAtOneMeter: referenceRSSIAtOneMeter, environmentalPathLoss: environmentalPathLoss, current: rssiSmoothedSample))])
            assert(distanceSmoothedSamples.count < 2 || zip(distanceSmoothedSamples, distanceSmoothedSamples.dropFirst()).allSatisfy { current, next in current.date <= next.date })
            monitorData.distanceSmoothedSamples = distanceSmoothedSamples
        }
    }

    static func recalculate(monitorData: BluetoothMonitorData) {
        let smoothingFunc = monitorData.smoothingFunc!

        monitorData.rssiSmoothedSamples = monitorData.rssiRawSamples.map{DataSample($0.date, smoothingFunc.update(measurement: $0.value))}
        
        if let referenceRSSIAtOneMeter = monitorData.referenceRSSIAtOneMeter,
           let environmentalPathLoss = monitorData.environmentalPathLoss {
            monitorData.distanceSmoothedSamples = monitorData.rssiSmoothedSamples.map{DataSample($0.date, rssiDistance(referenceAtOneMeter: referenceRSSIAtOneMeter, environmentalPathLoss: environmentalPathLoss, current: $0.value))}
        }
    }
    
    private let bluetoothScanner: BluetoothScanner
    private var cancellable: Cancellable? = nil
    private var monitors = [Monitor]()
    
    init(bluetoothScanner: BluetoothScanner) {
        self.bluetoothScanner = bluetoothScanner
        cancellable = bluetoothScanner.didUpdate.sink { self.onBluetoothScannerUpdate($0) }
    }
    
    func startMonitoring(
        _ id: UUID,
        smoothing: (referenceRSSIAtOneMeter: Double, environmentalPathLoss: Double, processNoise: Double, measureNoise: Double)? = nil) -> Monitored {
            startMonitoring(id, smoothing: smoothing.map{s in {_ in s}})
        }
    func startMonitoring(
        _ id: UUID,
        smoothing: ((BluetoothMonitorData) -> (referenceRSSIAtOneMeter: Double, environmentalPathLoss: Double, processNoise: Double, measureNoise: Double))? = nil) -> Monitored {
            let data = BluetoothMonitorData()
            let monitorId = UUID()
            let monitor: Monitor = (
                monitorId: monitorId,
                deviceId: id,
                data: data
            )
            if let smoothing = smoothing.map{$0(data)} {
                monitor.data.distanceSmoothedSamples = []
                monitor.data.smoothingFunc = KalmanFilter(
                    initialState: nil,
                    initialCovariance: 0.01,
                    processVariance: smoothing.processNoise,
                    measureVariance: smoothing.measureNoise)
                monitor.data.referenceRSSIAtOneMeter = smoothing.referenceRSSIAtOneMeter
                monitor.data.environmentalPathLoss = smoothing.environmentalPathLoss
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
    func dataFor(deviceId: UUID) -> [BluetoothMonitorData] {
        monitors.filter{$0.deviceId == deviceId}.map{$0.data}
    }
    
    func onBluetoothScannerUpdate(_ update: MonitoredPeripheral) {
        func tail(_ arr: [Tuple2<Date, Double>]) -> [Tuple2<Date, Double>] {
            return arr.filter{$0.a.distance(to: Date()) < signalDataRetentionPeriod}.suffix(1000)
        }

        for monitorData in monitors.filter{$0.deviceId == update.id}.map{$0.data} {
            assert(monitorData.smoothingFunc != nil)
            
            BluetoothMonitor.updateMonitorData(monitorData: monitorData, update: update)
        }
    }
    
}
