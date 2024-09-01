import SwiftUI
import OSLog
import Combine

/*
 Sometimes we want to provide an object to the UI and let it reactively obtain up to date values
 e.g. on a button press, without necessarily updating the view otherwise.
 Other times we will want a view to update only as a conditional function of the data via onReceive().
 Finally somtimes the naive approach letting SwiftUI do its magic is best.
 
 We also have constraints in dependency injection:
    `@EnvironmentObject` requires observable
    `@Environment` requires (i forget)
 both of which tend to cause the view to update.
 
 
 Naive updates on an object graph are well handled by `struct`.
 
 `@State` var that is a `@ObservableObjet`/`@Published` passed from a parent lets child subscribe via `onReceive(obj.objectWillChange)`
 You can "safely" extend `ObservableObject` to leverage `@EnvironmentObject` so long as nothing is `@Published` too.
 We hax around this via NotObserved<> as well.
 
 
  Avoid causing the view to bind to runtimeModel as it constantly updates. That means avoiding ref to it via @EnvironmentObject too.
 
  The domainModel doesn't spam updates and we usually want to update everything related, so the naive `struct` approach is used there.
 */


class RuntimeModel: ObservableObject {
    @Published var bluetoothStates: [MonitoredPeripheral]
    @Published var wifiStates: [MonitoredWifiDevice]
    @Published var linkStates: [LinkState]
    init(
        bluetoothStates: [MonitoredPeripheral] = [],
        wifiStates: [MonitoredWifiDevice] = [],
        linkStates: [LinkState] = []) {
            self.bluetoothStates = bluetoothStates
            self.linkStates = linkStates
            self.wifiStates = wifiStates
        }
}

// @Observable enables write-backs
// ObservableObject: @EnvironmentObject
// Publisher: onReceive
// Equatable: onChange
class DomainModel: ObservableObject, Observable /*Publisher*//*, Equatable */{
    @Published private(set) var version: Int = 0
    // make them use a METHOD, AKA passive
    // aggresively discourage casual use
    func setVersion(_ newValue: Int) {
        version = newValue
    }
    
    @Published var zones: [any Zone] {
        didSet {
            if oldValue != zones {
                version += 1
            }
        }
    }
    
    @Published var wellKnownBluetoothDevices: [MonitoredPeripheral] {
        didSet {
            if oldValue != wellKnownBluetoothDevices {
                version += 1
            }
        }
    }
    
    @Published var wellKnownWifiDevices: [MonitoredWifiDevice] {
        didSet {
            if oldValue != wellKnownWifiDevices {
                version += 1
            }
        }
    }

    @Published var links: [BluetoothLinkModel] {
        didSet {
            if oldValue != links {
                version += 1
            }
        }
    }
    
    init(
        version: Int,
        zones: [any Zone],
        wellKnownBluetoothDevices: [MonitoredPeripheral],
        wellKnownWifiDevices: [MonitoredWifiDevice],
        links: [BluetoothLinkModel]) {
            self.version = version
            self.zones = zones
            self.wellKnownBluetoothDevices = wellKnownBluetoothDevices
            self.wellKnownWifiDevices = wellKnownWifiDevices
            self.links = links
        }
}
