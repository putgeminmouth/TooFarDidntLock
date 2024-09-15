import SwiftUI
import OSLog
import Combine

protocol DictionaryRepresentable {
    func toDict() -> [String: Any?]
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
            "processVariance": self.processVariance,
            "measureVariance": self.measureVariance,
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
              let processVariance = (dict["processVariance"] as? NSNumber)?.doubleValue,
              let measureVariance = (dict["measureVariance"] as? NSNumber)?.doubleValue,
              let autoMeasureVariance = dict["autoMeasureVariance"] as? Bool,
              let idleTimeout = (dict["idleTimeout"] as? NSNumber)?.doubleValue,
              let requireConnection = dict["requireConnection"] as? Bool
        else { return nil }
        return BluetoothLinkModel(
            id: id,
            zoneId: zoneId,
            deviceId: deviceId,
            referencePower: referencePower,
            processVariance: processVariance,
            measureVariance: measureVariance,
            autoMeasureVariance: autoMeasureVariance,
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
            "transmitPower": self.transmitPower
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> BluetoothDeviceDescription? {
        guard let transmitPower = (dict["transmitPower"] as? NSNumber)?.doubleValue
        else { return nil }
        return BluetoothDeviceDescription(
            name: dict["name"] as? String,
            transmitPower: transmitPower)
    }
}

extension MonitoredPeripheral: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "id": self.id.uuidString,
            "name": self.name,
            "transmitPower": self.transmitPower,
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
        let transmitPower = (dict["transmitPower"] as? NSNumber)?.doubleValue
        let lastSeenRSSI = (dict["lastSeenRSSI"] as? NSNumber)?.doubleValue
        let lastSeenAt = (dict["lastSeenAt"] as? String).flatMap{ISO8601DateFormatter().date(from: $0)}
        return MonitoredPeripheral(
            id: id,
            name: name,
            transmitPower: transmitPower,
            lastSeenRSSI: lastSeenRSSI ?? 0,
            lastSeenAt: lastSeenAt ?? Date.distantPast,
            connectRetriesRemaining: 0,
            connectionState: .disconnected
        )
    }
}

extension MonitoredWifiDevice: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "bssid": self.bssid,
            "ssid": self.ssid,
            "noiseMeasurement": self.noiseMeasurement,
            "lastSeenRSSI": self.lastSeenRSSI,
            "lastSeenAt": ISO8601DateFormatter().string(from: self.lastSeenAt)
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> MonitoredWifiDevice? {
        guard let bssid = dict["bssid"] as? String
        else { return nil }
        let ssid = dict["ssid"] as? String
        let noiseMeasurement = (dict["noiseMeasurement"] as? NSNumber)?.doubleValue ?? 0
        let lastSeenRSSI = (dict["lastSeenRSSI"] as? NSNumber)?.doubleValue
        let lastSeenAt = (dict["lastSeenAt"] as? String).flatMap{ISO8601DateFormatter().date(from: $0)}
        return MonitoredWifiDevice(
            bssid: bssid,
            ssid: ssid,
            noiseMeasurement: noiseMeasurement,
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
            "wellKnownWifiDevices": self.wellKnownWifiDevices.map{$0.toDict()},
            "links": self.links.map{$0.toDict()},
        ]
        return dict
    }
    static func fromDict(_ dict: [String: Any?]) -> DomainModel? {
        guard let version = dict["version"] as? Int,
              let zonesDict = dict["zones"] as? [[String: Any?]],
              let wellKnownBluetoothDevicesDict = dict["wellKnownBluetoothDevices"] as? [[String: Any?]],
              let wellKnownWifiDevicesDict = dict["wellKnownWifiDevices"] as? [[String: Any?]],
              let linksDict = dict["links"] as? [[String: Any?]]
        else { return nil }
        let zones = zonesDict.compactMap{ZoneDictionaryRepresentable.fromDict($0)}
        let wellKnownBluetoothDevices = wellKnownBluetoothDevicesDict.compactMap{MonitoredPeripheral.fromDict($0)}
        let wellKnownWifiDevices = wellKnownWifiDevicesDict.compactMap{MonitoredWifiDevice.fromDict($0)}
        let links = linksDict.compactMap{BluetoothLinkModel.fromDict($0)}
        return DomainModel(
            version: version,
            zones: zones,
            wellKnownBluetoothDevices: wellKnownBluetoothDevices,
            wellKnownWifiDevices: wellKnownWifiDevices,
            links: links
        )
    }
}
