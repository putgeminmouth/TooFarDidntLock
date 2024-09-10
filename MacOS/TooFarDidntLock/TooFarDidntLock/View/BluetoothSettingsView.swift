import SwiftUI
import Combine
import UniformTypeIdentifiers
import OSLog
import Charts

struct BluetoothSettingsView: View {
    let logger = Log.Logger("BluetoothSettingsView")

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor

    let emptyID = UUID()
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
        .onChange(of: selectedId ?? emptyID) { (old, new: UUID) in
            if old != emptyID {
                selectedMonitor?.cancellable.cancel()
                selectedMonitor = nil
            }
            guard let state = runtimeModel.value.bluetoothStates.first(where: {$0.id == new})
            else {
                assert(false)
                return
            }
            if new != emptyID {
                selectedMonitor = bluetoothMonitor.startMonitoring(
                    new,
                    smoothing: (referenceRSSIAtOneMeter: state.lastSeenRSSI, processNoise: 0.1, measureNoise: 23.0)
                )
            }
        }
    }
}

struct BluetoothDeviceView: View {
    @EnvironmentObject var advancedMode: EnvVar<Bool>
    
    @Binding var id: String?
    @Binding var name: String?
    @Binding var transmitPower: Double?
    @Binding var rssi: Double?
    @Binding var lastSeenAt: Date?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Name: \(name ?? "")")
                .font(.title)
            if advancedMode.value {
                Text("ID: \(id ?? "00000000-0000-0000-0000-000000000000")")
                    .font(.footnote)
                Text("Power: \(transmitPower ?? 0)")
                Text("RSSI: \(rssi ?? 0)")
                if let lastSeenAt = lastSeenAt { Text("Latency: \(lastSeenAt.distance(to: Date.now))s") }
            }
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
                    id: Binding.constant(device.id.uuidString),
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
                if availableChartTypes.contains(.rssiRaw) {
                    Toggle("Raw signal power (decibels)", isOn: bindSetToggle($selectedChartTypes, [.rssiRaw]))
                        .toggleStyle(.checkbox)
                }
                if availableChartTypes.contains(.rssiSmoothed) {
                    Toggle("Smoothed signal power (decibels)", isOn: bindSetToggle($selectedChartTypes, [.rssiSmoothed]))
                        .toggleStyle(.checkbox)
                }
                if availableChartTypes.contains(.distance) {
                    Toggle("Calculated Distance (meters)", isOn: bindSetToggle($selectedChartTypes, [.distance]))
                        .toggleStyle(.checkbox)
                }
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

enum Distance: CaseIterable {
    case near
    case far
}

extension Distance {
    static func fromMeters(_ m: Double) -> Distance {
        if m < 8 {
            return .near
        } else {
            return .far
        }
    }
    func toMeters() -> Double {
        switch self {
        case .near: return 3
        case .far: return 6
        }
    }
}

struct BluetoothLinkSettingsView: View {

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor
    @EnvironmentObject var advancedMode: EnvVar<Bool>

    // TODO: i think this is optional because its easier to pass the binding?
    // technically this should never be empty
    @Binding var bluetoothLinkModel: OptionalModel<BluetoothLinkModel>
    // We use a dedicated monitor in this view instead of the link's or another existing monitor
    // because we want the view to react live without impact to changes in the view without having to save
    @State var monitor: BluetoothMonitor.Monitored?
    
    @State var linkedLastSeenRSSI: Double?
    @State var linkedLastSeenAt: Date?
    
    var calibrationTimer = Timed(interval: 2)
    @State var calibrationCancelable: AnyCancellable? = nil
    
    var body: some View {
        let linkModel = bluetoothLinkModel.value!
        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == linkModel.deviceId}
        let linkedZone: Binding<UUID?> = bindOpt($bluetoothLinkModel,
                                                 {$0?.zoneId},
                                                 {$0.value?.zoneId = $1!})
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                        ZoneSelectionView(
                            selectionCanStartNil: linkedZone,
                            nilMenuText: "Choose a Zone"
                        )
                    HStack(alignment: .top) {
                        BluetoothDeviceView(
                            id: Binding.constant(linkedDevice?.id.uuidString),
                            name: Binding.constant(linkedDevice?.name),
                            transmitPower: Binding.constant(linkedDevice?.transmitPower),
                            rssi: $linkedLastSeenRSSI,
                            lastSeenAt: $linkedLastSeenAt)
                        .padding(4)
                        .border(Color.gray, width: 1)
                        .cornerRadius(2)
                        
                        Button("", systemImage: "scope") {
                            if calibrationTimer.isActive {
                                calibrationTimer.stop()
                            } else {
                                calibrationTimer.start()
                            }
                        }.myButtonStyle()
                    }
                    if advancedMode.value {
                        LabeledDoubleSlider(
                            label: "Reference Power",
                            description: "Set to the signal power at 1 meter.",
                            value: bindOpt($bluetoothLinkModel,
                                           {$0?.referencePower ?? 0.0},
                                           {$0.value!.referencePower=$1}),
                            in: -100...0,
                            format: {"\(Int($0))"})
                        LabeledDoubleSlider(
                            label: "Process variance",
                            description: "TODO",
                            value: bindOpt($bluetoothLinkModel,
                                           {$0?.processVariance ?? BluetoothLinkModel.DefaultProcessVariance},
                                           {$0.value!.processVariance=$1}),
                            in: 0.01...50,
                            format: {"\(String(format: "%.2f", $0))"})
                        LabeledDoubleSlider(
                            label: "Measure variance",
                            description: "TODO",
                            value: bindOpt($bluetoothLinkModel,
                                           {$0?.measureVariance ?? BluetoothLinkModel.DefaultMeasureVariance},
                                           {$0.value!.measureVariance=$1}),
                            in: 0.01...50,
                            format: {"\(String(format: "%.2f", $0))"})
                        LabeledDoubleSlider(
                            label: "Idle timeout",
                            description: "Device is considered absent if not found for too long, resulting in a screen lock. Unless you configure an active connection, both the host and target device will scan / broadcast at intervals that may vary e.g. due to low power settings. It is recommended to set at least 10-30 seconds.",
                            value: bindOpt($bluetoothLinkModel,
                                           {$0?.idleTimeout ?? 0.0},
                                           {$0.value!.idleTimeout=$1}),
                            in: 0...10*60, step: 10, format: {formatMinSec(msec: $0)})
                        LabeledDoubleSlider(
                            label: "Max distance",
                            description: "The distance in meters at which the device is considered absent, resulting in a screen lock. It is calculated from the current signal strength and the reference power, and is not very stable or reliable.",
                            value: bindOpt($bluetoothLinkModel,
                                           {$0?.maxDistance ?? 0.0},
                                           {$0.value!.maxDistance=$1}),
                            in: 0.0...9.0, step: 0.25, format: {"\(String(format: "%.2f", $0))"})
                    } else {
                        Picker("Max distance",
                               selection: Binding<Distance>(get: {Distance.fromMeters(linkModel.maxDistance)},
                                                            set: {bluetoothLinkModel.value?.maxDistance = $0.toMeters()})) {
                            Text("Near \(String(format: "%.2f", Distance.near.toMeters()))m").tag(Distance.near)
                            Text("Far \(String(format: "%.2f", Distance.far.toMeters()))m").tag(Distance.far)
                        }
                    }
                    HStack {
                        LabeledView(
                            label: "Require connection",
                            horizontal: true,
                            description: "This is more reliable but might drain your device's power and interfere with other uses.") {
                                Toggle("", isOn: bindOpt($bluetoothLinkModel,
                                                         {$0?.requireConnection ?? false},
                                                         {$0.value!.requireConnection=$1}))
                            }
                        Spacer()
                        Image(systemName: (linkedDevice?.connectionState != .disconnected) ? "cable.connector" : "cable.connector.slash")
                            .colorMultiply(bluetoothLinkModel.value?.requireConnection == true ? .white : .gray)
                    }
                }
                
                if let monitor = monitor {
                    SignalMonitorView(
                        monitorData: monitor.data,
                        availableChartTypes: Set(SignalMonitorView.ChartType.allCases),
                        selectedChartTypes: Set([.rssiRaw, .rssiSmoothed])
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
        .onReceive(runtimeModel.value.bluetoothStateDidChange(id: {bluetoothLinkModel.value?.deviceId})) { update in
            if update.lastSeenRSSI != linkedLastSeenRSSI {
                linkedLastSeenRSSI = update.lastSeenRSSI
            }
            if update.lastSeenAt != linkedLastSeenAt {
                linkedLastSeenAt = update.lastSeenAt
            }
        }
        .onChange(of: bluetoothLinkModel.value?.referencePower ?? 0) { (old, new) in
            monitor?.data.referenceRSSIAtOneMeter = new
        }
        .onChange(of: bluetoothLinkModel.value?.processVariance ?? 0) { (old, new) in
            monitor?.data.smoothingFunc?.processVariance = new
        }
        .onChange(of: bluetoothLinkModel.value?.measureVariance ?? 0) { (old, new) in
            monitor?.data.smoothingFunc?.measureVariance = new
        }
//        .onReceive(calibrationTimer) { time in
//            calibrate()
//        }
    }
    
    func calibrate() {
        func trunc10s(_ x: Double) -> Double {
            Double(Int(x / 10) * 10)
        }
//            let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == bluetoothLinkModel.deviceId}!
        guard let monitor = monitor
//                  let bluetoothLinkModel = bluetoothLinkModel.value
        else { return }
        let data = monitor.data
//        var rawBuckets = data.rssiRawSamples.reduce([Date: [DataSample]]()) { acc, next in
//            var ret = acc
//            let idx = Date(timeIntervalSince1970: trunc10s(next.date.timeIntervalSince1970))
//            ret[idx] = (ret[idx] ?? []) + [next]
//            return ret
//        }
        let backHalf = DataSample.tail(data.rssiRawSamples, 30)
//        var rawAvg: [Date: Double] = rawBuckets.mapValues{$0.reduce(0.0){acc,next in acc+next.value}/Double($0.count)}
//        var rawAmp: [Date: Double] = rawBuckets.map { (key, value) in
//            let minValue = value.map{$0.value}.min()!
//            let maxValue = value.map{$0.value}.max()!
//            return (key, abs(maxValue - minValue))
//        }
        var rawMax = backHalf.reduce(-1000) { acc, next in max(acc, next.value) }
        var rawMin = backHalf.reduce(1000) { acc, next in min(acc, next.value) }
//        var smoothBuckets = data.rssiSmoothedSamples.reduce([Date: [DataSample]]()) { acc, next in
//            var ret = acc
//            let idx = Date(timeIntervalSince1970: trunc10s(next.date.timeIntervalSince1970))
//            ret[idx] = (ret[idx] ?? []) + [next]
//            return ret
//        }
//        var smoothAvg = smoothBuckets.mapValues{$0.reduce(0.0){acc,next in acc+next.value}/Double($0.count)}
        
//        assert(rawBuckets.keys == smoothBuckets.keys, "\(rawBuckets.keys) == \(smoothBuckets.keys)")
//        var delta = Array(rawAvg.values).average() - Array(smoothAvg.values).average()
        var delta = abs(rawMax - rawMin) * 1.5
        print("delta=\(delta)")
        var testVariance = delta
        bluetoothLinkModel.value?.measureVariance = delta
//        var testFilter = KalmanFilter(
//            initialState: data.smoothingFunc!.state,
//            initialCovariance: data.smoothingFunc!.covariance,
//            processVariance: data.smoothingFunc!.processVariance,
//            measureVariance: testVariance)
        data.smoothingFunc?.measureVariance = delta
//        if let last = data.rssiRawSamples.last {
//            let s = DataSample(last.date, data.smoothingFunc!.update(measurement: last.value))
//            data.rssiSmoothedSamples.append(s)
//        }
//        data.rssiSmoothedSamples = testSamples
    }
    
    func onAppear() {
        let linkModel = bluetoothLinkModel.value!
        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == linkModel.deviceId}!
        let isNew = domainModel.links.first{$0.id == linkModel.id} == nil
        monitor = bluetoothMonitor.startMonitoring(
            linkModel.deviceId,
            smoothing: (referenceRSSIAtOneMeter: linkModel.referencePower, processNoise: linkModel.processVariance, measureNoise: linkModel.measureVariance))

        // just for the UX, backfill with existing data
        // if new, pick any available monitor for the device, but recalculate with current settings
        // if existing, we can keep all the data since we always start with the current settings
        if isNew {
            if let data = bluetoothMonitor.dataFor(deviceId: linkedDevice.id).first {
                monitor!.data.rssiRawSamples = data.rssiRawSamples
                monitor!.data.smoothingFunc = KalmanFilter(
                    initialState: monitor!.data.rssiRawSamples.last?.value ?? linkModel.referencePower,
                    initialCovariance: 0.01,
                    processVariance: linkModel.processVariance,
                    measureVariance: linkModel.measureVariance
                )

                BluetoothMonitor.recalculate(monitorData: monitor!.data)
            }
        } else {
            let linkState = runtimeModel.value.linkStates.first{$0.id == linkModel.id} as! BluetoothLinkState
            monitor!.data.rssiRawSamples = linkState.monitorData.data.rssiRawSamples
            monitor!.data.rssiSmoothedSamples = linkState.monitorData.data.rssiSmoothedSamples
            monitor!.data.distanceSmoothedSamples = linkState.monitorData.data.distanceSmoothedSamples
            monitor!.data.smoothingFunc = linkState.monitorData.data.smoothingFunc
        }
        
        calibrationCancelable = calibrationTimer.sink(receiveValue: {_ in self.calibrate()})

    }
}

struct Test: View {

    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor
    @EnvironmentObject var advancedMode: EnvVar<Bool>

    // TODO: i think this is optional because its easier to pass the binding?
    // technically this should never be empty
    @Binding var bluetoothLinkModel: OptionalModel<BluetoothLinkModel>
    // We use a dedicated monitor in this view instead of the link's or another existing monitor
    // because we want the view to react live without impact to changes in the view without having to save
    @State var monitor: BluetoothMonitor.Monitored?
    
    @State var linkedLastSeenRSSI: Double?
    @State var linkedLastSeenAt: Date?
    
    var calibrationTimer = Timed(interval: 2)
    @State var calibrationCancelable: AnyCancellable? = nil
    
    var body: some View {
        let linkModel = bluetoothLinkModel.value!
        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == linkModel.deviceId}
        let linkedZone: Binding<UUID?> = bindOpt($bluetoothLinkModel,
                                                 {$0?.zoneId},
                                                 {$0.value?.zoneId = $1!})
        VStack(alignment: .leading) {
            Picker("Max distance",
                   selection: Binding<Distance>(get: {Distance.fromMeters(linkModel.maxDistance)},
                                                set: {bluetoothLinkModel.value?.maxDistance = $0.toMeters()})) {
                Button("") {
                    
                }
            }
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
                                    processVariance: BluetoothLinkModel.DefaultProcessVariance,
                                    measureVariance: BluetoothLinkModel.DefaultMeasureVariance,
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
