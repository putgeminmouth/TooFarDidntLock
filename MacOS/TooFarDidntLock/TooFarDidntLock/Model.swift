import SwiftUI
import OSLog
import Combine

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
struct DeviceLinkState: LinkState {
    let id: UUID
    var state: Links.State
    var rssiRawSamples = [Tuple2<Date, Double>]()
    var rssiSmoothedSamples = [Tuple2<Date, Double>]()
    var distanceSmoothedSamples = [Tuple2<Date, Double>]()
    var smoothingFunc = KalmanFilter(initialState: 0, initialCovariance: 2.01, processNoise: 0.1, measurementNoise: 20.01)
}
protocol Link {
    var id: UUID { get }
    var zoneId: UUID { get }
}

struct DeviceLinkModel: Link, Equatable {
    static func zd(_ l: DeviceLinkModel, _ r: DeviceLinkModel) -> Bool {
        return l.zoneId == r.zoneId && l.deviceId == r.deviceId
    }
    
    let id: UUID
    var zoneId: UUID
    var deviceId: UUID
    var referencePower: Double
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
    @Published var links: [DeviceLinkModel] {
        didSet {
            if oldValue != links {
                version += 1
            }
        }
    }
    
//    convenience init() {
//        self.init(version: 0, zones: [], wellKnownBluetoothDevices: [], links: [])
//    }
    init(version: Int, zones: [any Zone], wellKnownBluetoothDevices: [MonitoredPeripheral], links: [DeviceLinkModel]) {
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

extension DeviceLinkModel: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "id": self.id.uuidString,
            "zoneId": self.zoneId.uuidString,
            "deviceId": self.deviceId.uuidString,
            "referencePower": self.referencePower,
            "maximumDistance": self.maxDistance,
            "idleTimeout": self.idleTimeout,
            "requireConnection": self.requireConnection,
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> DeviceLinkModel? {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let zoneIdString = dict["zoneId"] as? String,
              let zoneId = UUID(uuidString: zoneIdString),
              let deviceIdString = dict["deviceId"] as? String,
              let deviceId = UUID(uuidString: deviceIdString),
              let referencePower = (dict["referencePower"] as? NSNumber)?.doubleValue,
              let maximumDistance = (dict["maximumDistance"] as? NSNumber)?.doubleValue,
              let idleTimeout = (dict["idleTimeout"] as? NSNumber)?.doubleValue,
              let requireConnection = dict["requireConnection"] as? Bool
        else { return nil }
        return DeviceLinkModel(
            id: id,
            zoneId: zoneId,
            deviceId: deviceId,
            referencePower: referencePower,
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
        var zones = zonesDict.flatMap{ZoneDictionaryRepresentable.fromDict($0)}
        let wellKnownBluetoothDevices = wellKnownBluetoothDevicesDict.flatMap{MonitoredPeripheral.fromDict($0)}
        let links = linksDict.flatMap{DeviceLinkModel.fromDict($0)}
        return DomainModel(
            version: version,
            zones: zones,
            wellKnownBluetoothDevices: wellKnownBluetoothDevices,
            links: links
        )
    }
}
