import SwiftUI

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
