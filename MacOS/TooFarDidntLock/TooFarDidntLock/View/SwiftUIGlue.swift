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
    static func == (lhs: OptionalModel<A>, rhs: OptionalModel<A>) -> Bool {
        return lhs.value == rhs.value
    }
    
    var value: A? = nil
}

struct Model<A: Equatable>: Equatable {
    static func == (lhs: Model<A>, rhs: Model<A>) -> Bool {
        return lhs.value == rhs.value
    }
    
    var value: A
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

func bindFunc<T>(_ f: @escaping () -> T) -> Binding<T> {
    Binding(
        get: { f() },
        set: { _ in }
    )
}
func bindOpt<T>(_ lhs: Binding<Optional<T>>, _ rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}
//func bindOpt<T>(_ lhs: Binding<OptionalModel<T>>, _ rhs: T) -> Binding<T> {
//    Binding(
//        get: { lhs.wrappedValue.value ?? rhs },
//        set: { lhs.wrappedValue.v = $0 }
//    )
//}
func bindOpt<T,R>(_ lhs: Binding<OptionalModel<T>>, _ get: @escaping (T?) -> R, _ set : @escaping (inout OptionalModel<T>,R) -> Void) -> Binding<R> {
    Binding(
        get: { get(lhs.wrappedValue.value) },
        set: { lhs.wrappedValue.value != nil ? set(&lhs.wrappedValue, $0) : () }
    )
}
func bindAs<A,B>(_ bind: Binding<A>) -> Binding<B> {
    Binding(
        get: { bind.wrappedValue as! B },
        set: { bind.wrappedValue = $0 as! A }
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

struct Validation: Hashable, Equatable {
    let message: String
}

struct ValidationModifier<T>: ViewModifier where T: Equatable {
    typealias Validator = () -> [Validation]
    
    @Binding var value: T
    var validator: Validator
    @State var isValid = false
    @State var isPopoverPresented = false
    @State var errors = [Validation]()

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPopoverPresented) {
                Group {
                    VStack {
                        ForEach(errors, id: \.self) { error in
                            Text("❌ \(error.message)")
                        }
                    }
                }.onTapGesture {
                    isPopoverPresented = false
                }.padding(10)
            }
            .onChange(of: value, initial: true) { (_,_) in
                self.errors = validator()
                isValid = errors.isEmpty
                isPopoverPresented = !isValid
            }
            .border(Color.red, width: isValid ? 0 : 2)
    }
}
extension View {
    func validate<T: Equatable>(onChangeOf value: Binding<T>, validator: @escaping () -> [Validation]) -> some View {
        self.modifier(ValidationModifier(value: value, validator: validator))
    }
}

struct MyButtonStyleModifier: ViewModifier {
    @State var hover = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .onHover { hover in self.hover = hover }
            .background(hover ? Color.gray.opacity(0.3) : Color.clear)
            .cornerRadius(8)
    }
}
extension View {
    func myButtonStyle() -> some View {
        self.modifier(MyButtonStyleModifier())
    }
    func myButtonLabelStyle() -> some View {
        self
            // these must apply to the button's label...
            .padding(5)
            .contentShape(RoundedRectangle(cornerRadius: 8)) // makes even padding clickable
    }
}

struct ListView<Content: View, ID, Data: MutableCollection & RandomAccessCollection>: View where ID: Hashable {
    enum Selection {
        case none
        case single
        case multi
    }
    @Binding var data: Data
    @Binding var selectionBinding: Any
    var selectionMode: Selection = .none
    let id: KeyPath<Binding<Data.Element>, ID>
    let content: (Binding<Data.Element>) -> Content

    @State var hoverId: ID?
    
    init(_ data: Binding<Data>, 
         id: KeyPath<Binding<Data.Element>, ID>,
         @ViewBuilder content: @escaping (Binding<Data.Element>) -> Content) {
        self._data = data
        self.id = id
        self.content = content
        self._selectionBinding = Binding.constant(Set<ID>())
    }
    init(_ data: Binding<Data>, 
         id: KeyPath<Binding<Data.Element>, ID>,
         selection: Binding<ID>,
         @ViewBuilder content: @escaping (Binding<Data.Element>) -> Content) {
        self._data = data
        self.id = id
        self.content = content

        self._selectionBinding = bindAs(selection)
        selectionMode = .single
    }
    init(_ data: Binding<Data>, 
         id: KeyPath<Binding<Data.Element>, ID>,
         selection: Binding<Set<ID>>,
         @ViewBuilder content: @escaping (Binding<Data.Element>) -> Content) {
        self._data = data
        self.id = id
        self.content = content

        self._selectionBinding = bindAs(selection)
        selectionMode = .multi
    }
    func list(@ViewBuilder _ content: @escaping (Binding<Data.Element>) -> some View) -> some View {
        Group {
            if selectionMode == .multi {
                List($data, id: id, selection: bindAs($selectionBinding) as Binding<Set<ID>>, rowContent: content)
                    // fixes layout in .sheet, maybe others
                    .frame(idealWidth: .infinity, idealHeight: .infinity)
            } else if selectionMode == .single {
                List($data, id: id, selection: bindAs($selectionBinding) as Binding<ID>, rowContent: content)
                    .frame(idealWidth: .infinity, idealHeight: .infinity)
            } else {
                List($data, id: id, rowContent: content)
                    .frame(idealWidth: .infinity, idealHeight: .infinity)
            }
        }
    }
    var body: some View {
        list { item in
            content(item)
                .background(hoverId == item[keyPath: id] ? Color.gray.opacity(0.3) : Color.clear)
                .onHover { hovering in
                    self.hoverId = hovering ? item[keyPath: id] : nil
                }
        }
    }
}

func estimateTextSize(text: String, font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)) -> CGSize {
    let attributes = [NSAttributedString.Key.font: font]
    let size = (text as NSString).size(withAttributes: attributes)
    return size
}

extension Image {
    func fitSizeAspect(size: Float) -> some View {
        self
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: CGFloat(size), height: CGFloat(size))
    }
}
