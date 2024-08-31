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
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor

    let emptyUUID = UUID()
    @State var selectedId: UUID?
    @State var selectedMonitor: BluetoothMonitor.Monitored?
    
    var body: some View {
        HStack {
            AvailableBluetoothDevicesSettingsView(selectedId: bindOpt($selectedId, UUID()))
            if let monitorData = selectedMonitor?.data {
                BluetoothDeviceMonitorView(
                    monitorData: Binding.constant(monitorData)
                )
                .frame(minHeight: 200)
            } else {
                Text("Select a device")
                    .frame(idealWidth: .infinity, maxWidth: .infinity, idealHeight: .infinity, maxHeight: .infinity)
                    .border(Color.primary, width: 1)
            }
        }
        .onChange(of: selectedId ?? emptyUUID) { (old, new) in
            if old != emptyUUID {
                selectedMonitor = nil
            }
            if new != emptyUUID {
                selectedMonitor = bluetoothMonitor.startMonitoring(new)
            }
        }
    }
}

struct BluetoothDeviceView: View {
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
                BluetoothDeviceView(
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
struct AvailableBluetoothDevicesSettingsView: View {

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

struct BluetoothDeviceMonitorView: View {
    enum ChartType: CaseIterable {
        case rssiRaw
        case rssiSmoothed
        case distance
    }

    @Binding var monitorData: BluetoothMonitorData
    @State var availableChartTypes = [ChartType]()
    @State var linkedDeviceChartType: ChartType = .distance
    
    @State var chartTypeAdjustedSamples: [Tuple2<Date, Double>] = []
    @State var chartTypeAdjustedYMin: Double = 0
    @State var chartTypeAdjustedYMax: Double = 0
    @State var chartTypeAdjustedYLastUpdated = Date()

    var body: some View {        
        VStack(alignment: .leading) {
            Picker(selection: $linkedDeviceChartType, label: EmptyView()) {
                ForEach(availableChartTypes, id: \.self) { type in
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
            LineChart(
                samples: $chartTypeAdjustedSamples,
                xRange: 60,
                yAxisMin: $chartTypeAdjustedYMin,
                yAxisMax: $chartTypeAdjustedYMax)
        }
        .onChange(of: monitorData.rssiRawSamples, initial: true) {
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
        .onAppear {
            if monitorData.distanceSmoothedSamples != nil {
                availableChartTypes = ChartType.allCases
                linkedDeviceChartType = .distance
            } else {
                availableChartTypes = ChartType.allCases.filter{$0 != .distance}
                linkedDeviceChartType = .rssiSmoothed
            }
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
            let samples = monitorData.rssiRawSamples
            smoothInterpolateBounds(samples)
            chartTypeAdjustedSamples = samples
        case .rssiSmoothed:
            let samples = monitorData.rssiSmoothedSamples
            smoothInterpolateBounds(samples)
            chartTypeAdjustedSamples = samples
        case .distance:
            if let samples = monitorData.distanceSmoothedSamples {
                smoothInterpolateBounds(samples)
                chartTypeAdjustedYMin = max(0, chartTypeAdjustedYMin)
                chartTypeAdjustedSamples = samples
            }
        }
    }
}

struct BluetoothLinkSettingsView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor

    // TODO: i think this is optional because its easier to pass the binding?
    // technically this should never be empty
    @Binding var bluetoothLinkModel: OptionalModel<BluetoothLinkModel>
    // We use a dedicated monitor in this view instead of the link's or another existing monitor
    // because we want the view to react live without impact to changes in the view without having to save
    @State var monitor: BluetoothMonitor.Monitored?

    var body: some View {
        let bluetoothLinkModel = bluetoothLinkModel.value
        let linkedDevice = runtimeModel.bluetoothStates.first{$0.id == bluetoothLinkModel?.deviceId}
        let linkState = runtimeModel.linkStates.first{$0.id == bluetoothLinkModel?.id}.map{$0 as! BluetoothLinkState}
        let linkedZone: Binding<UUID?> = bindOpt(self.$bluetoothLinkModel,
                                                 {$0?.zoneId},
                                                 {$0.value?.zoneId = $1!})
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        ZoneSelectionView(
                            selectionCanStartNil: linkedZone,
                            nilMenuText: "Choose a Zone"
                        )
                        BluetoothDeviceView(
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
                        value: bindOpt($bluetoothLinkModel,
                                       {$0?.referencePower ?? 0.0},
                                       {$0.value!.referencePower=$1}),
                        in: -100...0,
                        format: {"\(Int($0))"})
                    LabeledDoubleSlider(
                        label: "Environmental noise",
                        description: "TODO",
                        value: bindOpt($bluetoothLinkModel,
                                       {$0?.environmentalNoise ?? 0.0},
                                       {$0.value!.environmentalNoise=$1}),
                        in: 0...100,
                        format: {"\(Int($0))"})
                    LabeledDoubleSlider(
                        label: "Max distance",
                        description: "The distance in meters at which the device is considered absent, resulting in a screen lock. It is calculated from the current signal strength and the reference power, and is not very stable or reliable. It is recommended to consider anything less than 5m as close, and anything more as far.",
                        value: bindOpt($bluetoothLinkModel,
                                       {$0?.maxDistance ?? 0.0},
                                       {$0.value!.maxDistance=$1}),
                        in: 0.0...9.0, step: 0.25, format: {"\(String(format: "%.2f", $0))"})
                    LabeledDoubleSlider(
                        label: "Idle timeout",
                        description: "Device is considered absent if not found for too long, resulting in a screen lock. Unless you configure an active connection, both the host and target device will scan / broadcast at intervals that may vary e.g. due to low power settings. It is recommended to set at least 10-30 seconds.",
                        value: bindOpt($bluetoothLinkModel,
                                       {$0?.idleTimeout ?? 0.0},
                                       {$0.value!.idleTimeout=$1}),
                        in: 0...10*60, step: 10, format: {formatMinSec(msec: $0)})
                    HStack {
                        LabeledView(
                            label: "Require connection",
                            horizontal: true,
                            description: "When active, the app will attempt to maintain a bluetooth connection to the device, reconnecting as necessary. If the connection fails, the screen will lock.") {
                                Toggle("", isOn: bindOpt($bluetoothLinkModel,
                                                         {$0?.requireConnection ?? false},
                                                         {$0.value!.requireConnection=$1}))
                            }
                        Spacer()
                        Image(systemName: (linkedDevice?.connectionState != .disconnected) ? "cable.connector" : "cable.connector.slash")
                            .colorMultiply(bluetoothLinkModel?.requireConnection == true ? .white : .gray)
                    }
                }
                
                if let monitor = monitor {
                    BluetoothDeviceMonitorView(
                        monitorData: Binding.constant(monitor.data)
                    )
                }
            }
            .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)            
        }
        .onAppear() {
            monitor = bluetoothMonitor.startMonitoring(bluetoothLinkModel!.deviceId)
        }
        .onChange(of: bluetoothLinkModel?.environmentalNoise ?? 0) { (old, new) in
            monitor?.data.smoothingFunc?.processNoise = new
        }
    }
}

struct EditBluetoothDeviceLinkModal: View {
    
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: RuntimeModel

    let zoneId: UUID
    @State var itemBeingEdited = OptionalModel<BluetoothLinkModel>(value: nil)
    var onDismiss: (BluetoothLinkModel?) -> Void
    @State var selectedDeviceId: UUID? = nil
    @State var page: String? = "1"
    
    init(zoneId: UUID, initialValue: BluetoothLinkModel?, onDismiss: @escaping (BluetoothLinkModel?) -> Void) {
        self.zoneId = zoneId
        self.onDismiss = onDismiss

        // other forms of init break swifui, and no updates happen...
        self._itemBeingEdited = State(wrappedValue: OptionalModel(value: initialValue))
    }
    
    var body: some View {
        let page = itemBeingEdited.value == nil ? "1" : "2"

        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if page == "1" {
                    GroupBox("Select a device to link") {
                        BluetoothDevicesListView(selectedId: bindOpt($selectedDeviceId, UUID()), showOnlyNamedDevices: Binding.constant(true))
                            .onChange(of: selectedDeviceId) {
                                guard let selectedDevice = runtimeModel.bluetoothStates.first(where: {$0.id == selectedDeviceId})
                                else { return }
                                itemBeingEdited.value = BluetoothLinkModel(
                                    id: UUID(),
                                    zoneId: zoneId,
                                    deviceId: selectedDevice.id,
                                    referencePower: selectedDevice.lastSeenRSSI,
                                    environmentalNoise: 0,
                                    maxDistance: 1.0,
                                    idleTimeout: 60,
                                    requireConnection: false)
                                self.page = "2"
                            }
                    }
                    .frame(minHeight: 300)
                } else if page == "2" {
                    GroupBox("Configure") {
                        BluetoothLinkSettingsView(bluetoothLinkModel: $itemBeingEdited)
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
