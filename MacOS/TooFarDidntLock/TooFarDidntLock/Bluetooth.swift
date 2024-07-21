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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(peripheral.identifier)
    }
}

class BluetoothScanner: NSObject, CBCentralManagerDelegate, Publisher {
    let logger = Logger(subsystem: "TooFarDidntLock", category: "App")
    
    private var centralManager: CBCentralManager!
    private var timeoutSeconds: Double
    private var monitoredPeripherals = Set<MonitoredPeripheral>()
    private var updatesSinceLastNotiy = [MonitoredPeripheral]()
    private var lastNotifiedAt = Date()
    private var notifyMinIntervalMillis: TimeInterval
    private let notifier = PassthroughSubject<Output, Failure>()
    
    var peripherals: Set<MonitoredPeripheral> {
        get {
            monitoredPeripherals
        }
    }
    
    init(timeoutSeconds: Double, notifyMinIntervalMillis: TimeInterval) {
        self.timeoutSeconds = timeoutSeconds
        self.notifyMinIntervalMillis = notifyMinIntervalMillis
        
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    typealias Output = [MonitoredPeripheral]
    typealias Failure = Never
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
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            logger.error("Bluetooth is not available.")
        }
    }
    
    var XX = false
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let now = Date()
        
        // assume update list will never have timedout elements
        let update = MonitoredPeripheral(peripheral: peripheral, txPower: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Double, lastSeenRSSI: RSSI.doubleValue, lastSeenAt: now)
        
        // TODO: is preserving order still useful? I think not as that was for the UI and was moved there
        updatesSinceLastNotiy.updateOrAppend(update: {update}, where: {$0.peripheral.identifier == update.peripheral.identifier})
        monitoredPeripherals.update(with: update)
        
        if lastNotifiedAt.distance(to: now) * 1000 > notifyMinIntervalMillis {
            notifier.send(updatesSinceLastNotiy)
            lastNotifiedAt = now
            updatesSinceLastNotiy.removeAll()
        }
    }
}

extension Array {
    mutating func updateOrAppend(update: () -> Element, where predicate: (Element) throws -> Bool) rethrows {
        if let index = try self.firstIndex(where: predicate) {
            self[index] = update()
        } else {
            self.append(update())
        }
    }
}
