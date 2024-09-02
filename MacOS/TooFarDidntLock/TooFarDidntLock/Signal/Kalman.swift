
/*
 Low R (Measurement Noise), High Q (Process Noise): The filter trusts the measurements more and adjusts quickly, resulting in a more reactive estimate that closely tracks the true state despite the noise in the process.
 High R (Measurement Noise), Low Q (Process Noise): The filter trusts the predictions more and smooths out the measurement noise, leading to a more stable estimate but potentially lagging behind sudden changes in the true state.
 
 Measurement noise controls how much prediction is done more directly. If theres less noise, the prediction should match samples.
 With a lot of process/environmental noise, the prediction is less trusted, making the filter more reactive to pure measurements.
 */
class KalmanFilter {
    var state: Double
    var covariance: Double
    
    var processNoise: Double
    
    var measurementNoise: Double
    
    init(initialState: Double, initialCovariance: Double, processNoise: Double, measurementNoise: Double) {
        self.state = initialState
        self.covariance = initialCovariance
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }
    
    func update(measurement: Double) -> Double {
        // Prediction update
        let predictedState = state
        let predictedCovariance = covariance + processNoise
        
        // Measurement update
        let innovation = measurement - predictedState
        let innovationCovariance = predictedCovariance + measurementNoise
        
        // Kalman gain
        let kalmanGain = predictedCovariance / innovationCovariance
        
        // Update state and covariance
        state = predictedState + kalmanGain * innovation
        covariance = (1 - kalmanGain) * predictedCovariance
        
        return state
    }
}
