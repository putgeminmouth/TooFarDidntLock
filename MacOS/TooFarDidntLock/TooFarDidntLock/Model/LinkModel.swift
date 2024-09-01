import SwiftUI
import OSLog
import Combine

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



protocol Link {
    var id: UUID { get }
    var zoneId: UUID { get }
}
