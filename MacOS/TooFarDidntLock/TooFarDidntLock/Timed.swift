import SwiftUI
import OSLog
import Combine

class Timed: Cancellable, Publisher {
    typealias Output = Date
    typealias Failure = Never
    private let notifier = PassthroughSubject<Output, Failure>()
    private var publisher: Timer.TimerPublisher?
    private var interval: TimeInterval?
    private var dispatch: RunLoop
    private var sink: Cancellable?
//    private var cancellable: Cancellable?
    
    var lastValue: Output?
    
    init(interval: TimeInterval?, dispatch: RunLoop? = nil) {
        self.interval = interval
        self.dispatch = dispatch ?? .main // TODO: no default
    }
    convenience init() {
        self.init(interval: nil)
    }

    func receive<S>(subscriber: S) where S : Subscriber, S.Failure == Failure, S.Input == Output {
        self.notifier.receive(subscriber: subscriber)
    }

    @discardableResult
    func start(interval: Int) -> Timed {
        return self.start(interval: TimeInterval(interval))
    }
    @discardableResult
    func start() -> Timed {
        return self.start(interval: nil)
    }
    @discardableResult
    func start(interval: TimeInterval?, ttl: TimeInterval? = nil) -> Timed {
//        assert(self.cancellable == nil)
        assert(self.publisher == nil)
        assert(self.sink == nil)
        assert((interval ?? self.interval) != nil)
        let itv = (interval ?? self.interval)!
        self.interval = itv
        self.publisher = Timer.publish(every: itv, tolerance: nil, on: dispatch, in: .common)
        let startedAt = Date.now
        self.sink = self.publisher?.autoconnect().sink(receiveValue: {
            let isExpired = ttl.map{startedAt.distance(to: Date.now) > $0} ?? false
            if isExpired {
                self.stop()
            } else {
                self.lastValue = $0
                self.notifier.send($0)
            }
        })
//        self.cancellable = publisher?.connect()
        return self
    }
    
    @discardableResult
    func stop() -> Timed {
//        self.cancellable?.cancel()
//        self.cancellable = nil
        self.sink?.cancel()
        self.sink = nil
        self.publisher = nil
        return self
    }
    
    @discardableResult
    func restart(interval: TimeInterval? = nil) -> Timed {
        let interval = interval ?? (self.interval ?? self.publisher?.interval)
        return self.stop().start(interval: interval!)
    }
    
    func cancel() {
        self.stop()
    }
    
    var isActive: Bool {
        self.sink != nil
    }
}
