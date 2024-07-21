import SwiftUI
import OSLog
import Combine


struct DeviceLinkModel: Equatable {
    var uuid: UUID
    var deviceDetails: BluetoothDeviceModel
    var referencePower: Double
    var maxDistance: Double
    var idleTimeout: TimeInterval?
    var requireConnection: Bool
}

struct BluetoothDeviceModel: Equatable {
    var uuid: UUID
    // these may change
    var name: String?
    var rssi: Double
    var txPower: Double?
    var lastSeenAt: Date
    var isConnected: Bool
}


struct DeviceLinkStorage: Equatable {
    var uuid: String
    var deviceDetails: BluetoothDeviceDetailsStorage
    var referencePower: Double
    var maxDistance: Double
    var idleTimeout: TimeInterval?
    var requireConnection: Bool
}
struct BluetoothDeviceDetailsStorage: Equatable {
    var uuid: String
    var name: String?
    var rssi: Double
}
struct ApplicationStorage: Equatable {
    // somehow the autogen was not producing the right result
    static func == (lhs: ApplicationStorage, rhs: ApplicationStorage) -> Bool {
        guard lhs.deviceLink == rhs.deviceLink
        else { return false }
        return true
    }
    var deviceLink: DeviceLinkStorage?
}


extension ApplicationStorage: Decodable, Encodable, RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = ApplicationStorage.fromDict(dict: json)
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

protocol DictionaryRepresentable {
    func toDict() -> [String: Any?]
}

extension ApplicationStorage: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "deviceLink": self.deviceLink.map({$0.toDict()})
        ]
        return dict
    }
    static func fromDict(dict: [String: Any?]) -> ApplicationStorage? {
        let deviceLink = dict["deviceLink"]?.flatMap({$0 as? [String: Any?]}).flatMap(DeviceLinkStorage.fromDict)
        return ApplicationStorage(
            deviceLink: deviceLink
        )
    }
}

extension DeviceLinkStorage: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "uuid": self.uuid,
            "deviceDetails": self.deviceDetails.toDict(),
            "referencePower": self.referencePower,
            "maximumDistance": self.maxDistance,
            "idleTimeout": self.idleTimeout,
            "requireConnection": self.requireConnection,
        ]
        return dict
    }
    static func fromDict(dict: [String: Any?]) -> DeviceLinkStorage? {
        guard let uuid = dict["uuid"] as? String,
              let deviceDetails = dict["deviceDetails"]?.flatMap({$0 as? [String: Any?]}).flatMap(BluetoothDeviceDetailsStorage.fromDict),
              let referencePower = (dict["referencePower"] as? NSNumber)?.doubleValue,
              let maximumDistance = (dict["maximumDistance"] as? NSNumber)?.doubleValue,
              let idleTimeout = (dict["idleTimeout"] as? NSNumber)?.doubleValue,
              let requireConnection = dict["requireConnection"] as? Bool
        else { return nil }
        return DeviceLinkStorage(
            uuid: uuid,
            deviceDetails: deviceDetails,
            referencePower: referencePower,
            maxDistance: maximumDistance,
            idleTimeout: idleTimeout,
            requireConnection: requireConnection
        )
    }
}

extension BluetoothDeviceDetailsStorage: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "uuid": self.uuid,
            "name": self.name,
            "rssi": self.rssi
        ]
        return dict
    }
    static func fromDict(dict: [String: Any?]) -> BluetoothDeviceDetailsStorage? {
        guard let uuid = dict["uuid"] as? String,
              let rssi = (dict["rssi"] as? NSNumber)?.doubleValue
        else { return nil }
        return BluetoothDeviceDetailsStorage(
            uuid: uuid,
            name: dict["name"] as? String,
            rssi: rssi)
    }
}
