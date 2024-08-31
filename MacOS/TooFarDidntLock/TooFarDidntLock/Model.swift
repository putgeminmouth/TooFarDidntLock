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

protocol Zone: DictionaryRepresentable {
    var id: UUID { get }
    var name: String { get }
    func equals(_ other: any Zone) -> Bool
}

struct ManualZone: Zone, Equatable {
    let id: UUID
    var name: String
    var active: Bool
    func equals(_ other: any Zone) -> Bool {
        guard let other = other as? ManualZone
        else { return false }
        return self == other
    }
}

struct WifiZone: Zone, Equatable {
    let id: UUID
    var name: String
    var ssid: String?
    var bssid: String?
    func equals(_ other: any Zone) -> Bool {
        guard let other = other as? WifiZone
        else { return false }
        return self == other
    }
}

struct Links {
    enum State: Equatable {
        case linked
        case unlinked
    }
}
protocol LinkState {
    var id: UUID { get }
    var state: Links.State { get set }
}

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
protocol Link {
    var id: UUID { get }
    var zoneId: UUID { get }
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

class RuntimeModel: ObservableObject {
    @Published var bluetoothStates: [MonitoredPeripheral]
    @Published var linkStates: [LinkState]
    init(bluetoothStates: [MonitoredPeripheral] = [], linkStates: [LinkState] = []) {
        self.bluetoothStates = bluetoothStates
        self.linkStates = linkStates
    }
}


func == (lhs: [any Zone], rhs: [any Zone]) -> Bool {
    return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy{$0.equals($1)}
}
func != (lhs: [any Zone], rhs: [any Zone]) -> Bool {
    return !(lhs == rhs)
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
    @Published var links: [BluetoothLinkModel] {
        didSet {
            if oldValue != links {
                version += 1
            }
        }
    }
    
//    convenience init() {
//        self.init(version: 0, zones: [], wellKnownBluetoothDevices: [], links: [])
//    }
    init(version: Int, zones: [any Zone], wellKnownBluetoothDevices: [MonitoredPeripheral], links: [BluetoothLinkModel]) {
        self.version = version
        self.zones = zones
        self.wellKnownBluetoothDevices = wellKnownBluetoothDevices
        self.links = links
    }
}

struct ApplicationStorage: Equatable {
    static func == (lhs: ApplicationStorage, rhs: ApplicationStorage) -> Bool {
        return lhs.domainModel?.version == rhs.domainModel?.version
    }
    var domainModel: DomainModel?// = DomainModel("ApplicationStorage.init")
}


extension ApplicationStorage: Decodable, Encodable, RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = ApplicationStorage.fromDict(json)
        else {
            return nil
        }
        
        self = app
    }

    public var rawValue: String {
        let dict = self.toDict()
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }
}

extension Model<ApplicationStorage>: Decodable, Encodable, RawRepresentable, DictionaryRepresentable {
    public init?(rawValue: String) {
        if let value = ApplicationStorage(rawValue: rawValue) {
            self.value = value
        } else {
            return nil
        }
    }
    
    public var rawValue: String {
        return self.value.rawValue
    }
    
    func toDict() -> [String: Any?] {
        return value.toDict()
    }
    static func fromDict(_ dict: [String: Any?]) -> Model<ApplicationStorage>? {
        return ApplicationStorage.fromDict(dict).map{Model(value: $0)}
    }
}

protocol DictionaryRepresentable {
    func toDict() -> [String: Any?]
}

extension ApplicationStorage: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "domainModel": self.domainModel?.toDict()
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> ApplicationStorage? {
        guard let domainModel = dict["domainModel"]?.flatMap({$0 as? [String: Any?]}).flatMap(DomainModel.fromDict)
        else { return nil }
        return ApplicationStorage(
            domainModel: domainModel
        )
    }
}

struct ZoneDictionaryRepresentable {
    static func toDict(_ zone: any Zone) -> [String: Any?] {
        return [
            "type": String(describing: type(of: zone)),
            "id": zone.id.uuidString,
            "name": zone.name,
        ]
    }
    static func fromDict(_ dict: [String: Any?]) -> (any Zone)? {
        guard let type = dict["type"] as? String
        else { return nil }
        switch type {
        case String(describing: ManualZone.self):
            return ManualZone.fromDict(dict)
        case String(describing: WifiZone.self):
            return WifiZone.fromDict(dict)
        default:
            return nil
        }
    }
}

extension ManualZone: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = ZoneDictionaryRepresentable.toDict(self).mergeRight([
            "active": self.active
        ])
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> ManualZone? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = dict["name"] as? String,
              let active = dict["active"] as? Bool
        else { return nil }
        return ManualZone(
            id: id,
            name: name,
            active: active
        )
    }
}

extension WifiZone: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = ZoneDictionaryRepresentable.toDict(self).mergeRight([
            "ssid": self.ssid,
            "bssid": self.bssid,
        ])
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> WifiZone? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = dict["name"] as? String
        else { return nil }
        let ssid = dict["ssid"] as? String
        let bssid = dict["bssid"] as? String
        return WifiZone(
            id: id,
            name: name,
            ssid: ssid,
            bssid: bssid
        )
    }
}

extension BluetoothLinkModel: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "id": self.id.uuidString,
            "zoneId": self.zoneId.uuidString,
            "deviceId": self.deviceId.uuidString,
            "referencePower": self.referencePower,
            "environmentalNoise": self.environmentalNoise,
            "maximumDistance": self.maxDistance,
            "idleTimeout": self.idleTimeout,
            "requireConnection": self.requireConnection,
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> BluetoothLinkModel? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let zoneIdString = dict["zoneId"] as? String,
              let zoneId = UUID(uuidString: zoneIdString),
              let deviceIdString = dict["deviceId"] as? String,
              let deviceId = UUID(uuidString: deviceIdString),
              let referencePower = (dict["referencePower"] as? NSNumber)?.doubleValue,
              let maximumDistance = (dict["maximumDistance"] as? NSNumber)?.doubleValue,
              let environmentalNoise = (dict["environmentalNoise"] as? NSNumber)?.doubleValue,
              let idleTimeout = (dict["idleTimeout"] as? NSNumber)?.doubleValue,
              let requireConnection = dict["requireConnection"] as? Bool
        else { return nil }
        return BluetoothLinkModel(
            id: id,
            zoneId: zoneId,
            deviceId: deviceId,
            referencePower: referencePower,
            environmentalNoise: environmentalNoise,
            maxDistance: maximumDistance,
            idleTimeout: idleTimeout,
            requireConnection: requireConnection
        )
    }
}

extension BluetoothDevice: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "deviceId": self.deviceId.uuidString,
            "details": self.details.toDict()
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> BluetoothDevice? {
        guard let deviceIdString = dict["deviceId"] as? String,
              let deviceId = UUID(uuidString: deviceIdString),
              let details = dict["details"]?.flatMap({$0 as? [String: Any?]}).flatMap(BluetoothDeviceDescription.fromDict)
        else { return nil }
        return BluetoothDevice(
            deviceId: deviceId,
            details: details
        )
    }
}

extension BluetoothDeviceDescription: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "name": self.name,
            "txPower": self.txPower
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> BluetoothDeviceDescription? {
        guard let txPower = (dict["txPower"] as? NSNumber)?.doubleValue
        else { return nil }
        return BluetoothDeviceDescription(
            name: dict["name"] as? String,
            txPower: txPower)
    }
}

extension MonitoredPeripheral: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "id": self.id.uuidString,
            "name": self.name,
            "txPower": self.txPower,
            "lastSeenRSSI": self.lastSeenRSSI,
            "lastSeenAt": ISO8601DateFormatter().string(from: self.lastSeenAt)
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> MonitoredPeripheral? {
        guard let idString = (dict["id"] as? String),
              let id = UUID(uuidString: idString)
        else { return nil }
        let name = dict["name"] as? String
        let txPower = (dict["txPower"] as? NSNumber)?.doubleValue
        let lastSeenRSSI = (dict["lastSeenRSSI"] as? NSNumber)?.doubleValue
        let lastSeenAt = (dict["lastSeenAt"] as? String).flatMap{ISO8601DateFormatter().date(from: $0)}
        return MonitoredPeripheral(
            id: id,
            name: name,
            txPower: txPower,
            lastSeenRSSI: lastSeenRSSI ?? 0,
            lastSeenAt: lastSeenAt ?? Date.distantPast,
            connectRetriesRemaining: 0,
            connectionState: .disconnected
        )
    }
}

extension DomainModel: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "version": self.version,
            "zones": self.zones.map{$0.toDict()},
            "wellKnownBluetoothDevices": self.wellKnownBluetoothDevices.map{$0.toDict()},
            "links": self.links.map{$0.toDict()},
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> DomainModel? {
        guard let version = dict["version"] as? Int,
              let zonesDict = dict["zones"] as? [[String: Any?]],
              let wellKnownBluetoothDevicesDict = dict["wellKnownBluetoothDevices"] as? [[String: Any?]],
              let linksDict = dict["links"] as? [[String: Any?]]
        else { return nil }
        let zones = zonesDict.compactMap{ZoneDictionaryRepresentable.fromDict($0)}
        let wellKnownBluetoothDevices = wellKnownBluetoothDevicesDict.compactMap{MonitoredPeripheral.fromDict($0)}
        let links = linksDict.compactMap{BluetoothLinkModel.fromDict($0)}
        return DomainModel(
            version: version,
            zones: zones,
            wellKnownBluetoothDevices: wellKnownBluetoothDevices,
            links: links
        )
    }
}
