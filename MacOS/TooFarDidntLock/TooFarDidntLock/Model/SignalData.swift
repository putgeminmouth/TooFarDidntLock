import SwiftUI
import Combine

protocol SignalMonitorData {
    var rssiRawSamples: [DataSample] { get set }
    var rssiSmoothedSamples: [DataSample] { get set }
    
    var referenceRSSIAtOneMeter: Double? { get set }
    var distanceSmoothedSamples: [DataSample]? { get set }

    var smoothingFunc: KalmanFilter? { get set }
    
    var publisher: AnyPublisher<(), Never> { get }
}
