// https://www.reddit.com/r/swift/comments/154edey/new_to_swiftui_how_exactly_does_binding_and/

import SwiftUI
import OSLog
import Combine
//
//class EnvVar<B: Equatable, Group>: Equatable, ObservableObject {
//    static func == (lhs: EnvVar<B, Group>, rhs: EnvVar<B, Group>) -> Bool {
//        return lhs.wrappedValue == rhs.wrappedValue
//    }
//    
//    private let get: () -> B
//    private let set: (B) -> Void
//    
//    var wrappedValue: B {
//        get { self.get() }
//        set {
//            self.set(newValue)
//            self.objectWillChange.send()
//        }
//    }
//
//    init(get: @escaping () -> B, set: @escaping (B) -> Void) {
//        self.get = get
//        self.set = set
//    }
//}
//
//class EnvBinding<B: Equatable, Identifier>: Equatable, ObservableObject {
//    static func == (lhs: EnvBinding<B, Identifier>, rhs: EnvBinding<B, Identifier>) -> Bool {
//        return lhs.binding.wrappedValue == rhs.binding.wrappedValue
//    }
//    
//    @Published var binding: Binding<B>
//    
//    var wrappedValue: B { binding.wrappedValue }
//    var projectedValue: Binding<B> { binding }
//
//    init(_ binding: Binding<B>) {
//        self.binding = binding
//    }
//}
//
//protocol EnvRegistryValue<T>: AnyObject {
//    associatedtype T
//}
//
//struct EnvBindingRegistry {
//    static var registry = NSMapTable<NSString, AnyObject>.strongToWeakObjects()
//    
//    static func register<T>(name: String, binding: any EnvRegistryValue<T>) {
//        registry.setObject(binding, forKey: name as NSString)
//    }
//    static func get<T>(name: String) -> any EnvRegistryValue<T> {
//        return registry.object(forKey: name as NSString) as! any EnvRegistryValue<T>
//    }
//}
//@propertyWrapper
//class AppStorageEnv<T>: ObservableObject, DynamicProperty {
//    private var value: AppStorage<T>
//    
//    var wrappedValue: T {
//        get { value.wrappedValue }
//        set {
//            value.wrappedValue = newValue
//        }
//    }
//    
//    var projectedValue: Binding<T> { value.projectedValue }
//
//    init(wrappedValue: T, _ name: String) where T == Bool {
//        self.value = AppStorage(wrappedValue: wrappedValue, name)
//    }
//}
//
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
