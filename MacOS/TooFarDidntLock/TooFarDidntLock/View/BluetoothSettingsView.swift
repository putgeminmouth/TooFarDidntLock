import SwiftUI
import Combine
import UniformTypeIdentifiers
import OSLog
import Charts

struct BluetoothSettingsView: View {
    let logger = Log.Logger("BluetoothSettingsView")

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor

    let emptyUUID = UUID()
    @State var selectedId: UUID?
    @State var selectedMonitor: BluetoothMonitor.Monitored?
    
    var body: some View {
        HStack {
            AvailableBluetoothDevicesSettingsView(selectedId: bindOpt($selectedId, UUID()))
            if let monitorData = selectedMonitor?.data {
                BluetoothDeviceMonitorView(
                    monitorData: monitorData,
                    availableChartTypes: Set([.rssiRaw, .rssiSmoothed]),
                    selectedChartTypes: Set([.rssiRaw, .rssiSmoothed])
                )
                // we want to force the view to recreate when changing data
                .id(ObjectIdentifier(monitorData))
                .frame(minHeight: 200)
            } else {
                Text("Select a device")
                    .frame(idealWidth: .infinity, maxWidth: .infinity, idealHeight: .infinity, maxHeight: .infinity)
                    .border(Color.primary, width: 1)
            }
        }
        .onChange(of: selectedId ?? emptyUUID) { (old, new: UUID) in
            if old != emptyUUID {
                selectedMonitor?.cancellable.cancel()
                selectedMonitor = nil
            }
            if new != emptyUUID {
                selectedMonitor = bluetoothMonitor.startMonitoring(new)

                // just for the UX, backfill with existing data
                if let data = bluetoothMonitor.dataFor(deviceId: new).first,
                   let firstSample = data.rssiRawSamples.first?.value {
                    selectedMonitor!.data.rssiRawSamples = data.rssiRawSamples
                    selectedMonitor!.data.smoothingFunc = BluetoothMonitor.initSmoothingFunc(initialRSSI: firstSample)
                    BluetoothMonitor.recalculate(monitorData: selectedMonitor!.data)
                }
            }
        }
    }
}

struct BluetoothDeviceView: View {
    @Binding var uuid: String?
    @Binding var name: String?
    @Binding var transmitPower: Double?
    @Binding var rssi: Double?
    @Binding var lastSeenAt: Date?

    var body: some View {
        VStack(alignment: .leading) {
            Text("UUID: \(uuid ?? "00000000-0000-0000-0000-000000000000")")
            Text("Name: \(name ?? "")")
            Text("Power: \(transmitPower ?? 0)")
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
                    transmitPower: Binding.constant(device.transmitPower),
                    rssi: Binding.constant(device.lastSeenRSSI),
                    lastSeenAt: Binding.constant(nil))
                // make row occupy full width
                Spacer()
                EmptyView()
            }
            if let callback = callback {
                callback(AnyView(row), device)
                    .allowsHitTesting(false) // don't let Text() and stuff prevent list selection
            } else {
                row
                    .allowsHitTesting(false) // don't let Text() and stuff prevent list selection
            }
        }
    }
    
}
struct AvailableBluetoothDevicesSettingsView: View {
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

    @State var monitorData: BluetoothMonitorData
    @State var availableChartTypes: Set<ChartType>
    @State var selectedChartTypes: Set<ChartType>
    
    @State private var chartSamples: LineChart.Samples = [:]
    @State private var chartYMin: Double = 0
    @State private var chartYMax: Double = 0
    @State private var chartYLastUpdated = Date()

    var body: some View {
        VStack(alignment: .leading) {
            Menu("Select data series") {
                Toggle("All", isOn: bindSetToggle($selectedChartTypes, availableChartTypes))
                    .toggleStyle(.button)
                Divider()
                Toggle("Raw signal power (decibels)", isOn: bindSetToggle($selectedChartTypes, [.rssiRaw]))
                    .toggleStyle(.checkbox)
                Toggle("Smoothed signal power (decibels)", isOn: bindSetToggle($selectedChartTypes, [.rssiSmoothed]))
                    .toggleStyle(.checkbox)
                Toggle("Calculated Distance (meters)", isOn: bindSetToggle($selectedChartTypes, [.distance]))
                    .toggleStyle(.checkbox)
            }
            LineChart(
                samples: $chartSamples,
                xRange: 60,
                yAxisMin: $chartYMin,
                yAxisMax: $chartYMax)
        }
        .onReceive(monitorData.objectWillChange) { _ in
            recalculate()
            chartYMin = Double.greatestFiniteMagnitude
            chartYMax = -Double.greatestFiniteMagnitude
            for (key, chartTypeAdjustedSample) in chartSamples {
                let (_, _, ymin, ymax) = calcBounds(chartTypeAdjustedSample)
                chartYMin = Double.minimum(chartYMin, ymin)
                chartYMax = Double.maximum(chartYMax, ymax)
            }
            if chartSamples.isEmpty {
                chartYMin = 0
                chartYMax = 1
            }
            assert(chartYMin <= chartYMax, "\(chartYMin) <= \(chartYMax)")
        }
        .onChange(of: selectedChartTypes) {
            recalculate()
            chartYMin = Double.greatestFiniteMagnitude
            chartYMax = -Double.greatestFiniteMagnitude
            for (key, chartTypeAdjustedSample) in chartSamples {
                let (_, _, ymin, ymax) = calcBounds(chartTypeAdjustedSample)
                chartYMin = Double.minimum(chartYMin, ymin)
                chartYMax = Double.maximum(chartYMax, ymax)
                
            }
            if chartSamples.isEmpty {
                chartYMin = 0
                chartYMax = 1
            }
            assert(chartYMin <= chartYMax, "\(chartYMin) <= \(chartYMax)")
        }
    }
    func calcBounds(_ samples: [DataSample]) -> (sampleMin: Double, sampleMax: Double, ymin: Double, ymax: Double) {
        let stddev = samples.map{$0.value}.standardDeviation()
        let sampleMin = samples.min(by: {$0.value < $1.value})?.value ?? 0
        let sampleMax = samples.max(by: {$0.value < $1.value})?.value ?? 0
        let ymin = sampleMin - stddev * 1
        let ymax = sampleMax + stddev * 1
        return (sampleMin: sampleMin, sampleMax: sampleMax, ymin: ymin, ymax: ymax)
    }
    func smoothInterpolateBounds(_ samples: [DataSample]) {
        let (sampleMin, sampleMax, ymin, ymax) = calcBounds(samples)

        let chartTypeAdjustedYShouldUpdate = chartYLastUpdated.distance(to: Date.now) > 5

        if chartTypeAdjustedYShouldUpdate {
            chartYLastUpdated = Date.now
            let a = 0.5
            let b = 1-a

            chartYMin = chartYMin * a + ymin * b
            chartYMax = chartYMax * a + ymax * b
        }
        chartYMin = min(sampleMin, chartYMin)
        chartYMax = max(sampleMax, chartYMax)
    }
    func recalculate() {
        chartSamples = [:]
        
        let samples1 = monitorData.rssiRawSamples
        if selectedChartTypes.contains(.rssiRaw) {
            smoothInterpolateBounds(samples1)
//            var chartTypeAdjustedSamples = LineChart.Samples()
            chartSamples[DataDesc("rssiRaw")] = samples1
        }
        
        if selectedChartTypes.contains(.rssiSmoothed) {
            let samples2 = monitorData.rssiSmoothedSamples
            smoothInterpolateBounds(samples2)
            chartSamples[DataDesc("rssiSmoothed")] = samples2
        }
        
        if selectedChartTypes.contains(.distance),
           let samples3 = monitorData.distanceSmoothedSamples {
            smoothInterpolateBounds(samples3)
            chartYMin = max(0, chartYMin)
            chartSamples[DataDesc("distance")] = samples3
        }
    }
}

struct BluetoothLinkSettingsView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor

    // TODO: i think this is optional because its easier to pass the binding?
    // technically this should never be empty
    @Binding var bluetoothLinkModel: OptionalModel<BluetoothLinkModel>
    // We use a dedicated monitor in this view instead of the link's or another existing monitor
    // because we want the view to react live without impact to changes in the view without having to save
    @State var monitor: BluetoothMonitor.Monitored?
    
    @State var linkedLastSeenRSSI: Double?
    @State var linkedLastSeenAt: Date?
    
    var body: some View {
        let bluetoothLinkModel = bluetoothLinkModel.value
        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == bluetoothLinkModel?.deviceId}
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
                            transmitPower: Binding.constant(linkedDevice?.transmitPower),
                            rssi: $linkedLastSeenRSSI,
                            lastSeenAt: $linkedLastSeenAt)
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
                        monitorData: monitor.data,
                        availableChartTypes: Set(BluetoothDeviceMonitorView.ChartType.allCases),
                        selectedChartTypes: Set([.distance])
                    )
                }
            }
            .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)            
        }
        .onAppear() {
            onAppear()
        }
        // likely unnecessary optimization: we avoid binding the entire view to runtimeModel
        // and only update these props. elsewhere we use the cached model
        .onReceive(runtimeModel.value.bluetoothStateDidChange(id: {bluetoothLinkModel?.deviceId})) { update in
            if update.lastSeenRSSI != linkedLastSeenRSSI {
                linkedLastSeenRSSI = update.lastSeenRSSI
            }
            if update.lastSeenAt != linkedLastSeenAt {
                linkedLastSeenAt = update.lastSeenAt
            }
        }
        .onChange(of: bluetoothLinkModel?.referencePower ?? 0) { (old, new) in
            monitor?.data.referenceRSSIAtOneMeter = new
        }
        .onChange(of: bluetoothLinkModel?.environmentalNoise ?? 0) { (old, new) in
            monitor?.data.smoothingFunc?.processNoise = new
        }
    }
    
    func onAppear() {
        let bluetoothLinkModel = bluetoothLinkModel.value!
        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == bluetoothLinkModel.deviceId}!
        let isNew = domainModel.links.first{$0.id == bluetoothLinkModel.id} == nil
        monitor = bluetoothMonitor.startMonitoring(bluetoothLinkModel.deviceId, referenceRSSIAtOneMeter: bluetoothLinkModel.referencePower)

        // just for the UX, backfill with existing data
        // if new, pick any available monitor for the device, but recalculate with current settings
        // if existing, we can keep all the data since we always start with the current settings
        if isNew {
            if let data = bluetoothMonitor.dataFor(deviceId: linkedDevice.id).first {
                monitor!.data.rssiRawSamples = data.rssiRawSamples
                monitor!.data.smoothingFunc = BluetoothMonitor.initSmoothingFunc(
                    initialRSSI: monitor!.data.rssiRawSamples.first?.value ?? bluetoothLinkModel.referencePower,
                    processNoise: bluetoothLinkModel.environmentalNoise
                )

                BluetoothMonitor.recalculate(monitorData: monitor!.data)
            }
        } else {
            let linkState = runtimeModel.value.linkStates.first{$0.id == bluetoothLinkModel.id} as! BluetoothLinkState
            monitor!.data.rssiRawSamples = linkState.monitorData.data.rssiRawSamples
            monitor!.data.rssiSmoothedSamples = linkState.monitorData.data.rssiRawSamples
            monitor!.data.distanceSmoothedSamples = linkState.monitorData.data.distanceSmoothedSamples
            monitor!.data.smoothingFunc = linkState.monitorData.data.smoothingFunc
        }
    }
}

struct MaMa: View {
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
    @Binding var bluetoothLinkModel: OptionalModel<BluetoothLinkModel>
    @State var stateUpdates = ProxyPublisher<MonitoredPeripheral>(nil)
    
    var body: some View {
        let bluetoothLinkModel = bluetoothLinkModel.value

        EmptyView()
            .onReceive(runtimeModel.value.bluetoothStateDidChange(id: {bluetoothLinkModel?.deviceId})) { update in
            }
    }
}

struct EditBluetoothDeviceLinkModal: View {
    
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>

    let zoneId: UUID
    @State var itemBeingEdited = OptionalModel<BluetoothLinkModel>(value: nil)
    var onDismiss: (BluetoothLinkModel?) -> Void
    @State var selectedDeviceId: UUID? = nil
    @State var page: String? = "1"
    
    init(zoneId: UUID, initialValue: BluetoothLinkModel?, onDismiss: @escaping (BluetoothLinkModel?) -> Void) {
        self.zoneId = zoneId
        self.onDismiss = onDismiss

        // using State() like this is not recommended but other forms of init break swifui, and no updates happen...
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
                                guard let selectedDevice = runtimeModel.value.bluetoothStates.first(where: {$0.id == selectedDeviceId})
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
