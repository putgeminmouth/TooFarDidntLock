import SwiftUI
import Combine

// we keep a bit more than we show to allow smoothing the display edges
// TODO: centralize this and the 60s used elsewhere
let signalDataRetentionPeriod: TimeInterval = 100

typealias DataDesc = String

struct DataSample: Equatable, Hashable {
    static func tail(_ arr: [DataSample], _ offset: Double) -> [DataSample] {
        return arr.filter{
            let d = $0.date.distance(to: Date())
            return d > offset
        }.suffix(1000)
    }

    
    let date: Date
    let value: Double
    
    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
    init(_ date: Date, _ value: Double) {
        self.init(date: date, value: value)
    }
}

protocol SignalMonitorData {
    var rssiRawSamples: [DataSample] { get set }
    var rssiSmoothedSamples: [DataSample] { get set }
    
    var referenceRSSIAtOneMeter: Double? { get set }
    var distanceSmoothedSamples: [DataSample]? { get set }

    var smoothingFunc: KalmanFilter? { get set }
    
    var publisher: AnyPublisher<(), Never> { get }
}
