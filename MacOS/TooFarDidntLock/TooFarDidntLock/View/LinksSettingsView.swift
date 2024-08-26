import SwiftUI

struct LinksSettingsView: View {
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel

    @State var zoneIdFilter: UUID? = nil
    @State var modalIsPresented = false
    @State var listSelection: UUID = UUID()
    @State var itemBeingEdited = OptionalModel<BluetoothLinkModel>(value: nil)
    @State var newItemTypeIsPresented = false
    @State var newItemType: String?
    
    var body: some View {
        let _ = itemBeingEdited
        let _ = newItemType
        VStack(alignment: .leading) {
            ZoneSelectionView(
                selectionCanBeNil: $zoneIdFilter,
                nilMenuText: "Filter by Zone",
                nilButtonText: "All Zones"
            )

            let data = domainModel.links
                .filter{zoneIdFilter == nil || $0.zoneId == zoneIdFilter}
                .map{ model in
                    let zone = domainModel.zones.first{$0.id == model.zoneId}
                    let device = runtimeModel.bluetoothStates.first{$0.id == model.deviceId}
                    return (id: model.id, model: model, zone: zone, device: device)
                }
            let maxZoneNameWidth = data.compactMap{$0.zone?.name}.map{estimateTextSize(text: $0).width}.max() ?? 0

            ListView(Binding.constant(data), id: \.wrappedValue.id, selection: $listSelection) { link in
                let link = link.wrappedValue
                let linkIcon = Icons.Links.of(link.model)
                let zone = link.zone
                let zoneIcon = zone.map{Icons.Zones.of($0)}
                HStack {
                    if zoneIdFilter == nil {
                        zoneIcon?.toImage()
                            .fitSizeAspect(size: 15)
                        Text("\(zone?.name ?? "")")
                            .frame(width: maxZoneNameWidth, alignment: .leading)
                        Divider()
                    }
                    linkIcon.toImage()
                        .fitSizeAspect(size: 15)
                    Text("\(link.device?.name ?? "")")
                    Spacer()
                    Button("", systemImage: "trash") {
                        domainModel.links.removeAll{$0.id == link.id}
                    }.myButtonStyle()
                }
                .padding([.leading, .trailing], 3)
                .padding([.top, .bottom], 5)
                .contentShape(Rectangle()) // makes even empty space clickable
                .onTapGesture(count: 2) {
                    itemBeingEdited.value = link.model
                    modalIsPresented = true
                }
            }
            
            if let zoneIdFilter = zoneIdFilter ?? domainModel.zones.first.map{$0.id} {
                Text("")
                    .sheet(isPresented: $modalIsPresented) {
                        let _ = assert(newItemType == nil || newItemType == "Bluetooth")
                        EditBluetoothDeviceLinkModal(zoneId: zoneIdFilter, initialValue: itemBeingEdited.value, onDismiss: { link in
                            if let link = link {
                                domainModel.links.updateOrAppend({link}, where: {$0.id == link.id})
                            }
                            modalIsPresented = false
                        })
                            .frame(minWidth: 700)
                            .padding()
                    }
            }

            HStack {
                Spacer()
                
                Button {
                    newItemTypeIsPresented = true
                } label: {
                    Image(systemName: "plus")
                        .myButtonLabelStyle()
                }
                .myButtonStyle()
                .popover(isPresented: $newItemTypeIsPresented) {
                    VStack(alignment: .leading) {
                        Button {
                            newItemType = "Bluetooth"
                            modalIsPresented = true
                        } label: {
                            Label(title: {Text("Bluetooth")}, icon: {Icons.bluetooth.toImage().fitSizeAspect(size: 15)})
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .myButtonLabelStyle()
                        }
                        .myButtonStyle()
                        .padding(1)
                    }.padding(7)
                }
            }
        }
    }
}

