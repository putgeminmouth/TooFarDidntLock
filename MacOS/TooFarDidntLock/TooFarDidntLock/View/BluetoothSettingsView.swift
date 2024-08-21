import SwiftUI
import Combine
import UniformTypeIdentifiers
import OSLog
import Charts

struct BluetoothSettingsView: View {
    let logger = Log.Logger("BluetoothSettingsView")

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel

    @State var linkBeingEdited: OptionalModel<DeviceLinkModel> = OptionalModel(value: nil)

    var body: some View {
        VStack(alignment: .leading) {
            DeviceLinkSettingsView(
                deviceLinkModel: $linkBeingEdited
            )
            
            Spacer()
            
            AvailableDevicesSettingsView(selectedId: Binding.constant(UUID()))
        }
        .onChange(of: linkBeingEdited) { (old, new) in
            if let index = domainModel.links.firstIndex{$0.id == new.value?.id} {
                domainModel.links[index] = new.value!
            }
        }
        .onAppear() {
            // this updates the domainModel but who cares, also this is a temp hax
            if let link = domainModel.links.first {
                linkBeingEdited.value = link
            } else {
                linkBeingEdited.value = nil
            }
        }
        
    }
}

struct DeviceView: View {
    @Binding var uuid: String?
    @Binding var name: String?
    @Binding var rssi: Double?
    @Binding var lastSeenAt: Date?

    var body: some View {
        VStack(alignment: .leading) {
            Text("UUID: \(uuid ?? "00000000-0000-0000-0000-000000000000")")
            Text("Name: \(name ?? "")")
            Text("RSSI: \(rssi ?? 0)")
            if let lastSeenAt = lastSeenAt { Text("Latency: \(lastSeenAt.distance(to: Date.now))s") }
        }
    }
}

struct BluetoothDevicesListView: View {

    @EnvironmentObject var runtimeModel: RuntimeModel

    @Binding var selectedId: UUID
    @Binding var showOnlyNamedDevices: Bool
    var callback: ((AnyView, MonitoredPeripheral) -> AnyView)?
    
    init(selectedId: Binding<UUID>, showOnlyNamedDevices: Binding<Bool>, items: ((AnyView, MonitoredPeripheral) -> AnyView)? = nil) {
        self._selectedId = selectedId
        self._showOnlyNamedDevices = showOnlyNamedDevices
        self.callback = items
    }

    var body: some View {
        let availableDevices = runtimeModel.bluetoothStates
        let items = showOnlyNamedDevices ? availableDevices.filter{$0.name?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 0} : availableDevices
        ListView(Binding.constant(items), id: \.wrappedValue.id, selection: $selectedId) { device in
            let device = device.wrappedValue
            let row = HStack {
                DeviceView(
                    uuid: Binding.constant(device.id.uuidString),
                    name: Binding.constant(device.name),
                    rssi: Binding.constant(device.lastSeenRSSI),
                    lastSeenAt: Binding.constant(nil))
                // make row occupy full width
                Spacer()
                EmptyView()
            }
            if let callback = callback {
                callback(AnyView(row), device)
            } else {
                row
            }
        }
    }
    
}
struct AvailableDevicesSettingsView: View {

    @EnvironmentObject var runtimeModel: RuntimeModel

    @AppStorage("uipref.bluetooth.showOnlyNamedDevices") var showOnlyNamedDevices: Bool = true
    
    @Binding var selectedId: UUID
    
    var body: some View {
        Group() {
            VStack {
                HStack {
                    Text("Scanning for available devices...")
                    Spacer()
                    Toggle(isOn: $showOnlyNamedDevices) {
                        Label("Show only named devices", systemImage: "")
                    }
                }
                BluetoothDevicesListView(selectedId: $selectedId, showOnlyNamedDevices: $showOnlyNamedDevices) { row, device in
                    AnyView(
                        row
                            .onDrag({ NSItemProvider(object: device.id.uuidString as NSString) })
                    )
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct DeviceMonitorView: View {
    enum ChartType: CaseIterable {
        case rssiRaw
        case rssiSmoothed
        case distance
    }

//    @Binding var deviceLinkModel: OptionalModel<DeviceLinkModel>
    @Binding var linkedDeviceRSSIRawSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceRSSISmoothedSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceDistanceSamples: [Tuple2<Date, Double>]

    @State var linkedDeviceChartType = ChartType.distance
    
    @State var chartTypeAdjustedSamples: [Tuple2<Date, Double>] = []
    @State var chartTypeAdjustedYMin: Double = 0
    @State var chartTypeAdjustedYMax: Double = 0
    @State var chartTypeAdjustedYLastUpdated = Date()

    var body: some View {
        VStack(alignment: .leading) {
            Picker(selection: $linkedDeviceChartType, label: EmptyView()) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    switch type {
                    case .rssiRaw:
                        Text("Raw signal power (decibels)").tag(type)
                    case .rssiSmoothed:
                        Text("Smoothed signal power (decibels)").tag(type)
                    case .distance:
                        Text("Calculated Distance (meters)").tag(type)
                    }
                }
            }
            ZStack {
                LineChart(
                    samples: $chartTypeAdjustedSamples,
                    xRange: 60,
                    yAxisMin: $chartTypeAdjustedYMin,
                    yAxisMax: $chartTypeAdjustedYMax)
            }
        }
        .onChange(of: linkedDeviceRSSIRawSamples, initial: true) {
            recalculate()
            if chartTypeAdjustedSamples.count < 3 {
                let (_, _, ymin, ymax) = calcBounds(chartTypeAdjustedSamples)
                chartTypeAdjustedYMin = ymin
                chartTypeAdjustedYMax = ymax
            }
        }
        .onChange(of: linkedDeviceChartType) {
            recalculate()
            let (_, _, ymin, ymax) = calcBounds(chartTypeAdjustedSamples)
            chartTypeAdjustedYMin = ymin
            chartTypeAdjustedYMax = ymax
        }
    }
    func calcBounds(_ samples: [Tuple2<Date, Double>]) -> (sampleMin: Double, sampleMax: Double, ymin: Double, ymax: Double) {
        let stddev = samples.map{$0.b}.standardDeviation()
        let sampleMin = samples.min(by: {$0.b < $1.b})?.b ?? 0
        let sampleMax = samples.max(by: {$0.b < $1.b})?.b ?? 0
        let ymin = sampleMin - stddev * 1
        let ymax = sampleMax + stddev * 1
        return (sampleMin: sampleMin, sampleMax: sampleMax, ymin: ymin, ymax: ymax)
    }
    func smoothInterpolateBounds(_ samples: [Tuple2<Date, Double>]) {
        let (sampleMin, sampleMax, ymin, ymax) = calcBounds(samples)

        let chartTypeAdjustedYShouldUpdate = chartTypeAdjustedYLastUpdated.distance(to: Date.now) > 5

        if chartTypeAdjustedYShouldUpdate {
            chartTypeAdjustedYLastUpdated = Date.now
            let a = 0.5
            let b = 1-a

            chartTypeAdjustedYMin = chartTypeAdjustedYMin * a + ymin * b
            chartTypeAdjustedYMax = chartTypeAdjustedYMax * a + ymax * b
        }
        chartTypeAdjustedYMin = min(sampleMin, chartTypeAdjustedYMin)
        chartTypeAdjustedYMax = max(sampleMax, chartTypeAdjustedYMax)
    }
    func recalculate() {
        switch linkedDeviceChartType {
        case .rssiRaw:
            let samples = linkedDeviceRSSIRawSamples
            smoothInterpolateBounds(samples)
            chartTypeAdjustedSamples = samples
        case .rssiSmoothed:
            let samples = linkedDeviceRSSISmoothedSamples
            smoothInterpolateBounds(samples)
            chartTypeAdjustedSamples = samples
        case .distance:
            let samples = linkedDeviceDistanceSamples
            smoothInterpolateBounds(samples)
            chartTypeAdjustedYMin = max(0, chartTypeAdjustedYMin)
            chartTypeAdjustedSamples = samples
        }
    }
}

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

struct DeviceLinkSettingsView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel
    
    @Binding var deviceLinkModel: OptionalModel<DeviceLinkModel>
    
    var body: some View {
        let deviceLinkModel = deviceLinkModel.value
        let linkedDevice = runtimeModel.bluetoothStates.first{$0.id == deviceLinkModel?.deviceId}
        let linkState = runtimeModel.linkStates.first{$0.id == deviceLinkModel?.id}.map{$0 as! DeviceLinkState}
        let availableDevices = runtimeModel.bluetoothStates
        let linkedZone: Binding<UUID?> = bindOpt(self.$deviceLinkModel,
                                                 {$0?.zoneId},
                                                 {$0.value?.zoneId = $1!})
        VStack(alignment: .leading) {
            Text("Drag and drop a device from the list here to link it.")
            GroupBox(label: Label("Linked device", systemImage: "")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            ZoneSelectionView(
                                selectionCanStartNil: linkedZone,
                                nilMenuText: "Choose a Zone"
                            )
                            DeviceView(
                                uuid: Binding.constant(linkedDevice?.id.uuidString),
                                name: Binding.constant(linkedDevice?.name),
                                rssi: Binding.constant(linkedDevice?.lastSeenRSSI),
                                lastSeenAt: Binding.constant(linkedDevice?.lastSeenAt))
                                .padding(4)
                                .border(Color.gray, width: 1)
                                .cornerRadius(2)
                        }
                        LabeledDoubleSlider(
                            label: "Reference Power",
                            description: "Set to the signal power at 1 meter.",
                            value: bindOpt($deviceLinkModel,
                                           {$0?.referencePower ?? 0.0},
                                           {$0.value!.referencePower=$1}),
                            in: -100...0, 
                            format: {"\(Int($0))"})
                        LabeledDoubleSlider(
                            label: "Max distance",
                            description: "The distance in meters at which the device is considered absent, resulting in a screen lock. It is calculated from the current signal strength and the reference power, and is not very stable or reliable. It is recommended to consider anything less than 5m as close, and anything more as far.",
                            value: bindOpt($deviceLinkModel,
                                           {$0?.maxDistance ?? 0.0},
                                           {$0.value!.maxDistance=$1}),
                            in: 0.0...9.0, step: 0.25, format: {"\(String(format: "%.2f", $0))"})
                        LabeledDoubleSlider(
                            label: "Idle timeout",
                            description: "Device is considered absent if not found for too long, resulting in a screen lock. Unless you configure an active connection, both the host and target device will scan / broadcast at intervals that may vary e.g. due to low power settings. It is recommended to set at least 10-30 seconds.",
                            value: bindOpt($deviceLinkModel,
                                           {$0?.idleTimeout ?? 0.0},
                                           {$0.value!.idleTimeout=$1}),
                            in: 0...10*60, step: 10, format: {formatMinSec(msec: $0)})
                        HStack {
                            LabeledView(
                                label: "Require connection",
                                horizontal: true,
                                description: "When active, the app will attempt to maintain a bluetooth connection to the device, reconnecting as necessary. If the connection fails, the screen will lock.") {
                                    Toggle("", isOn: bindOpt($deviceLinkModel,
                                                             {$0?.requireConnection ?? false},
                                                             {$0.value!.requireConnection=$1}))
                                }
                            Spacer()
                            Image(systemName: (linkedDevice?.connectionState != .disconnected) ? "cable.connector" : "cable.connector.slash")
                                .colorMultiply(deviceLinkModel?.requireConnection == true ? .white : .gray)
                        }
                    }
                    
                    DeviceMonitorView(
                        linkedDeviceRSSIRawSamples: Binding.constant(linkState?.rssiRawSamples ?? []),
                        linkedDeviceRSSISmoothedSamples: Binding.constant(linkState?.rssiSmoothedSamples ?? []),
                        linkedDeviceDistanceSamples: Binding.constant(linkState?.distanceSmoothedSamples ?? [])
                    )
                }
                .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                .onDrop(of: ["public.text"], isTargeted: nil) { providers in
                    self.onDeviceLinkDrop(providers)
                    return true
                }
            }
        }
    }
    
    func onDeviceLinkDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let uuidString = object as? String,
                       let deviceId = UUID(uuidString: uuidString) {
                        if let state = runtimeModel.bluetoothStates.first{$0.id == deviceId} {

                            let deviceLink = DeviceLinkModel(
                                id: UUID(),
                                zoneId: (domainModel.zones.first?.id)!,
                                deviceId: deviceId,
                                referencePower: state.lastSeenRSSI,
                                maxDistance: 1.0,
                                idleTimeout: 10,
                                requireConnection: false
                            )
                            // drop happens on some ItemProvider thread
                            DispatchQueue.main.async {
                                domainModel.links.append(deviceLink)
//                                domainModel.links = [deviceLink]
                                deviceLinkModel.value = deviceLink
                                domainModel.wellKnownBluetoothDevices.updateOrAppend(state, where: {$0.id == deviceId})
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EditBluetoothDeviceLinkModal: View {
    
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel

    let zoneId: UUID
    @State var itemBeingEdited = OptionalModel<DeviceLinkModel>(value: nil)
    var onDismiss: (DeviceLinkModel?) -> Void
    @State var selectedDeviceId: UUID? = nil
    @State var page: String? = "1"
    
    init(zoneId: UUID, initialValue: DeviceLinkModel?, onDismiss: @escaping (DeviceLinkModel?) -> Void) {
        self.zoneId = zoneId
        self.onDismiss = onDismiss

        // other forms of init break swifui, and no updates happen...
        self._itemBeingEdited = State(wrappedValue: OptionalModel(value: initialValue))
    }
    
    var body: some View {
        let page = itemBeingEdited.value == nil ? "1" : "2"

        VStack(alignment: .leading) {
            let data = domainModel.links
            VStack(alignment: .leading) {
                if page == "1" {
                    GroupBox("Select a device to link") {
                        BluetoothDevicesListView(selectedId: bindOpt($selectedDeviceId, UUID()), showOnlyNamedDevices: Binding.constant(true))
                            .onChange(of: selectedDeviceId) {
                                guard let selectedDevice = runtimeModel.bluetoothStates.first(where: {$0.id == selectedDeviceId})
                                else { return }
                                itemBeingEdited.value = DeviceLinkModel(
                                    id: UUID(),
                                    zoneId: zoneId,
                                    deviceId: selectedDevice.id,
                                    referencePower: selectedDevice.lastSeenRSSI,
                                    maxDistance: 1.0,
                                    idleTimeout: 60,
                                    requireConnection: false)
                                self.page = "2"
                            }
                    }
                    .frame(minHeight: 300)
                } else if page == "2" {
                    GroupBox("Configure") {
                        DeviceLinkSettingsView(deviceLinkModel: $itemBeingEdited)
                            .frame(minHeight: 300)
                    }
                } else {
                    EmptyView()
                }
            }
            HStack {
                Spacer()
                Button("Cancel"){
                    onDismiss(nil)
                }
                if page == "2" {
                    Button("OK") {
                        onDismiss(itemBeingEdited.value)
                    }
                }
            }
        }
    }
}


struct LinksSettingsView: View {
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel

    @State var zoneIdFilter: UUID? = nil
    @State var modalIsPresented = false
    @State var listSelection: UUID = UUID()
    @State var itemBeingEdited = OptionalModel<DeviceLinkModel>(value: nil)
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
                    return (id: model.id, model: model, state: runtimeModel.linkStates.first{$0.id == model.id }, zone: zone, device: device)
                }
            let maxZoneNameWidth = data.flatMap{$0.zone?.name}.map{estimateTextSize(text: $0).width}.max() ?? 0

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
                        let _ = assert(newItemType == "Bluetooth")
                        EditBluetoothDeviceLinkModal(zoneId: zoneIdFilter, initialValue: itemBeingEdited.value, onDismiss: { link in
                            if let link = link {
                                domainModel.links.updateOrAppend({link}, where: {$0.id == link.id})
                            }
                            modalIsPresented = false
                        })
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

