
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
