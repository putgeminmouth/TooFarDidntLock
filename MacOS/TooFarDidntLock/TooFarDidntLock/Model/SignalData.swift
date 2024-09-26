import SwiftUI
import Combine

/*
 https://en.wikipedia.org/wiki/Path_loss
 > 2 is for propagation in free space, 4 is for relatively lossy environments
 > and for the case of full specular reflection from the earth surface—the so-called flat earth model.
 > In some environments, such as buildings, stadiums and other indoor environments,
 > the path loss exponent can reach values in the range of 4 to 6
 */
struct PathLoss {
    static let freeSpace = 2.0
    static let lossy = 4.0
}

func rssiDistance(referenceAtOneMeter: Double, environmentalPathLoss: Double, current: Double) -> Double {
    let N: Double = environmentalPathLoss
    let e: Double = (referenceAtOneMeter - current) / (10*N)
    let distanceInMeters = pow(10, e)
    return Double(distanceInMeters)
}

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
