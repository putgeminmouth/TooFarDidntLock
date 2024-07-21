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


struct MonitoredPeripheral: Hashable, Equatable {
    static func == (lhs: MonitoredPeripheral, rhs: MonitoredPeripheral) -> Bool {
        return lhs.peripheral.identifier == rhs.peripheral.identifier
    }
    
    let peripheral: CBPeripheral
    let txPower: Double?
    var lastSeenRSSI: Double
    var lastSeenAt: Date
    var connectRetriesRemaining: Int
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(peripheral.identifier)
    }
}

class Debouncer<Output>: Publisher {
    typealias Output = [Output]
    typealias Failure = Never

    private var updatesSinceLastNotiy = [Output]()
    private var lastNotifiedAt = Date()
    private var debounceInterval: TimeInterval
    private let notifier = PassthroughSubject<[Output], Failure>()
    private let underlying: (any Publisher<Output, Failure>)?

    init(debounceInterval: TimeInterval) {
        self.debounceInterval = debounceInterval
        self.underlying = nil
    }
    
    init(debounceInterval: TimeInterval, wrapping underlying: any Publisher<Output, Failure>) {
        self.debounceInterval = debounceInterval
        self.underlying = underlying
        
        var cancelable: Cancellable?
        cancelable = underlying.sink { completion in
            cancelable?.cancel()
        } receiveValue: { output in
            self.add(output)
        }
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, [Output] == S.Input {
        self.notifier.receive(subscriber: subscriber)
    }
    
    func add(_ item: Output) {
        let now = Date.now
        
        updatesSinceLastNotiy.append(item)
        
        // for now assume a steady stream of data, so we don't worry
        // about scheduling a later update in case no more data come in to trigger
        if lastNotifiedAt.distance(to: now) > debounceInterval {
            notifier.send(updatesSinceLastNotiy)
            lastNotifiedAt = now
            updatesSinceLastNotiy.removeAll()
        }
    }
    
    var debugUpdatesSinceLastNotify: [Output] { updatesSinceLastNotiy }
}

class BluetoothScanner: NSObject, Publisher, CBCentralManagerDelegate, CBPeripheralDelegate {
    typealias Output = MonitoredPeripheral
    typealias Failure = Never

    let logger = Logger(subsystem: "TooFarDidntLock", category: "App")
    
    private var centralManager: CBCentralManager!
    private var timeToLive: Double
    private var monitoredPeripherals = Set<MonitoredPeripheral>()
    private var connections = Set<UUID>()
    private let notifier = PassthroughSubject<Output, Failure>()
    let didDisconnect = PassthroughSubject<UUID, Never>()

    var peripherals: Set<MonitoredPeripheral> {
        get {
            monitoredPeripherals
        }
    }
    
    init(timeToLive: TimeInterval) {
        self.timeToLive = timeToLive
        
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, S.Failure == Failure, S.Input == Output {
        self.notifier.receive(subscriber: subscriber)
    }
    
    
    func startScanning() {
        logger.log("startScanning")
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func stopScanning() {
        logger.log("stopScanning")
        centralManager.stopScan()
    }
    
    func connect(uuid: UUID) -> Void? {
        guard let peripheral = monitoredPeripherals.first(where: {$0.peripheral.identifier == uuid})
        else { return nil }
        // i don't think this is required but it gives more immediate feedback and avoids logs
        guard !connections.contains(peripheral.peripheral.identifier)
        else { return () }
        // could not get CBConnectPeripheralOptionEnableAutoReconnect working
        centralManager.connect(peripheral.peripheral)
        return ()
    }

    func disconnect(uuid: UUID) {
        guard let peripheral = monitoredPeripherals.first(where: {$0.peripheral.identifier == uuid})
        else { return }
        centralManager.cancelPeripheralConnection(peripheral.peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            logger.error("Bluetooth is not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let now = Date()
        
        // assume update list will never have timedout elements
        let update = MonitoredPeripheral(
            peripheral: peripheral,
            txPower: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Double,
            lastSeenRSSI: RSSI.doubleValue,
            lastSeenAt: now,
            connectRetriesRemaining: 1
        )
        
        monitoredPeripherals = Set([update]).union(monitoredPeripherals).filter{$0.lastSeenAt.distance(to: now) < timeToLive}

        notifier.send(update)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard var device = monitoredPeripherals.first(where: {$0.peripheral.identifier==peripheral.identifier})
        else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        logger.info("Connected to \(peripheral.identifier)")
        device.connectRetriesRemaining = 1
        monitoredPeripherals.update(with: device)
        connections.insert(peripheral.identifier)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        logger.info("Failed to connect to \(peripheral.identifier), error=\(error)")
        handleDisconnect(peripheral: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: (any Error)?) {
        // code=7 : The specified device has disconnected from us.
        logger.info("Disconnected from \(peripheral.identifier), isReconnecting=\(isReconnecting), error=\(error)")
        handleDisconnect(peripheral: peripheral)
    }
    
    private func handleDisconnect(peripheral: CBPeripheral) {
        connections.remove(peripheral.identifier)
        guard var device = monitoredPeripherals.first(where: {$0.peripheral.identifier==peripheral.identifier})
        else { return }
        if device.connectRetriesRemaining > 0 {
            device.connectRetriesRemaining -= 1
            logger.info("Reconnecting to \(peripheral.identifier), retriesRemaining=\(device.connectRetriesRemaining)")
            monitoredPeripherals.update(with: device)
            centralManager.connect(peripheral)
        } else {
            self.didDisconnect.send(peripheral.identifier)
        }
    }
}

extension CBPeripheral {
    var isConnected: Bool {
        state == .connected || state == .connecting
    }
}
