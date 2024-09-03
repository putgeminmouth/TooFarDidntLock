import SwiftUI
import Combine
import UniformTypeIdentifiers
import OSLog
import Charts

struct WifiSettingsView: View {
    let logger = Log.Logger("WifiSettingsView")

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var wifiMonitor: WifiMonitor

    let emptyID = UUID().uuidString
    @State var selectedId: String?
    @State var selectedMonitor: WifiMonitor.Monitored?
    
    var body: some View {
        HStack {
            AvailableWifiDevicesSettingsView(selectedId: bindOpt($selectedId, emptyID))
            if let monitorData = selectedMonitor?.data {
                WifiDeviceMonitorView(
                    monitorData: monitorData
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
        .onChange(of: selectedId ?? emptyID) { (old, new: String) in
            if old != emptyID {
                selectedMonitor?.cancellable.cancel()
                selectedMonitor = nil
            }
            if new != emptyID {
                selectedMonitor = wifiMonitor.startMonitoring(new)

                // just for the UX, backfill with existing data
                if let data = wifiMonitor.dataFor(deviceId: new).first,
                   let firstSample = data.rssiRawSamples.first?.value {
                    selectedMonitor!.data.rssiRawSamples = data.rssiRawSamples
                    selectedMonitor!.data.smoothingFunc = WifiMonitor.initSmoothingFunc(
                        initialRSSI: firstSample,
                        processVariance: 0.1,
                        measureVariance: 23.0
                    )
                    WifiMonitor.recalculate(monitorData: selectedMonitor!.data)
                }
            }
        }
    }
}

struct WifiDeviceView: View {
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

struct WifiDevicesListView: View {

    @EnvironmentObject var runtimeModel: RuntimeModel

    @Binding var selectedId: String
    @Binding var showOnlyNamedDevices: Bool
    var callback: ((AnyView, MonitoredWifiDevice) -> AnyView)?
    
    init(selectedId: Binding<String>, showOnlyNamedDevices: Binding<Bool>, items: ((AnyView, MonitoredWifiDevice) -> AnyView)? = nil) {
        self._selectedId = selectedId
        self._showOnlyNamedDevices = showOnlyNamedDevices
        self.callback = items
    }

    var body: some View {
        let availableDevices = runtimeModel.wifiStates
        let items = showOnlyNamedDevices ? availableDevices.filter{$0.ssid?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 0} : availableDevices
        ListView(Binding.constant(items), id: \.wrappedValue.bssid, selection: $selectedId) { device in
            let device = device.wrappedValue
            let row = HStack {
                WifiDeviceView(
                    uuid: Binding.constant(device.bssid),
                    name: Binding.constant(device.ssid),
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
struct AvailableWifiDevicesSettingsView: View {
    @AppStorage("uipref.wifi.showOnlyNamedDevices") var showOnlyNamedDevices: Bool = true
    
    @Binding var selectedId: String
    
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
                WifiDevicesListView(selectedId: $selectedId, showOnlyNamedDevices: $showOnlyNamedDevices) { row, device in
                    AnyView(
                        row
                            .onDrag({ NSItemProvider(object: device.bssid as NSString) })
                    )
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct WifiDeviceMonitorView: View {
    enum ChartType: CaseIterable {
        case rssiRaw
        case rssiSmoothed
        case distance
    }

    @State var monitorData: WifiMonitorData
    @State var availableChartTypes = [ChartType]()
    @State var linkedDeviceChartType: ChartType = .distance
    
    @State var chartTypeAdjustedSamples: LineChart.Samples = [:]
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
        .onReceive(monitorData.objectWillChange) { _ in
            recalculate()
            for (key, chartTypeAdjustedSample) in chartTypeAdjustedSamples {
                if chartTypeAdjustedSample.count < 3 {
                    let (_, _, ymin, ymax) = calcBounds(chartTypeAdjustedSample)
                    chartTypeAdjustedYMin = Double.minimum(chartTypeAdjustedYMin, ymin)
                    chartTypeAdjustedYMax = Double.maximum(chartTypeAdjustedYMax, ymax)
                }
            }
        }
        .onChange(of: linkedDeviceChartType) {
            recalculate()
            for (key, chartTypeAdjustedSample) in chartTypeAdjustedSamples {
                let (_, _, ymin, ymax) = calcBounds(chartTypeAdjustedSample)
                chartTypeAdjustedYMin = Double.minimum(chartTypeAdjustedYMin, ymin)
                chartTypeAdjustedYMax = Double.maximum(chartTypeAdjustedYMax, ymax)
            }
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
        if monitorData.distanceSmoothedSamples != nil {
            availableChartTypes = ChartType.allCases
        } else {
            availableChartTypes = ChartType.allCases.filter{$0 != .distance}
        }
        for (key, _) in chartTypeAdjustedSamples {
            switch linkedDeviceChartType {
            case .rssiRaw:
                let samples = monitorData.rssiRawSamples
                smoothInterpolateBounds(samples)
                chartTypeAdjustedSamples = [DataDesc("rssiRaw"): samples]
            case .rssiSmoothed:
                let samples = monitorData.rssiSmoothedSamples
                smoothInterpolateBounds(samples)
                chartTypeAdjustedSamples = [DataDesc("rssiSmoothed"): samples]
            case .distance:
                if let samples = monitorData.distanceSmoothedSamples {
                    smoothInterpolateBounds(samples)
                    chartTypeAdjustedYMin = max(0, chartTypeAdjustedYMin)
                    chartTypeAdjustedSamples = [DataDesc("distance"): samples]
                }
            }
        }
    }
}

//struct WifiLinkSettingsView: View {
//    @Environment(\.scenePhase) var scenePhase
//    @EnvironmentObject var domainModel: DomainModel
//    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
//    @EnvironmentObject var wifiMonitor: WifiMonitor
//
//    // TODO: i think this is optional because its easier to pass the binding?
//    // technically this should never be empty
//    @Binding var wifiLinkModel: OptionalModel<WifiLinkModel>
//    // We use a dedicated monitor in this view instead of the link's or another existing monitor
//    // because we want the view to react live without impact to changes in the view without having to save
//    @State var monitor: WifiMonitor.Monitored?
//    
//    @State var linkedLastSeenRSSI: Double?
//    @State var linkedLastSeenAt: Date?
//
//    var body: some View {
//        let wifiLinkModel = wifiLinkModel.value
//        let linkedDevice = domainModel.wellKnownWifiDevices.first{$0.bssid == wifiLinkModel?.deviceId}
//        let linkedZone: Binding<UUID?> = bindOpt(self.$wifiLinkModel,
//                                                 {$0?.zoneId},
//                                                 {$0.value?.zoneId = $1!})
//        VStack(alignment: .leading) {
//            HStack(alignment: .top) {
//                VStack(alignment: .leading) {
//                    VStack(alignment: .leading) {
//                        ZoneSelectionView(
//                            selectionCanStartNil: linkedZone,
//                            nilMenuText: "Choose a Zone"
//                        )
//                        WifiDeviceView(
//                            uuid: Binding.constant(linkedDevice?.id.uuidString),
//                            name: Binding.constant(linkedDevice?.name),
//                            rssi: $linkedLastSeenRSSI,
//                            lastSeenAt: $linkedLastSeenAt)
//                        .padding(4)
//                        .border(Color.gray, width: 1)
//                        .cornerRadius(2)
//                        // likely unnecessary optimization: we avoid binding the entire view to runtimeModel
//                        // and only update these props. elsewhere we use the cached model
//                        .onReceive(runtimeModel.value.objectWillChange) { _ in
//                            if let state = runtimeModel.value.wifiStates.first{$0.id == wifiLinkModel?.deviceId} {
//                                linkedLastSeenRSSI = state.lastSeenRSSI
//                                linkedLastSeenAt = state.lastSeenAt
//                            }
//                        }
//                    }
//                    LabeledDoubleSlider(
//                        label: "Reference Power",
//                        description: "Set to the signal power at 1 meter.",
//                        value: bindOpt($wifiLinkModel,
//                                       {$0?.referencePower ?? 0.0},
//                                       {$0.value!.referencePower=$1}),
//                        in: -100...0,
//                        format: {"\(Int($0))"})
//                    LabeledDoubleSlider(
//                        label: "Environmental noise",
//                        description: "TODO",
//                        value: bindOpt($wifiLinkModel,
//                                       {$0?.processVariance ?? 0.0},
//                                       {$0.value!.processVariance=$1}),
//                        in: 0...100,
//                        format: {"\(Int($0))"})
//                    LabeledDoubleSlider(
//                        label: "Max distance",
//                        description: "The distance in meters at which the device is considered absent, resulting in a screen lock. It is calculated from the current signal strength and the reference power, and is not very stable or reliable. It is recommended to consider anything less than 5m as close, and anything more as far.",
//                        value: bindOpt($wifiLinkModel,
//                                       {$0?.maxDistance ?? 0.0},
//                                       {$0.value!.maxDistance=$1}),
//                        in: 0.0...9.0, step: 0.25, format: {"\(String(format: "%.2f", $0))"})
//                    LabeledDoubleSlider(
//                        label: "Idle timeout",
//                        description: "Device is considered absent if not found for too long, resulting in a screen lock. Unless you configure an active connection, both the host and target device will scan / broadcast at intervals that may vary e.g. due to low power settings. It is recommended to set at least 10-30 seconds.",
//                        value: bindOpt($wifiLinkModel,
//                                       {$0?.idleTimeout ?? 0.0},
//                                       {$0.value!.idleTimeout=$1}),
//                        in: 0...10*60, step: 10, format: {formatMinSec(msec: $0)})
//                    HStack {
//                        LabeledView(
//                            label: "Require connection",
//                            horizontal: true,
//                            description: "When active, the app will attempt to maintain a wifi connection to the device, reconnecting as necessary. If the connection fails, the screen will lock.") {
//                                Toggle("", isOn: bindOpt($wifiLinkModel,
//                                                         {$0?.requireConnection ?? false},
//                                                         {$0.value!.requireConnection=$1}))
//                            }
//                        Spacer()
//                        Image(systemName: (linkedDevice?.connectionState != .disconnected) ? "cable.connector" : "cable.connector.slash")
//                            .colorMultiply(wifiLinkModel?.requireConnection == true ? .white : .gray)
//                    }
//                }
//                
//                if let monitor = monitor {
//                    WifiDeviceMonitorView(
//                        monitorData: monitor.data
//                    )
//                }
//            }
//            .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
//        }
//        .onAppear() {
//            onAppear()
//        }
//        .onChange(of: wifiLinkModel?.referencePower ?? 0) { (old, new) in
//            monitor?.data.referenceRSSIAtOneMeter = new
//        }
//        .onChange(of: wifiLinkModel?.processVariance ?? 0) { (old, new) in
//            monitor?.data.smoothingFunc?.processVariance = new
//        }
//    }
//    
//    func onAppear() {
//        let wifiLinkModel = wifiLinkModel.value!
//        let linkedDevice = runtimeModel.value.wifiStates.first{$0.bssid == wifiLinkModel.deviceId}!
//        let isNew = domainModel.links.first{$0.id == wifiLinkModel.id} == nil
//        monitor = wifiMonitor.startMonitoring(wifiLinkModel.deviceId, referenceRSSIAtOneMeter: wifiLinkModel.referencePower)
//
//
//        // just for the UX, backfill with existing data
//        // if new, pick any available monitor for the device, but recalculate with current settings
//        // if existing, we can keep all the data since we always start with the current settings
//        if isNew {
//            if let data = wifiMonitor.dataFor(deviceId: linkedDevice.bssid).first {
//                monitor!.data.rssiRawSamples = data.rssiRawSamples
//                monitor!.data.smoothingFunc = WifiMonitor.initSmoothingFunc(
//                    initialRSSI: monitor!.data.rssiRawSamples.first?.b ?? wifiLinkModel.referencePower,
//                    processVariance: wifiLinkModel.processVariance
//                )
//
//                WifiMonitor.recalculate(monitorData: monitor!.data)
//            }
//        } else {
//            let linkState = runtimeModel.value.linkStates.first{$0.id == wifiLinkModel.id} as! WifiLinkState
//            monitor!.data.rssiRawSamples = linkState.monitorData.data.rssiRawSamples
//            monitor!.data.rssiSmoothedSamples = linkState.monitorData.data.rssiRawSamples
//            monitor!.data.distanceSmoothedSamples = linkState.monitorData.data.distanceSmoothedSamples
//            monitor!.data.smoothingFunc = linkState.monitorData.data.smoothingFunc
//        }
//    }
//}

//struct EditWifiDeviceLinkModal: View {
//    
//    @EnvironmentObject var domainModel: DomainModel
//    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
//
//    let zoneId: UUID
//    @State var itemBeingEdited = OptionalModel<WifiLinkModel>(value: nil)
//    var onDismiss: (WifiLinkModel?) -> Void
//    @State var selectedDeviceId: UUID? = nil
//    @State var page: String? = "1"
//    
//    init(zoneId: UUID, initialValue: WifiLinkModel?, onDismiss: @escaping (WifiLinkModel?) -> Void) {
//        self.zoneId = zoneId
//        self.onDismiss = onDismiss
//
//        // using State() like this is not recommended but other forms of init break swifui, and no updates happen...
//        self._itemBeingEdited = State(wrappedValue: OptionalModel(value: initialValue))
//    }
//    
//    var body: some View {
//        let page = itemBeingEdited.value == nil ? "1" : "2"
//
//        VStack(alignment: .leading) {
//            VStack(alignment: .leading) {
//                if page == "1" {
//                    GroupBox("Select a device to link") {
//                        WifiDevicesListView(selectedId: bindOpt($selectedDeviceId, UUID()), showOnlyNamedDevices: Binding.constant(true))
//                            .onChange(of: selectedDeviceId) {
//                                guard let selectedDevice = runtimeModel.value.wifiStates.first(where: {$0.bssid == selectedDeviceId})
//                                else { return }
//                                itemBeingEdited.value = WifiLinkModel(
//                                    id: UUID(),
//                                    zoneId: zoneId,
//                                    deviceId: selectedDevice.bssid,
//                                    referencePower: selectedDevice.lastSeenRSSI,
//                                    processVariance: 0,
//                                    maxDistance: 1.0,
//                                    idleTimeout: 60,
//                                    requireConnection: false)
//                                self.page = "2"
//                            }
//                    }
//                    .frame(minHeight: 300)
//                } else if page == "2" {
//                    GroupBox("Configure") {
//                        WifiLinkSettingsView(wifiLinkModel: $itemBeingEdited)
//                            .frame(minHeight: 300)
//                    }
//                } else {
//                    EmptyView()
//                }
//            }
//            HStack {
//                Spacer()
//                Button("Cancel"){
//                    onDismiss(nil)
//                }
//                if page == "2" {
//                    Button("OK") {
//                        onDismiss(itemBeingEdited.value)
//                    }
//                }
//            }
//        }
//    }
//}
