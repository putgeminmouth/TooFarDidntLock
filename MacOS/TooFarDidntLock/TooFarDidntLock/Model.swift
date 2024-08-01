import SwiftUI
import OSLog
import Combine


struct DeviceLinkModel: Equatable {
    var uuid: UUID
    var deviceDetails: BluetoothDeviceDescription
    var deviceState: MonitoredPeripheral?
    var referencePower: Double
    var maxDistance: Double
    var idleTimeout: TimeInterval?
    var requireConnection: Bool
}

struct BluetoothDeviceDescription: Equatable {
    var name: String?
    var txPower: Double?
}

struct ApplicationStorage: Equatable {
    // somehow the autogen was not producing the right result
    static func == (lhs: ApplicationStorage, rhs: ApplicationStorage) -> Bool {
        guard lhs.deviceLink == rhs.deviceLink
        else { return false }
        return true
    }
    var deviceLink: DeviceLinkModel?
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
        let deviceLink = dict["deviceLink"]?.flatMap({$0 as? [String: Any?]}).flatMap(DeviceLinkModel.fromDict)
        return ApplicationStorage(
            deviceLink: deviceLink
        )
    }
}

extension DeviceLinkModel: DictionaryRepresentable {
    func toDict() -> [String: Any?] {
        let dict: [String: Any?] = [
            "uuid": self.uuid.uuidString,
            "deviceDetails": self.deviceDetails.toDict(),
            "referencePower": self.referencePower,
            "maximumDistance": self.maxDistance,
            "idleTimeout": self.idleTimeout,
            "requireConnection": self.requireConnection,
        ]
        return dict
    }
    static func fromDict(dict: [String: Any?]) -> DeviceLinkModel? {
        guard let uuidString = dict["uuid"] as? String,
              let uuid = UUID(uuidString: uuidString),
              let deviceDetails = dict["deviceDetails"]?.flatMap({$0 as? [String: Any?]}).flatMap(BluetoothDeviceDescription.fromDict),
              let referencePower = (dict["referencePower"] as? NSNumber)?.doubleValue,
              let maximumDistance = (dict["maximumDistance"] as? NSNumber)?.doubleValue,
              let idleTimeout = (dict["idleTimeout"] as? NSNumber)?.doubleValue,
              let requireConnection = dict["requireConnection"] as? Bool
        else { return nil }
        return DeviceLinkModel(
            uuid: uuid,
            deviceDetails: deviceDetails,
            deviceState: nil,
            referencePower: referencePower,
            maxDistance: maximumDistance,
            idleTimeout: idleTimeout,
            requireConnection: requireConnection
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
    static func fromDict(dict: [String: Any?]) -> BluetoothDeviceDescription? {
        guard let txPower = (dict["txPower"] as? NSNumber)?.doubleValue
        else { return nil }
        return BluetoothDeviceDescription(
            name: dict["name"] as? String,
            txPower: txPower)
    }
}
