import SwiftUI

class ZoneEvaluator: ObservableObject {
    let manual: ManualZoneEvaluator
    let wifi: WifiZoneEvaluator
    init(manual: ManualZoneEvaluator, wifi: WifiZoneEvaluator) {
        self.manual = manual
        self.wifi = wifi
    }
    
    func isActive(_ zone: any Zone) -> Bool {
        switch zone {
        case let z as ManualZone:
            return manual.isActive(z)
        case let z as WifiZone:
            return wifi.isActive(z)
        default:
            return false
        }
    }
}

class ManualZoneEvaluator {
    func isActive(_ zone: ManualZone) -> Bool {
        return zone.active
    }
}

class WifiZoneEvaluator {
    let wifi: WifiScanner
    init(wifi: WifiScanner) {
        self.wifi = wifi
    }
    
    func isActive(_ zone: WifiZone) -> Bool {
        return zone.bssid != nil && wifi.activeWiFiInterfaces().first{$0.bssid() == zone.bssid} != nil
    }
}
