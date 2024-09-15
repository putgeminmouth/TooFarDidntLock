import Combine
import Foundation

class SimpleMovingAverage {
    private var windowSize: Int
    private var values: [Double] = []
    private var sum: Double = 0.0
    
    init(windowSize: Int) {
        self.windowSize = windowSize
    }
    
    func addValue(_ value: Double) {
        values.append(value)
        sum += value
        
        if values.count > windowSize {
            sum -= values.removeFirst()
        }
    }
    
    var currentAverage: Double {
        if values.isEmpty {
            return 0.0
        } else {
            return sum / Double(values.count)
        }
    }
}

struct Tuple2<A: Equatable, B: Equatable>: Equatable {
    let a: A
    let b: B
    var first: A { a }
    var second: B { b }
    init(_ a: A, _ b: B) {
        self.a = a
        self.b = b
    }
}

extension Array {
    mutating func updateOrAppend(_ update: @escaping (Element?) -> Element, where predicate: @escaping (Element) -> Bool) {
        if let index = self.firstIndex(where: predicate) {
            self[index] = update(self[index])
        } else {
            self.append(update(nil))
        }
    }
    mutating func updateOrAppend(_ update: @escaping () -> Element, where predicate: @escaping (Element) -> Bool) {
        if let index = self.firstIndex(where: predicate) {
            self[index] = update()
        } else {
            self.append(update())
        }
    }
    mutating func updateOrAppend(_ update: Element, where predicate: @escaping (Element) -> Bool) {
        if let index = try self.firstIndex(where: predicate) {
            self[index] = update
        } else {
            self.append(update)
        }
    }
    mutating func updateOrAppend(_ update: Element) where Element: Equatable {
        if let index = self.firstIndex(of: update) {
            self[index] = update
        } else {
            self.append(update)
        }
    }
    
    func nonEmptyOrNil() -> Array? {
        return self.isEmpty ? nil : self
    }
}

extension Array where Element == Double {
    func mean() -> Double {
        return self.reduce(0, +) / Double(self.count)
    }
    
    func standardDeviation() -> Double {
        guard !self.isEmpty else { return 0 }
        let meanValue = self.mean()
        let variance = self.reduce(0) { (result, value) -> Double in
            let diff = value - meanValue
            return result + diff * diff
        } / Double(self.count)
        return sqrt(variance)
    }
    
    func percentile(_ percentilePercent: Double) -> Double {
        let sortedData = self.sorted()
        let index = Int(Double(sortedData.count - 1) * percentilePercent / 100.0)
        return sortedData[index]
    }
    
    func average() -> Double? {
        guard count > 0 else { return nil }
        let avg = self.reduce(0, +) / Double(self.count)
        return avg
    }
}

extension Array where Element == Tuple2<Date, Double> {
    func runningPercentile(windowSampleCount: Int, percentilePercent: Double) -> [Tuple2<Date, Double>] {
        guard windowSampleCount > 0 else { return [] }
        var result = [Tuple2<Date, Double>]()
        let sampleCount = Swift.min(self.count, windowSampleCount)
        let windowCount = self.count / windowSampleCount
        for i in 0..<windowCount {
            let window = Array(self[i..<(i + sampleCount)])
            assert( window.count > 0)
            result.append(Tuple2(
                Date(timeIntervalSince1970: window.map{$0.a.timeIntervalSince1970}.reduce(0.0, +) / Double(window.count)),
                window.map{$0.b}.percentile(percentilePercent)
            ))
        }
        return result
    }
    
    func lastNSeconds(seconds: Double) -> [Tuple2<Date, Double>] {
        return self.filter{$0.a.distance(to: Date()) < seconds}
    }
}

class Debouncer<Output>: Publisher {
    typealias Output = [Output]
    typealias Failure = Never

    private var updatesSinceLastNotiy = [Output]()
    private var lastNotifiedAt = Date()
    private var debounceInterval: TimeInterval
    private let notifier = PassthroughSubject<[Output], Failure>()
    private let underlying: (any Publisher<Output, Failure>)?

    init(debounceInterval: TimeInterval) {
        self.debounceInterval = debounceInterval
        self.underlying = nil
    }
    
    init(debounceInterval: TimeInterval, wrapping underlying: any Publisher<Output, Failure>) {
        self.debounceInterval = debounceInterval
        self.underlying = underlying
        
        var cancelable: Cancellable?
        cancelable = underlying.sink { completion in
            cancelable?.cancel()
        } receiveValue: { output in
            self.add(output)
        }
    }
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, [Output] == S.Input {
        self.notifier.receive(subscriber: subscriber)
    }
    
    func add(_ item: Output) {
        let now = Date.now
        
        updatesSinceLastNotiy.append(item)
        
        // for now assume a steady stream of data, so we don't worry
        // about scheduling a later update in case no more data come in to trigger
        if lastNotifiedAt.distance(to: now) > debounceInterval {
            notifier.send(updatesSinceLastNotiy)
            lastNotifiedAt = now
            updatesSinceLastNotiy.removeAll()
        }
    }
    
    var debugUpdatesSinceLastNotify: [Output] { updatesSinceLastNotiy }
}

extension Dictionary {
    func map<T>(_ transform: @escaping (Self.Key, Self.Value) -> (Self.Key, T)) -> Dictionary<Self.Key, T> {
        return Dictionary<Self.Key, T>(uniqueKeysWithValues: self.map{ transform($0.key, $0.value) })
    }
    
    func mergeRight(_ rhs: [Key: Value]) -> [Key: Value] {
        return self.merging(rhs) {(l,r) in r}
    }
}

@propertyWrapper
struct EquatableIgnore<Value>: Equatable {
    var wrappedValue: Value

    static func == (lhs: EquatableIgnore<Value>, rhs: EquatableIgnore<Value>) -> Bool {
        true
    }
}

// https://stackoverflow.com/questions/63926305/combine-previous-value-using-combine
extension Publisher {
    
    /// Includes the current element as well as the previous element from the upstream publisher in a tuple where the previous element is optional.
    /// The first time the upstream publisher emits an element, the previous element will be `nil`.
    ///
    ///     let range = (1...5)
    ///     cancellable = range.publisher
    ///         .withPrevious()
    ///         .sink { print ("(\($0.previous), \($0.current))", terminator: " ") }
    ///      // Prints: "(nil, 1) (Optional(1), 2) (Optional(2), 3) (Optional(3), 4) (Optional(4), 5) ".
    ///
    /// - Returns: A publisher of a tuple of the previous and current elements from the upstream publisher.
    func withPrevious() -> AnyPublisher<(previous: Output?, current: Output), Failure> {
        scan(Optional<(Output?, Output)>.none) { ($0?.1, $1) }
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    
    /// Includes the current element as well as the previous element from the upstream publisher in a tuple where the previous element is not optional.
    /// The first time the upstream publisher emits an element, the previous element will be the `initialPreviousValue`.
    ///
    ///     let range = (1...5)
    ///     cancellable = range.publisher
    ///         .withPrevious(0)
    ///         .sink { print ("(\($0.previous), \($0.current))", terminator: " ") }
    ///      // Prints: "(0, 1) (1, 2) (2, 3) (3, 4) (4, 5) ".
    ///
    /// - Parameter initialPreviousValue: The initial value to use as the "previous" value when the upstream publisher emits for the first time.
    /// - Returns: A publisher of a tuple of the previous and current elements from the upstream publisher.
    func withPrevious(_ initialPreviousValue: Output) -> AnyPublisher<(previous: Output, current: Output), Failure> {
        scan((initialPreviousValue, initialPreviousValue)) { ($0.1, $1) }.eraseToAnyPublisher()
    }

}
