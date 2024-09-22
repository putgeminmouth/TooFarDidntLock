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
                SignalMonitorView(
                    monitorData: monitorData,
                    availableChartTypes: Set([.rssi]),
                    selectedChartTypes: Set([.rssi]),
                    ruleMarks: Binding.constant([])
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
            if advancedMode.value {
                Text("Name: \(name ?? "")")
                    .font(.title)
                Text("ID: \(id ?? "00000000-0000-0000-0000-000000000000")")
                    .font(.footnote)
                Text("Power: \(transmitPower ?? 0)")
                Text("RSSI: \(rssi ?? 0)")
                if let lastSeenAt = lastSeenAt { Text("Latency: \(lastSeenAt.distance(to: Date.now))s") }
            } else {
                Text("\(name ?? "Unknown")")
                    .font(.title)
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
    
    var body: some View {
        let linkModel = bluetoothLinkModel.value!
        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == linkModel.deviceId}
        let linkState = runtimeModel.value.linkStates.first{$0.id == linkModel.id} as? BluetoothLinkState
        let linkedZone: Binding<UUID?> = bindOpt($bluetoothLinkModel,
                                                 {$0?.zoneId},
                                                 {$0.value?.zoneId = $1!})
        let isNew = domainModel.links.first{$0.id == linkModel.id} == nil

        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                        ZoneSelectionView(
                            selectionCanStartNil: linkedZone,
                            nilMenuText: "Choose a Zone"
                        )
                    HVStack(!advancedMode.value ? .vertical(.leading) : .horizontal(.top)) {
                        BluetoothDeviceView(
                            id: Binding.constant(linkedDevice?.id.uuidString),
                            name: Binding.constant(linkedDevice?.name),
                            transmitPower: Binding.constant(linkedDevice?.transmitPower),
                            rssi: $linkedLastSeenRSSI,
                            lastSeenAt: $linkedLastSeenAt)
                        .padding(4)
                        .border(Color.gray, width: 1)
                        .cornerRadius(2)

                        HVStack(advancedMode.value ? .vertical(.leading) : .horizontal(.center)) {
                            CalibrateView(
                                onStart: startCalibration,
                                onUpdate: updateCalibration,
                                duration: 60.0,
                                isPresented: !advancedMode.value && isNew) { page in
                                    if page == 0 {
                                        VStack {
                                            Image("Icons/Calibrate/calibrate_512_256_clear_0")
                                            Text("Place the devices one meter apart, then Start.")
                                                .font(.headline)
                                            Text("The device's signal strength will be measured for up to a minute, allowing for more accurate distance estimation.")
                                                .font(.body)
                                                .wrappingMagic(lineLimit: 3)
                                        }
                                    } else {
                                        VStack {
                                            AnimatedImage(resources: [
                                                "Icons/Calibrate/calibrate_512_256_clear_0",
                                                "Icons/Calibrate/calibrate_512_256_clear_2",
                                                "Icons/Calibrate/calibrate_512_256_clear_0",
                                                "Icons/Calibrate/calibrate_512_256_clear_1",
                                                "Icons/Calibrate/calibrate_512_256_clear_0",
                                                "Icons/Calibrate/calibrate_512_256_clear_3",
                                                "Icons/Calibrate/calibrate_512_256_clear_0",
                                            ], delay: 2)
                                            Text("Please wait...")
                                                .font(.headline)
                                            Text("You can stop at any time and still benefit from partial calibration.")
                                                .font(.body)
                                                .wrappingMagic(lineLimit: 1)
                                        }
                                    }
                                }
                            Text("Calibrate")
                        }
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
                        HStack {
                            Toggle(
                                isOn: bindOpt($bluetoothLinkModel,
                                              {$0?.autoMeasureVariance ?? advancedMode.value},
                                              {$0.value!.autoMeasureVariance=$1}),
                                label: {Image(systemName: "livephoto.badge.automatic")})
                                .help("Auto tune")
                            LabeledDoubleSlider(
                                label: "Measure variance",
                                description: "TODO",
                                value: bindOpt($bluetoothLinkModel,
                                               {$0?.measureVariance ?? BluetoothLinkModel.DefaultMeasureVariance},
                                               {$0.value!.measureVariance=$1}),
                                in: 0.01...50,
                                format: {"\(String(format: "%.2f", $0))"})
                            .disabled(bluetoothLinkModel.value?.autoMeasureVariance ?? false)
                        }
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
                            in: 0.0...9.0, step: 0.25, format: {"\(String(format: "%.2f", $0))m"})
                        LabeledDoubleSlider(
                            label: "Link state tolerance",
                            description: "The min duration before the link will change states.",
                            value: bindOpt($bluetoothLinkModel,
                                           {$0?.linkStateDebounce ?? 0.0},
                                           {$0.value!.linkStateDebounce=$1}),
                            in: 0.0...90, step: nil, format: {formatMinSec(msec: $0)})
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
                    let available: Set<SignalMonitorView.ChartType> = advancedMode.value ? Set(SignalMonitorView.ChartType.allCases) : Set([.distance])
                    let selected: Set<SignalMonitorView.ChartType> = advancedMode.value ? Set([.rssi]) : Set([.distance])
                    SignalMonitorView(
                        monitorData: monitor.data,
                        availableChartTypes: available,
                        selectedChartTypes: selected,
                        ruleMarks: Binding.constant(linkState?.stateChangedHistory ?? [])
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
            
            // since we use a disconnected monitor and link, we emulate what is done by the Link manager here
            if let monitor = monitor,
               bluetoothLinkModel.value != nil {
                if bluetoothLinkModel.value!.autoMeasureVariance {
                    BluetoothLinkEvaluator.autoTuneMeasureVariance(model: &(bluetoothLinkModel.value!), data: monitor.data)
                }
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
        .onChange(of: bluetoothLinkModel.value?.measureVariance ?? 0) { (old, new) in
            monitor?.data.smoothingFunc?.measureVariance = new
        }
    }
    
    func startCalibration() {
        bluetoothLinkModel.value?.measureVariance = 20
        bluetoothLinkModel.value?.processVariance = 1
    }

    func updateCalibration(startedAt: Date, elapsed: TimeInterval) -> CalibrateView.Action {
        guard let monitor = monitor
        else { return .stop }
        guard elapsed < 60
        else { return .stop }
        guard !monitor.data.rssiRawSamples.isEmpty
        else { return .continue }

        let data = monitor.data

        // calc avg even if sample data doesn't meet all requirements, best effort
        // ideally we continue until more data is available though
        if let avg = data.rssiSmoothedSamples.map{$0.value}.average() {
            bluetoothLinkModel.value?.referencePower = avg
        }

        guard data.rssiRawSamples.count > 1
        else { return .continue }
        
        let now = Date.now
        guard let maxDate = data.rssiSmoothedSamples.map{$0.date.distance(to: Date.now)}.max(),
            let minDate = data.rssiSmoothedSamples.map{$0.date.distance(to: Date.now)}.min()
        else { return .continue }
        
        guard let last = data.rssiSmoothedSamples.last
        else { return .continue}
        
        let ret: CalibrateView.Action = startedAt.distance(to: last.date) > 30 ? .stop : .continue
        return ret
    }
    
    func onAppear() {
        let linkModel = bluetoothLinkModel.value!
        let isNew = domainModel.links.first{$0.id == linkModel.id} == nil
        monitor = bluetoothMonitor.startMonitoring(
            linkModel.deviceId,
            smoothing: (referenceRSSIAtOneMeter: linkModel.referencePower, processNoise: linkModel.processVariance, measureNoise: linkModel.measureVariance))

        // just for the UX, backfill with existing data
        // if new, pick any available monitor for the device, but recalculate with current settings
        // if existing, we can keep all the data since we always start with the current settings
        if isNew {
            if let data = bluetoothMonitor.dataFor(deviceId: linkModel.deviceId).first {
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
    }
}

//struct Test: View {
//
//    @Environment(\.scenePhase) var scenePhase
//    @EnvironmentObject var domainModel: DomainModel
//    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
//    @EnvironmentObject var bluetoothMonitor: BluetoothMonitor
//    @EnvironmentObject var advancedMode: EnvVar<Bool>
//
//    // TODO: i think this is optional because its easier to pass the binding?
//    // technically this should never be empty
//    @Binding var bluetoothLinkModel: OptionalModel<BluetoothLinkModel>
//    // We use a dedicated monitor in this view instead of the link's or another existing monitor
//    // because we want the view to react live without impact to changes in the view without having to save
//    @State var monitor: BluetoothMonitor.Monitored?
//    
//    @State var linkedLastSeenRSSI: Double?
//    @State var linkedLastSeenAt: Date?
//    
//    var body: some View {
//        let linkModel = bluetoothLinkModel.value!
//        let linkedDevice = runtimeModel.value.bluetoothStates.first{$0.id == linkModel.deviceId}
//        let linkedZone: Binding<UUID?> = bindOpt($bluetoothLinkModel,
//                                                 {$0?.zoneId},
//                                                 {$0.value?.zoneId = $1!})
//        let isNew = domainModel.links.first{$0.id == linkModel.id} == nil
//        
//        CalibrateView(
//            onStart: {},
//            onUpdate: {_ in .stop},
//            duration: 60.0,
//            autoStart: !advancedMode.value && isNew) { page in
//                if page == 0 {
//                    VStack {
//                        Image("Icons/Calibrate/calibrate_512_256_clear_0")
//                        Text("Place the devices one meter apart to measure the device's signal strength.")
//                    }
//                } else {
//                    VStack {
//                        AnimatedImage(resources: [
//                            "Icons/Calibrate/calibrate_512_256_clear_0",
//                            "Icons/Calibrate/calibrate_512_256_clear_2",
//                            "Icons/Calibrate/calibrate_512_256_clear_0",
//                            "Icons/Calibrate/calibrate_512_256_clear_1",
//                            "Icons/Calibrate/calibrate_512_256_clear_0",
//                            "Icons/Calibrate/calibrate_512_256_clear_3",
//                            "Icons/Calibrate/calibrate_512_256_clear_0",
//                        ], delay: 2)
//                        Text("Please wait... the signal is being continuously measured so you can stop at any time and still keep less accurate results.")
//                    }
//                }
//            }
//        Text("Calibrate")
//    }
//}

struct EditBluetoothDeviceLinkModal: View {
    
    @EnvironmentObject var domainModel: DomainModel
    @EnvironmentObject var runtimeModel: NotObserved<RuntimeModel>
    @EnvironmentObject var advancedMode: EnvVar<Bool>

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
                                    autoMeasureVariance: advancedMode.value,
                                    maxDistance: 1.0,
                                    idleTimeout: 60,
                                    requireConnection: false,
                                    linkStateDebounce: BluetoothLinkModel.DefaultLinkStateDebounce)
                                self.page = "2"
                            }
                    }
                    .frame(minHeight: 300)
                } else if page == "2" {
                    GroupBox("Configure") {
                        BluetoothLinkSettingsView(bluetoothLinkModel: $itemBeingEdited)
                            .frame(idealHeight: 99999) // dunno why it needs this but otherwise it cuts off
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
