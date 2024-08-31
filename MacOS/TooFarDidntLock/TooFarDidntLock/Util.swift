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
    mutating func updateOrAppend(update: () -> Element, where predicate: (Element) throws -> Bool) rethrows {
        if let index = try self.firstIndex(where: predicate) {
            self[index] = update()
        } else {
            self.append(update())
        }
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
