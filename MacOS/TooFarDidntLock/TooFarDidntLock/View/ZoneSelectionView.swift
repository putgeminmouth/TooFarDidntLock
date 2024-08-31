import SwiftUI
import Combine

struct ZoneSelectionView: View {
    @EnvironmentObject var domainModel: DomainModel

    var nilMenuText = "Choose a Zone"
    var nilButtonText = "None"
    
    @Binding var selection: UUID?
    var allowNil = false
    
    init(selectionCanBeNil: Binding<UUID?>,
         nilMenuText: String? = nil,
         nilButtonText: String? = nil) {
        self._selection = selectionCanBeNil
        allowNil = true
        
        nilMenuText.map{self.nilMenuText = $0}
        nilButtonText.map{self.nilButtonText = $0}
    }
    init(selectionCanStartNil: Binding<UUID?>,
         nilMenuText: String? = nil,
         nilButtonText: String? = nil) {
        self._selection = selectionCanStartNil
        allowNil = false
        
        nilMenuText.map{self.nilMenuText = $0}
        nilButtonText.map{self.nilButtonText = $0}
    }
    init(selectionNonNil: Binding<UUID>,
         nilMenuText: String? = nil,
         nilButtonText: String? = nil) {
        self._selection = bindAs(selectionNonNil)
        allowNil = false
        
        nilMenuText.map{self.nilMenuText = $0}
        nilButtonText.map{self.nilButtonText = $0}
    }
    
    var body: some View {
        let selectedZone = domainModel.zones.first{$0.id == selection}
        HStack {
            Icons.zone.toImage()
                .help("Zone")
            Menu {
                if allowNil {
                    Button {
                        selection = nil
                    } label: {
                        Text(nilButtonText)
                    }
                }
                ForEach($domainModel.zones, id: \.id) { zone in
                    Button {
                        selection = zone.wrappedValue.id
                    } label: {
                        ZoneMenuItemView(zone: zone)
                    }
                }
            } label: {
                Label(title: {Text(selectedZone.map{$0.name} ?? nilMenuText)}, icon: {selectedZone.map{Icons.Zones.of($0).toImage()} ?? Image(systemName: "")})
            }
        }
    }
}
