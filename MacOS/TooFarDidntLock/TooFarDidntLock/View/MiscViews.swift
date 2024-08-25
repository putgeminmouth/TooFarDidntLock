import SwiftUI

struct LabeledView<Content: View>: View {
    @State var label: String
    @State var horizontal: Bool = true
    @State var description: String?
    @State var descriptionShowing: Bool = false
    let content: Content
    
    init(label: String, horizontal: Bool, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = horizontal
        self.description = description
        self.content = content()
    }
    init(horizontal label: String, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = true
        self.description = description
        self.content = content()
    }
    init(vertical label: String, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = false
        self.description = description
        self.content = content()
    }

    var body: some View {
        let info = Image(systemName: description != nil ? "info.circle" : "")
            .frame(width: 0, height: 0)
            .onTapGesture {
                descriptionShowing.toggle()
            }
            .popover(isPresented: $descriptionShowing) {
                HStack(alignment: .top) {
                    Text(description!)
                        .frame(width: 200)
//                                    .fixedSize(horizontal: true, vertical: true)
//                                    .lineLimit(nil)
//                        .fixedSize(horizontal: true, vertical: true)
//                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
//                .frame(maxHeight: 300)
            }
        VStack(alignment: .leading) {
            if horizontal {
                HStack(alignment: .top) {
                    Text(label)
                    info
                    content
                }
            } else {
                VStack(alignment: .leading) {
                    Text(label)
                    info
                    content
                }
            }
        }
    }
}

struct LabeledIntSlider: View {
    
    var label: String
    let description: String?
    @Binding var value: Int
    let `in`: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    var body: some View {
        LabeledView(label: label, horizontal: true, description: description) {
            Slider(value: $value, in: `in`, step: step)
            Text(format(value))
                .frame(minWidth: 50, alignment: .trailing)
        }
    }
}
struct LabeledDoubleSlider: View {
    
    var label: String
    let description: String?
    @Binding var value: Double
    let `in`: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        LabeledView(label: label, horizontal: true, description: description) {
            if let step = step {
                Slider(value: $value, in: `in`, step: step)
            } else {
                Slider(value: $value, in: `in`)
            }
            Text(format(value))
                .frame(minWidth: 50, alignment: .trailing)
        }
    }
}
