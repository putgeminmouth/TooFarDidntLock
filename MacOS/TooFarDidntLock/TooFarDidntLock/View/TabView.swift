import Foundation
import SwiftUI

struct ATab: View {
    let label: String
    let image: Image
    let content: AnyView
    
    init(_ label: String, systemName: String, @ViewBuilder content: @escaping () -> any View) {
        self.init(label, image: Image(systemName: systemName), content: content)
    }
    init(_ label: String, resource: String, @ViewBuilder content: @escaping () -> any View) {
        self.init(label, image: Image(resource), content: content)
    }
    init(_ label: String, image: Image, @ViewBuilder content: @escaping () -> any View) {
        self.label = label
        self.image = image
        self.content = AnyView(content())
    }
    
    var body: some View {
        content
    }
}

struct ATabView: View {
    let tabs: [ATab]
    @State private var selectedTab = 0
    
    init(@ViewBuilder _ content: @escaping () -> TupleView<(ATab, ATab, ATab, ATab)>) {
        let (c1,c2, c3, c4) = content().value
        self.tabs = [c1, c2, c3, c4]
    }

    var body: some View {
        VStack() {
            HStack {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Button(action: {
                        selectedTab = index
                    }) {
                        VStack(alignment: .center) {
                            tabs[index].image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                            Text(tabs[index].label)
                                .font(.caption)
                        }
                        .colorMultiply(selectedTab == index ? .blue : .white)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()

            // setting the scrollview to match heigh is important, otherwise
            // some views won't properly calcualte, e.g. List
            GeometryReader { g in
                ScrollView {
                    ZStack {
                        tabs[selectedTab].content
                            .padding()
                    }.frame(width: g.size.width, height: g.size.height, alignment: .top)
                }.frame(width: g.size.width, height: g.size.height)
            }
            Spacer() // needed?
        }
    }
}
