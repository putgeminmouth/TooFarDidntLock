import SwiftUI
import OSLog
import Combine

typealias DataDesc = String
//struct DataDesc: Hashable {
//    let label: String
//    init(label: String) {
//        self.label = label
//    }
//    init(_ label: String) {
//        self.init(label: label)
//    }
//}

struct DataSample: Equatable, Hashable {
    let date: Date
    let value: Double
    
    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
    init(_ date: Date, _ value: Double) {
        self.init(date: date, value: value)
    }
}

class BluetoothMonitorData: ObservableObject {
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
    var transmitPower: Double?
}
