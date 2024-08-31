import SwiftUI

struct Icons {
    struct Icon {
        var systemName: String? = nil
        var resourceName: String? = nil
        
        func toImage() -> Image {
            if let systemName = systemName {
                return Image(systemName: systemName)
            } else if let resourceName = resourceName {
                return Image(resourceName)
            } else {
                assert(false)
            }
        }
    }
    
    static let zone = Icon(systemName: "mappin.and.ellipse")
    static let settings = Icon(systemName: "gear")
    static let bluetooth = Icon(resourceName: "Bluetooth")
    static let link = Icon(systemName: "link")
    struct Zones {
        static let manual = Icon(systemName: "lightswitch.on")
        static let wifi = Icon(systemName: "wifi")
        static func of(_ zone: any Zone) -> Icon {
            if zone is ManualZone { return manual }
            if zone is WifiZone { return wifi }
            assert(false)
        }
    }
    struct Links {
        static func of(_ link: any Link) -> Icon {
            if link is BluetoothLinkModel { return bluetooth }
            assert(false)
        }
    }
}
