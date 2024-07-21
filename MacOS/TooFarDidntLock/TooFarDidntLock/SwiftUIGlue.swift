import SwiftUI
import OSLog
import Combine

class EnvVar<B: Equatable>: Equatable, ObservableObject {
    static func == (lhs: EnvVar<B>, rhs: EnvVar<B>) -> Bool {
        return lhs.wrappedValue == rhs.wrappedValue
    }
    
    @Published var wrappedValue: B

    init(_ value: B) {
        self.wrappedValue = value
    }
}

struct OptionalModel<A: Equatable>: Equatable {
    var value: A? = nil
}
//class OptionalModel<A: Equatable>: Equatable, ObservableObject {
//    static func == (lhs: OptionalModel<A>, rhs: OptionalModel<A>) -> Bool {
//        return lhs.value == rhs.value
//    }
//    
//    init(_ value: A? = nil) {
//        self.value = value
//    }
//    
//    @Published var value: A? {
//        didSet {
//            DispatchQueue.main.async {
//                self.objectWillChange.send()
//            }
//        }
//    }
//}

class ListModel<A: Equatable>: ObservableObject, Equatable {
    static func == (lhs: ListModel<A>, rhs: ListModel<A>) -> Bool {
        lhs.values == rhs.values
    }
    
    init(_ values: [A] = []) {
        self.values = values
    }
    
    @Published var values: [A] {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}

func bindOpt<T>(_ lhs: Binding<Optional<T>>, _ rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}
func bindDecimal(_ lhs: Binding<Decimal>) -> Binding<Float> {
    Binding(
        get: { NSDecimalNumber(decimal: lhs.wrappedValue).floatValue },
        set: { lhs.wrappedValue = Decimal(floatLiteral: Double($0)) }
    )
}
func bindIntAsDouble(_ intBinding: Binding<Int>) -> Binding<Double> {
    Binding(
        get: { Double(intBinding.wrappedValue) },
        set: { intBinding.wrappedValue = Int($0) }
    )
}
func bindIntAtScale(_ intBinding: Binding<Int>, steps: Int, scale: @escaping (Int) -> Int) -> Binding<Int> {
    Binding(
        get: { intBinding.wrappedValue },
        set: { intBinding.wrappedValue = scale($0) }
    )
}

func bindPublisher<Output, P: Publisher<Output, Never>>(_ publisher: P) -> Binding<Output> where P.Output == Output, P.Failure == Never {
    var cancelable: AnyCancellable?
    var latestValue: Output?
    cancelable = publisher.sink(receiveCompletion: { completion in
        cancelable?.cancel()
    }, receiveValue: { output in
        latestValue = output
    })
    return Binding<Output>(
        // don't care about races
        get: {latestValue!},
        set: {_ in}
    )
}

/*
 Sometimes you code just for fun
 Even if it's wrong to see it run
 To learn from what you've done
 
 Debouncing alternative to @State: intermediate updates are dropped.
 Views are presented with the debounced value via projectedValue
 Controllers access the realtime value via wrappedValue
 */
@propertyWrapper
struct Debounced<T>: DynamicProperty {
    private let timer: Timed
    @State private var cancellable: AnyCancellable?

    @State private var debouncedValue: T
    @State private var latestValue: T
    
    var wrappedValue: T {
        get { latestValue }
        nonmutating set {
            if cancellable == nil {
                self.cancellable = timer.sink(receiveValue: {_ in self.debouncedValue = latestValue})
            }
            if !timer.isActive() {
                self.debouncedValue = latestValue
                timer.start(interval: 1)
            }
            latestValue = newValue
        }
    }
    
    var projectedValue: Binding<T> {
        Binding(
            get: {debouncedValue},
            set: { newValue in
                assert(false)
            }
        )
    }
    
    init(wrappedValue: T, interval: TimeInterval) {
        self.debouncedValue = wrappedValue
        self.timer = Timed(interval: interval)
        self.latestValue = wrappedValue
    }
}
