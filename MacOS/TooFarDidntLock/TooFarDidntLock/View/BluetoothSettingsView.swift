import SwiftUI
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
            
            AvailableDevicesSettingsView()
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

struct AvailableDevicesSettingsView: View {

    @EnvironmentObject var runtimeModel: RuntimeModel

    @State var availableDevicesHover: UUID?
    @AppStorage("uipref.bluetooth.showOnlyNamedDevices") var showOnlyNamedDevices: Bool = true
    
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
                let availableDevices = runtimeModel.bluetoothStates
                let items = showOnlyNamedDevices ? availableDevices.filter{$0.name?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 0} : availableDevices
                List(Binding.constant(items), id: \.id) { device in
                    VStack(alignment: .leading) {
                        DeviceView(
                            uuid: Binding.constant(device.wrappedValue.id.uuidString),
                            name: Binding.constant(device.wrappedValue.name),
                            rssi: Binding.constant(device.wrappedValue.lastSeenRSSI),
                            lastSeenAt: Binding.constant(nil))
                    }
                    .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrag({ NSItemProvider(object: device.wrappedValue.id.uuidString as NSString) })
                    .background(availableDevicesHover == device.wrappedValue.id ? Color.gray.opacity(0.3) : Color.clear)
                    .onHover { hovering in
                        availableDevicesHover = hovering ? device.wrappedValue.id : nil
                    }
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
        VStack(alignment: .leading) {
            Text("Drag and drop a device from the list here to link it.")
            GroupBox(label: Label("Linked device", systemImage: "")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            HStack {
                                let selectedZone = domainModel.zones.first{$0.id == deviceLinkModel?.zoneId}
                                Image(systemName: Icons.zone)
                                    .help("Linked zone")
                                Menu(selectedZone.map{$0.name} ?? "Choose a Zone", systemImage: selectedZone.map{Icons.Zones.of($0)} ?? "") {
                                    ForEach($domainModel.zones, id: \.id) { zone in
                                        Button {
                                            self.deviceLinkModel.value!.zoneId = zone.wrappedValue.id
                                        } label: {
                                            ZoneMenuItemView(zone: zone)
                                        }
                                    }
                                }
                            }
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
                                domainModel.links = [deviceLink]
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
