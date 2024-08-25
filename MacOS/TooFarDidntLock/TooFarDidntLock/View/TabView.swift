import Foundation
import SwiftUI

enum TabContent {
    case tab(label: String, icon: Image, _ content: () -> any View)
    case divider
}

struct Tab: View {
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

struct TabView: View {
    let tabs: [TabContent]
    @State private var selectedTab = 0
    
    init(_ content: @escaping () -> [TabContent]) {
        self.tabs = content()
    }

    var body: some View {
        VStack() {
            HStack {
                ForEach(0..<tabs.count, id: \.self) { index in
                    switch tabs[index] {
                    case .tab(let label, let icon, _):
                        Button(action: {
                            selectedTab = index
                        }) {
                            VStack(alignment: .center) {
                                icon
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 30, height: 30)
                                Text(label)
                                    .font(.caption)
                            }
                            .colorMultiply(selectedTab == index ? .blue : .white)
                        }
                        .buttonStyle(PlainButtonStyle())
                    case .divider:
                        Divider()
                            .frame(height: 30)
                    }
                }
            }
            .padding()

            // setting the scrollview to match heigh is important, otherwise
            // some views won't properly calcualte, e.g. List
            GeometryReader { g in
                ScrollView {
                    ZStack {
                        if case let .tab(_, _, content) = tabs[selectedTab] {
                            AnyView(content())
                                .padding()
                        }
                    }.frame(width: g.size.width, height: g.size.height, alignment: .top)
                }.frame(width: g.size.width, height: g.size.height)
            }
            Spacer() // needed?
        }
    }
}
