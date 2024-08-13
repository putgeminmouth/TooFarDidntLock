import SwiftUI
import OSLog
import CoreWLAN

struct Icons {
    static let zone = "mappin.and.ellipse"
    struct Zones {
        static let manual = "lightswitch.on"
        static let wifi = "wifi"
        static func of(_ zone: any Zone) -> String {
            if zone is ManualZone { return manual }
            if zone is WifiZone { return wifi }
            return ""
        }
    }
}

struct ActiveIcon: View {
    @Binding var active: Bool
    
    private var systemName: String {
        if active {
            return "dot.circle"
        } else {
            return "circle"
        }
    }
    
    var body: some View {
        Image(systemName: systemName)
            .foregroundColor(active ? Color.green : Color.gray)
    }
}

struct ZoneMenuItemView: View {
    @Binding var zone: any Zone

    var body: some View {
        Group {
            if zone is ManualZone {
                ManualZoneMenuItemView(zone: bindAs($zone))
            } else if zone is WifiZone {
                WifiZoneMenuItemView(zone: bindAs($zone))
            } else {
                let _ = assert(false)
                EmptyView()
            }
        }
    }
}

struct ManualZoneMenuItemView: View {
    @EnvironmentObject var zoneEvaluator: ZoneEvaluator

    @Binding var zone: ManualZone
    var body: some View {
        HStack {
            Image(systemName: Icons.Zones.manual)
            Text("\(zone.name)")
        }
    }
}

struct WifiZoneMenuItemView: View {
    @EnvironmentObject var zoneEvaluator: ZoneEvaluator

    @Binding var zone: WifiZone
    var body: some View {
        HStack {
            Image(systemName: Icons.Zones.wifi)
            Text("\(zone.name)")
        }
    }
}

struct ZoneListItemView: View {
    @Binding var zone: any Zone

    var body: some View {
        Group {
            if zone is ManualZone {
                ManualZoneListItemView(zone: bindAs($zone))
            } else if zone is WifiZone {
                WifiZoneListItemView(zone: bindAs($zone))
            } else {
                let _ = assert(false)
                EmptyView()
            }
        }
    }
}

struct ManualZoneListItemView: View {
    @EnvironmentObject var zoneEvaluator: ZoneEvaluator

    @Binding var zone: ManualZone
    var body: some View {
        HStack {
            Image(systemName: Icons.Zones.manual)
                .help("Manual")
                .frame(minWidth: 20)
                .padding(3)
                .background(Color.gray.opacity(0.5))
                .cornerRadius(4)
            Text("\(zone.name)")
            Toggle("", isOn: $zone.active)
                .toggleStyle(.switch)
            Spacer()
            ActiveIcon(active: Binding.constant(zoneEvaluator.isActive(zone)))
                .help(zoneEvaluator.isActive(zone) ? "Zone is active" : "Zone is inactive")
        }
    }
}

struct WifiZoneListItemView: View {
    @EnvironmentObject var zoneEvaluator: ZoneEvaluator

    @Binding var zone: WifiZone
    var body: some View {
        HStack {
            Image(systemName: Icons.Zones.wifi)
                .help("Wifi")
                .frame(minWidth: 20)
                .padding(3)
                .background(Color.gray.opacity(0.5))
                .cornerRadius(4)
            Text("\(zone.name)")
            Text(zone.ssid ?? "Unknown")
                .italic(zone.ssid == nil)
            Text(zone.bssid ?? "Unknown")
                .italic(zone.ssid == nil)
            Spacer()
            ActiveIcon(active: bindFunc({zoneEvaluator.isActive(zone)}))
                .help(zoneEvaluator.isActive(zone) ? "Zone is active" : "Zone is inactive")
        }
    }
}

struct ZoneEditView: View {
    @State var zone: any Zone
    var interfaces: [CWInterface]
    @State var onchange: (any Zone) -> Void
    init(zone: any Zone, interfaces: [CWInterface], onchange: @escaping (any Zone) -> Void) {
        self.zone = zone
        self.interfaces = interfaces
        self.onchange = onchange
    }
    
    var body: some View {
        Group {
            if zone is ManualZone {
                ManualZoneEditView(zone: bindAs($zone), onchange: self.onchange)
            } else if zone is WifiZone {
                WifiZoneEditView(zone: bindAs($zone), interfaces: interfaces, onchange: self.onchange)
            } else {
                let _ = assert(false)
                EmptyView()
            }
        }
    }
}

struct ManualZoneEditView: View {
    @Binding var zone: ManualZone
    @State var onchange: (ManualZone) -> Void
    init(zone: Binding<ManualZone>, onchange: @escaping (ManualZone) -> Void) {
        self._zone = zone
        self.onchange = onchange
    }

    var body: some View {
        VStack(alignment: .leading) {
            LabeledView(horizontal: "Name") {
                TextField("Name", text: $zone.name)
                    .validate(onChangeOf: $zone.name, validator: {
                        guard !zone.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else { return [Validation(message: "Name cannot be empty")] }
                        return []
                    })
            }
            LabeledView(horizontal: "Active") {
                Toggle("", isOn: $zone.active)
                    .toggleStyle(.switch)
            }
        }
        .onChange(of: zone) {
            self.onchange(zone)
        }
    }
}

struct WifiZoneEditView: View {
    @Binding var zone: WifiZone
    var interfaces: [CWInterface]
    @State var onchange: (WifiZone) -> Void
    init(zone: Binding<WifiZone>, interfaces: [CWInterface], onchange: @escaping (WifiZone) -> Void) {
        self._zone = zone
        self.interfaces = interfaces
        self.onchange = onchange
    }

    var body: some View {
        VStack(alignment: .leading) {
            LabeledView(horizontal: "Name") {
                TextField("", text: $zone.name)
                    .validate(onChangeOf: $zone.name, validator: {
                        guard !zone.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else { return [Validation(message: "Name cannot be empty")] }
                        return []
                    })
            }
            LabeledView(horizontal: "Network") {
                Menu("\(zone.ssid ?? "Choose")") {
                    ForEach(interfaces, id: \.self) { itf in
                        Button("\(itf.ssid() ?? "Unknown")"){}
                            .italic(zone.ssid == nil)
                    }
                }
            }
            LabeledView(horizontal: "BSSID") {
                Text(zone.bssid ?? "Unknown")
                    .italic(zone.ssid == nil)
            }
        }
        .onChange(of: zone) {
            self.onchange(zone)
        }
    }
}

struct ZoneSettingsView: View {
    let logger = Log.Logger("ZoneSettingsView")

    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var wifiScanner: WifiScanner

    @State var name: String = ""
    @State var itemBeingEdited: (any Zone)?
    @State var newItemTypeIsPresented = false
    @State var newItemIsPresented = false
    @State var editIsPresented = false
    @State var hover: UUID? = nil

    @EnvironmentObject var zoneEvaluator: ZoneEvaluator

    func newZone(_ zoneType: String) -> (any Zone)? {
        if zoneType == "Manual" {
            let name = [
                self.name,
                "New Manual"
            ].map{ZoneSettingsView.sanitizeName($0)}.first{!$0.isEmpty}!
            return ManualZone(id: UUID(), name: name, active: false)
        } else if zoneType == "Wifi" {
            let intf = wifiScanner.activeWiFiInterfaces().first
            let ssid = intf?.ssid()
            let name = [
                self.name,
                ssid ?? "",
                "New Wifi"
            ].map{ZoneSettingsView.sanitizeName($0)}.first{!$0.isEmpty}!
            return WifiZone(id: UUID(), name: name, ssid: ssid, bssid: intf?.bssid())
        } else {
            return nil
        }
        
    }
    
    static func sanitizeName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            let _ = itemBeingEdited
            ForEach($domainModel.zones, id: \.id) { zone in
                VStack(alignment: .leading) {
                    HStack {
                        ZoneListItemView(zone: zone)
                        
                        Spacer()
                        
                        Button("", systemImage: "trash") {
                            if domainModel.zones.count > 1, let index = domainModel.zones.firstIndex{$0.id == zone.wrappedValue.id} {
                                domainModel.zones.remove(at: index)
                            }
                        }.buttonStyle(PlainButtonStyle())
                            .disabled(domainModel.zones.count <= 1)
                            .help(domainModel.zones.count <= 1 ? "Must have at least one Zone" : "")
                    }
                }
                .background(hover == zone.wrappedValue.id ? Color.gray.opacity(0.3) : Color.clear)
                .onHover { hovering in
                    self.hover = hovering ? zone.wrappedValue.id : nil
                }
                .onTapGesture(count: 2) {
                    itemBeingEdited = zone.wrappedValue
                    editIsPresented = true
                }
            }
            .sheet(isPresented: $editIsPresented) {
                VStack {
                    ZoneEditView(zone: itemBeingEdited!, interfaces: wifiScanner.activeWiFiInterfaces()) { update in
                        itemBeingEdited = update
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            itemBeingEdited = nil
                            editIsPresented = false
                        }
                        Button("OK") {
                            if let index = domainModel.zones.firstIndex{$0.id == itemBeingEdited?.id} {
                                domainModel.zones[index] = itemBeingEdited!
                            } else {
                                assert(false)
                            }
                            itemBeingEdited = nil
                            editIsPresented = false
                        }
                    }
                }
                .padding(10)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 200)
            }

            HStack {
                Spacer()
                
                Button("", systemImage: "plus") {
                    newItemTypeIsPresented = true
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $newItemTypeIsPresented) {
                    VStack(alignment: .leading) {
                        Button("Manual", systemImage: Icons.Zones.manual) {
                            newItemIsPresented = true
                            itemBeingEdited = newZone("Manual")!
                        }
                            .buttonStyle(PlainButtonStyle())
                            .padding(1)
                        Button("Wifi", systemImage: Icons.Zones.wifi) {
                            newItemIsPresented = true
                            itemBeingEdited = newZone("Wifi")!
                        }
                            .buttonStyle(PlainButtonStyle())
                            .padding(1)
                    }.padding(7)
                }.sheet(isPresented: $newItemIsPresented) {
                    VStack {
                        ZoneEditView(zone: itemBeingEdited!, interfaces: wifiScanner.activeWiFiInterfaces()) { update in
                            itemBeingEdited = update
                        }
                        
                        HStack {
                            Spacer()
                            Button("Cancel") {
                                newItemIsPresented = false
                            }
                            Button("OK") {
                                if itemBeingEdited.map{ZoneSettingsView.sanitizeName($0.name)}?.isEmpty ?? false {
                                    return
                                }
                                domainModel.zones = domainModel.zones + [itemBeingEdited!]
                                newItemIsPresented = false
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }
}
