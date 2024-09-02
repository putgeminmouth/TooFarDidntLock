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

class CancellablePublisher<Output>: ObservableObject, Cancellable {
    
    let didPublish: PassthroughSubject<Output, Never>? = PassthroughSubject<Output, Never>()
    private var cancellable: AnyCancellable?

    init(_ cancel: @escaping () -> Void) {
        cancellable = AnyCancellable {
            cancel()
        }
    }
    
    func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }
    
    func send(_ input: Output) {
        didPublish?.send(input)
    }
}

class ProxyPublisher<Output>: Publisher {
    typealias Output = Output
    typealias Failure = Never

    var underlying: (any Publisher<Output, Never>)?
    init(_ underlying: (any Publisher<Output, Never>)?) {
        self.underlying = underlying
    }
    func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Output == S.Input {
        underlying?.receive(subscriber: subscriber)
    }

    func send(_ input: Output) {
        underlying
    }
}

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

    func bluetoothStateDidChange(id: @escaping () -> UUID?) -> AnyPublisher<MonitoredPeripheral, Never> {
        return $bluetoothStates
            .flatMap{$0.publisher}
            .filter {
                return $0.id == id()
            }.eraseToAnyPublisher()
    }
}

// @Observable enables write-backs
// ObservableObject: @EnvironmentObject
// Publisher: onReceive
// Equatable: onChange
class DomainModel: ObservableObject, Observable /*Publisher*//*, Equatable */{
    static func equate(_ lhs: MonitoredPeripheral, _ rhs: MonitoredPeripheral) -> Bool {
        // leave out spammy "state" props like rssi
        return lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.transmitPower == rhs.transmitPower
    }
    
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
            if oldValue.elementsEqual(wellKnownBluetoothDevices, by: DomainModel.equate) {
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
