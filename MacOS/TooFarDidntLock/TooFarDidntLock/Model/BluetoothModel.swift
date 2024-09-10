import SwiftUI
import OSLog
import Combine

class BluetoothMonitorData: SignalMonitorData, ObservableObject {
    var publisher: AnyPublisher<(), Never> {
        objectWillChange.eraseToAnyPublisher()
    }
    
    @Published var rssiRawSamples = [DataSample]()
    @Published var rssiSmoothedSamples = [DataSample]()
    
    @Published var referenceRSSIAtOneMeter: Double?
    @Published var distanceSmoothedSamples: [DataSample]?

    var smoothingFunc: KalmanFilter? = nil
}

struct BluetoothLinkState: LinkState {
    let id: UUID
    var state: Links.State
    var monitorData: BluetoothMonitor.Monitored
}

struct BluetoothLinkModel: Link, Equatable {
    static func zd(_ l: BluetoothLinkModel, _ r: BluetoothLinkModel) -> Bool {
        return l.zoneId == r.zoneId && l.deviceId == r.deviceId
    }
    
    static let DefaultProcessVariance = 1.0
    static let DefaultMeasureVariance = 1.0
    
    let id: UUID
    var zoneId: UUID
    var deviceId: UUID
    var referencePower: Double
    var processVariance: Double
    var measureVariance: Double
    var maxDistance: Double
    var idleTimeout: TimeInterval?
    var requireConnection: Bool
}

struct BluetoothDevice: Equatable {
    var deviceId: UUID
    var details: BluetoothDeviceDescription
}

struct BluetoothDeviceDescription: Equatable {
    var name: String?
    var transmitPower: Double?
}
