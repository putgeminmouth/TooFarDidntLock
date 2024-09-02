import SwiftUI
import OSLog
import Combine

class WifiMonitorData: ObservableObject {
    @Published var rssiRawSamples = [DataSample]()
    @Published var rssiSmoothedSamples = [DataSample]()
    
    @Published var referenceRSSIAtOneMeter: Double?
    @Published var distanceSmoothedSamples: [DataSample]?

    var smoothingFunc: KalmanFilter? = nil
}

struct WifiLinkState: LinkState {
    let id: UUID
    var state: Links.State
    var monitorData: WifiMonitor.Monitored
}

struct WifiLinkModel: Link, Equatable {
    static func zd(_ l: WifiLinkModel, _ r: WifiLinkModel) -> Bool {
        return l.zoneId == r.zoneId && l.deviceId == r.deviceId
    }
    
    let id: UUID
    var zoneId: UUID
    var deviceId: String
    var referencePower: Double
    var environmentalNoise: Double
    var maxDistance: Double
    var idleTimeout: TimeInterval?
    var requireConnection: Bool
}

//struct WifiDevice: Equatable {
//    var deviceId: UUID
//    var details: WifiDeviceDescription
//}
