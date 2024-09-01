import SwiftUI
import OSLog
import Combine

class BluetoothMonitorData: ObservableObject {
    @Published var rssiRawSamples = [Tuple2<Date, Double>]()
    @Published var rssiSmoothedSamples = [Tuple2<Date, Double>]()
    
    @Published var referenceRSSIAtOneMeter: Double?
    @Published var distanceSmoothedSamples: [Tuple2<Date, Double>]?

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
    
    let id: UUID
    var zoneId: UUID
    var deviceId: UUID
    var referencePower: Double
    var environmentalNoise: Double
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
    var txPower: Double?
}
