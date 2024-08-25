import SwiftUI
import Combine
import Foundation
import CoreLocation
import CoreBluetooth
import OSLog

func rssiDistance(referenceAtOneMeter: Double, current: Double) -> Double {
    let N: Double = 2
    let e: Double = (referenceAtOneMeter - current) / (10*N)
    let distanceInMeters = pow(10, e)
    return Double(distanceInMeters)
}

/*
 Low R, High Q: The filter trusts the measurements more and adjusts quickly, resulting in a more reactive estimate that closely tracks the true state despite the noise in the process.
 High R, Low Q: The filter trusts the predictions more and smooths out the measurement noise, leading to a more stable estimate but potentially lagging behind sudden changes in the true state.
 */
class KalmanFilter {
    var state: Double
    var covariance: Double
    
    var processNoise: Double
    
    var measurementNoise: Double
    
    init(initialState: Double, initialCovariance: Double, processNoise: Double, measurementNoise: Double) {
        self.state = initialState
        self.covariance = initialCovariance
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }
    
    func update(measurement: Double) -> Double {
        // Prediction update
        let predictedState = state
        let predictedCovariance = covariance + processNoise
        
        // Measurement update
        let innovation = measurement - predictedState
        let innovationCovariance = predictedCovariance + measurementNoise
        
        // Kalman gain
        let kalmanGain = predictedCovariance / innovationCovariance
        
        // Update state and covariance
        state = predictedState + kalmanGain * innovation
        covariance = (1 - kalmanGain) * predictedCovariance
        
        return state
    }
}

// defining equality on uuid here can break stuff in swiftui+debouncer......
struct MonitoredPeripheral: Equatable {
    enum ConnectionState {
        case connected
        case reconnecting
        case disconnected
    }
        
    // CBPeripheral.state doesnt update as we'd like; notably disconnect is unreliable
//    let peripheral: CBPeripheral
    let id: UUID
    let name: String?
    let txPower: Double?
    @EquatableIgnore var lastSeenRSSI: Double
    @EquatableIgnore var lastSeenAt: Date
    @EquatableIgnore var connectRetriesRemaining: Int
    @EquatableIgnore var connectionState: ConnectionState
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
        
        if existing == nil {
            logger.debug("Discovered \(peripheral.identifier); name=\(peripheral.name ?? "")")
        }
        
        let now = Date()
        
        // assume update list will never have timedout elements
        cwPeripherals[peripheral.identifier] = peripheral
        let update = MonitoredPeripheral(
            id: peripheral.identifier,
            name: peripheral.name,
            txPower: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Double,
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
    private let bluetoothScanner: BluetoothScanner
    private var cancellable: Cancellable? = nil
    private var monitors = [Monitor]()
    
    init(bluetoothScanner: BluetoothScanner) {
        self.bluetoothScanner = bluetoothScanner
        cancellable = bluetoothScanner.didUpdate.sink { self.onBluetoothScannerUpdate($0) }
    }
    
    func startMonitoring(_ id: UUID) -> Monitored {
        let monitorId = UUID()
        let monitor: Monitor = (
            monitorId: monitorId,
            deviceId: id,
            data: BluetoothMonitorData()
        )
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
//    func data(id: UUID) -> BluetoothMonitorData? {
//        monitors[id]
//    }
    
    func onBluetoothScannerUpdate(_ update: MonitoredPeripheral) {
        func tail(_ arr: [Tuple2<Date, Double>]) -> [Tuple2<Date, Double>] {
            return arr.filter{$0.a.distance(to: Date()) < 60}.suffix(1000)
        }

        for monitorData in monitors.filter{$0.deviceId == update.id}.map{$0.data} {
            if monitorData.smoothingFunc == nil {
                monitorData.smoothingFunc = KalmanFilter(initialState: update.lastSeenRSSI, initialCovariance: 2.01, processNoise: 0.1, measurementNoise: 20.01)
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
    }
    
}
