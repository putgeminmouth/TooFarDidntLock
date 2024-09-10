import Foundation

/*
 Low R (Measurement Noise), High Q (Process Noise): The filter trusts the measurements more and adjusts quickly, resulting in a more reactive estimate that closely tracks the true state despite the noise in the process.
 High R (Measurement Noise), Low Q (Process Noise): The filter trusts the predictions more and smooths out the measurement noise, leading to a more stable estimate but potentially lagging behind sudden changes in the true state.
 
 Measurement noise controls how much prediction is done more directly. If theres less noise, the prediction should match samples.
 With a lot of process/environmental noise, the prediction is less trusted, making the filter more reactive to pure measurements.
 
 Measurement covariance: how much do measurements vary? how much do predictions need to allow for sharp changes? a non-noisy signal can still have a high (but regular) variance.
 
 Values of 0 for variance seems to break things.
 */
class KalmanFilter {
    var state: Double!
    var covariance: Double
    
    var processVariance: Double
    
    var measureVariance: Double
    
    init(initialState: Double?, initialCovariance: Double, processVariance: Double, measureVariance: Double) {
        self.state = initialState
        self.covariance = initialCovariance
        self.processVariance = processVariance
        self._measureVariance = measureVariance
        _id = ObjectIdentifier(self)
    }
    
    func update(measurement: Double) -> Double {
        if state == nil {
            state = measurement
        }
        
        // Prediction update
        let predictedState = state!
        let predictedCovariance = covariance + processVariance
        
        // Measurement update
        let innovation = measurement - predictedState
        let innovationCovariance = predictedCovariance + measureVariance
        
        // Kalman gain
        let kalmanGain = predictedCovariance / (innovationCovariance != 0 ? innovationCovariance :  1)
        
        // Update state and covariance
        state = predictedState + kalmanGain * innovation
        covariance = (1 - kalmanGain) * predictedCovariance

        return state
    }
}
