import SwiftUI
import OSLog
import Combine

func == (lhs: [any Zone], rhs: [any Zone]) -> Bool {
    return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy{$0.equals($1)}
}
func != (lhs: [any Zone], rhs: [any Zone]) -> Bool {
    return !(lhs == rhs)
}

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
