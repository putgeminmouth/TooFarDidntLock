import SwiftUI
import UniformTypeIdentifiers
import OSLog
import Charts

func formatMinSec(msec: Int) -> String {
    return formatMinSec(msec: Double(msec))
}
func formatMinSec(msec: Double) -> String {
    return "\(Int(msec / 60))m \(Int(msec) % 60)s"
}

extension Slider<EmptyView, EmptyView> {
    init(value: Binding<Int>, in bounds: ClosedRange<Int>, step: Int) {
        let dValue: Binding<Double> = bindIntAsDouble(value)
        let dBounds: ClosedRange<Double> = Double(bounds.lowerBound)...Double(bounds.upperBound)
        let dStep: Double = Double(step)

        self.init(value: dValue, in: dBounds, step: dStep)
    }
}

struct LabeledView<Content: View>: View {
    @State var label: String
    @State var horizontal: Bool = true
    @State var description: String?
    @State var descriptionShowing: Bool = false
    let content: Content
    
    init(label: String, horizontal: Bool, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = horizontal
        self.description = description
        self.content = content()
    }

    var body: some View {
        let info = Image(systemName: description != nil ? "info.circle" : "")
            .frame(width: 0, height: 0)
            .onTapGesture {
                descriptionShowing.toggle()
            }
            .popover(isPresented: $descriptionShowing) {
                HStack(alignment: .top) {
                    Text(description!)
                        .frame(width: 200)
//                                    .fixedSize(horizontal: true, vertical: true)
//                                    .lineLimit(nil)
//                        .fixedSize(horizontal: true, vertical: true)
//                        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
//                .frame(maxHeight: 300)
            }
        VStack(alignment: .leading) {
            if horizontal {
                HStack(alignment: .top) {
                    Text(label)
                    info
                    content
                }
            } else {
                VStack(alignment: .leading) {
                    Text(label)
                    info
                    content
                }
            }
        }
    }
}

struct LabeledIntSlider: View {
    
    var label: String
    let description: String?
    @Binding var value: Int
    let `in`: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    var body: some View {
        LabeledView(label: label, horizontal: true, description: description) {
            Slider(value: $value, in: `in`, step: step)
            Text(format(value))
                .frame(minWidth: 50, alignment: .trailing)
        }
    }
}
struct LabeledDoubleSlider: View {
    
    var label: String
    let description: String?
    @Binding var value: Double
    let `in`: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        LabeledView(label: label, horizontal: true, description: description) {
            if let step = step {
                Slider(value: $value, in: `in`, step: step)
            } else {
                Slider(value: $value, in: `in`)
            }
            Text(format(value))
                .frame(minWidth: 50, alignment: .trailing)
        }
    }
}

struct SettingsView: View {
    let logger = Logger(subsystem: "TooFarDidntLock", category: "Settings")

    @Binding var deviceLinkModel: OptionalModel<DeviceLinkModel>
    @Binding var availableDevices: [MonitoredPeripheral]
    @Binding var linkedDeviceRSSIRawSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceRSSISmoothedSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceDistanceSamples: [Tuple2<Date, Double>]
    @Binding var launchAtStartup: Bool
    @Binding var showInDock: Bool
    @Binding var safetyPeriodSeconds: Int
    @Binding var cooldownPeriodSeconds: Int

    var body: some View {
        ZStack {
            Image("AboutImage")
                .resizable()
                .scaledToFit()
                .frame(width: 500, height: 500)
                .blur(radius: 20)
                .opacity(0.080)

            ATabView {
                ATab("General", systemName: "gear") {
                    GeneralSettingsView(
                        launchAtStartup: $launchAtStartup,
                        showInDock: $showInDock,
                        safetyPeriodSeconds: $safetyPeriodSeconds,
                        cooldownPeriodSeconds: $cooldownPeriodSeconds)
                }
                ATab("Bluetooth", resource: "Bluetooth") {
                    BluetoothSettingsView(
                        deviceLinkModel: $deviceLinkModel,
                        availableDevices: $availableDevices,
                        linkedDeviceRSSIRawSamples: $linkedDeviceRSSIRawSamples,
                        linkedDeviceRSSISmoothedSamples: $linkedDeviceRSSISmoothedSamples,
                        linkedDeviceDistanceSamples: $linkedDeviceDistanceSamples
                    )
                }
            }
        }
        
    }
}

struct GeneralSettingsView: View {
    let logger = Logger(subsystem: "TooFarDidntLock", category: "Settings")

    @Binding var launchAtStartup: Bool
    @Binding var showInDock: Bool
    @Binding var safetyPeriodSeconds: Int
    @Binding var cooldownPeriodSeconds: Int

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Launch at startup", isOn: $launchAtStartup)
            Toggle("Show in dock", isOn: $showInDock)
            LabeledIntSlider(
                label: "Safety period",
                description: "When the app starts up, locking is disabled for a while. This provides a safety window to make sure you can't get permanently locked out.",
                value: $safetyPeriodSeconds, in: 0...900, step: 30, format: {formatMinSec(msec: $0)})
            LabeledIntSlider(
                label: "Cooldown period",
                description: "Prevents locking again too quickly each time the screen is unlocked. This can happen depending on your environment or configuration.",
                value: $cooldownPeriodSeconds, in: 0...500, step: 10, format: {formatMinSec(msec: $0)})

        }
        .navigationTitle("Settings: Too Far; Didn't Lock")
        .padding()
        .onAppear() {
            logger.debug("SettingsView.appear")
            NSApp.activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification), perform: { _ in
        })
    }
}

struct BluetoothSettingsView: View {
    let logger = Logger(subsystem: "TooFarDidntLock", category: "Settings")

    @Binding var deviceLinkModel: OptionalModel<DeviceLinkModel>
    @Binding var availableDevices: [MonitoredPeripheral]
    @Binding var linkedDeviceRSSIRawSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceRSSISmoothedSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceDistanceSamples: [Tuple2<Date, Double>]

    var body: some View {
        VStack(alignment: .leading) {
            DeviceLinkSettingsView(
                deviceLinkModel: $deviceLinkModel,
                availableDevices: $availableDevices,
                linkedDeviceRSSIRawSamples: $linkedDeviceRSSIRawSamples,
                linkedDeviceRSSISmoothedSamples: $linkedDeviceRSSISmoothedSamples,
                linkedDeviceDistanceSamples: $linkedDeviceDistanceSamples
            )
            
            Spacer()
            
            AvailableDevicesSettingsView(availableDevices: $availableDevices)
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

    @Binding var availableDevices: [MonitoredPeripheral]

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
                let items = showOnlyNamedDevices ? availableDevices.filter{$0.peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 0} : availableDevices
                List(Binding.constant(items), id: \.peripheral.identifier) { device in
                    VStack(alignment: .leading) {
                        DeviceView(
                            uuid: Binding.constant(device.wrappedValue.peripheral.identifier.uuidString),
                            name: Binding.constant(device.wrappedValue.peripheral.name),
                            rssi: Binding.constant(device.wrappedValue.lastSeenRSSI),
                            lastSeenAt: Binding.constant(nil))
                    }
                    .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrag({ NSItemProvider(object: device.wrappedValue.peripheral.identifier.uuidString as NSString) })
                    .background(availableDevicesHover == device.wrappedValue.peripheral.identifier ? Color.gray.opacity(0.3) : Color.clear)
                    .onHover { hovering in
                        availableDevicesHover = hovering ? device.wrappedValue.peripheral.identifier : nil
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct LineChart: View {
    @State var refreshViewTimer = Timed(interval: 2)
    @Binding var samples: [Tuple2<Date, Double>]
    @State var xRange: Int
    @Binding var yAxisMin: Double
    @Binding var yAxisMax: Double
    var body: some View {
        // we want to keep the graph moving even if no new data points have come in
        // this binds the view render to the timer updates
        let _ = refreshViewTimer
        let now = Date.now
        let xAxisMin = Calendar.current.date(byAdding: .second, value: -(xRange+1), to: now)!
        let xAxisMax = Calendar.current.date(byAdding: .second, value: 0, to: now)!

        let filteredSamples = samples.filter{$0.a > xAxisMin}
        let average: Double? = (filteredSamples.first != nil) && (filteredSamples.last != nil) ? (filteredSamples.first!.b + filteredSamples.last!.b) / 2.0 : nil
        let averageSamples: [Tuple2<Date, Double>]? = average != nil ? [Tuple2(xAxisMin, average!), Tuple2(xAxisMax, average!)] : nil
        
        Chart {
            if filteredSamples.count > 2 {
                ForEach(filteredSamples, id: \.a) { sample in
                    LineMark(x: .value("t", sample.a), y: .value("y", sample.b), series: .value("", "samples"))
                    PointMark(x: .value("t", sample.a), y: .value("y", sample.b))
                        .symbolSize(10)
                    AreaMark(x: .value("t", sample.a), yStart: .value("y", yAxisMin), yEnd :.value("y", sample.b))
                        .foregroundStyle(Color.init(hue: 1, saturation: 0, brightness: 1, opacity: 0.05))
                }
                
                if let averageSamples {
                    ForEach(averageSamples, id: \.a) { sample in
                        LineMark(x: .value("t2", sample.a), y: .value("y2", sample.b), series: .value("", "regression"))
                            .lineStyle(StrokeStyle(dash: [5]))
                            .foregroundStyle(Color.init(hue: 1, saturation: 0, brightness: 0.40, opacity: 1.0))
                    }
                }
            }
        }.overlay {
            if filteredSamples.count > 2 {
                EmptyView()
            } else {
                Text("Gathering data...")
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: stride(from: xAxisMax, to: xAxisMin, by: -10).map{$0}.reversed()) { value in
                AxisValueLabel("\(-Int(value.as(Date.self)?.distance(to: now) ?? 0))s")
            }
        }
        .chartYScale(domain: yAxisMin...yAxisMax)
        .padding(.leading, 20)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .padding(.trailing, 5)
        .border(Color.gray, width: 1)
    }
}

struct DeviceMonitorView: View {
    enum ChartType: CaseIterable {
        case rssiRaw
        case rssiSmoothed
        case distance
    }

    @Binding var deviceLinkModel: OptionalModel<DeviceLinkModel>
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

extension Array where Element == Double {
    func mean() -> Double {
        return self.reduce(0, +) / Double(self.count)
    }
    
    func standardDeviation() -> Double {
        guard !self.isEmpty else { return 0 }
        let meanValue = self.mean()
        let variance = self.reduce(0) { (result, value) -> Double in
            let diff = value - meanValue
            return result + diff * diff
        } / Double(self.count)
        return sqrt(variance)
    }
    
    func percentile(_ percentilePercent: Double) -> Double {
        let sortedData = self.sorted()
        let index = Int(Double(sortedData.count - 1) * percentilePercent / 100.0)
        return sortedData[index]
    }
    
    func average() -> Double {
        guard count > 0 else { return 0 }
        let avg = self.reduce(0, +) / Double(self.count)
        return avg
    }
}
extension Array where Element == Tuple2<Date, Double> {
    func runningPercentile(windowSampleCount: Int, percentilePercent: Double) -> [Tuple2<Date, Double>] {
        guard windowSampleCount > 0 else { return [] }
        var result = [Tuple2<Date, Double>]()
        let sampleCount = Swift.min(self.count, windowSampleCount)
        let windowCount = self.count / windowSampleCount
        for i in 0..<windowCount {
            let window = Array(self[i..<(i + sampleCount)])
            assert( window.count > 0)
            result.append(Tuple2(
                Date(timeIntervalSince1970: window.map{$0.a.timeIntervalSince1970}.reduce(0.0, +) / Double(window.count)),
                window.map{$0.b}.percentile(percentilePercent)
            ))
        }
        return result
    }
    
    func lastNSeconds(seconds: Double) -> [Tuple2<Date, Double>] {
        return self.filter{$0.a.distance(to: Date()) < seconds}
    }
}

struct DeviceLinkSettingsView: View {
    @Environment(\.scenePhase) var scenePhase
    
    @Binding var deviceLinkModel: OptionalModel<DeviceLinkModel>
    @Binding var availableDevices: [MonitoredPeripheral]
    @Binding var linkedDeviceRSSIRawSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceRSSISmoothedSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceDistanceSamples: [Tuple2<Date, Double>]

    @State var linkedDeviceId: UUID?
    @State var linkedDeviceReferencePower: Double = 0
    @State var linkedDeviceMaxDistance: Double = 1
    @State var linkedDeviceIdleTimeout: Double = 10
    @State var linkedDeviceRequireConnection: Bool = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Drag and drop a device from the list here to link it.")
            GroupBox(label: Label("Linked device", systemImage: "")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        HStack {
                            let linkedDevice = deviceLinkModel.value?.deviceDetails
                            DeviceView(
                                uuid: Binding.constant(deviceLinkModel.value?.uuid.uuidString),
                                name: Binding.constant(linkedDevice?.name),
                                rssi: Binding.constant(deviceLinkModel.value?.deviceState?.lastSeenRSSI),
                                lastSeenAt: Binding.constant(deviceLinkModel.value?.deviceState?.lastSeenAt))
                                .padding(4)
                                .border(Color.gray, width: 1)
                                .cornerRadius(2)
                        }
                        LabeledDoubleSlider(
                            label: "Reference Power",
                            description: "Set to the signal power at 1 meter.",
                            value: $linkedDeviceReferencePower, in: -100...0, format: {"\(Int($0))"})
                        .onChange(of: linkedDeviceReferencePower) {
                            if let _ = deviceLinkModel.value {
                                deviceLinkModel.value?.referencePower = linkedDeviceReferencePower
                            }
                        }
                        LabeledDoubleSlider(
                            label: "Max distance",
                            description: "The distance in meters at which the device is considered absent, resulting in a screen lock. It is calculated from the current signal strength and the reference power, and is not very stable or reliable. It is recommended to consider anything less than 5m as close, and anything more as far.",
                            value: $linkedDeviceMaxDistance, in: 0.0...9.0, step: 0.25, format: {"\(String(format: "%.2f", $0))"})
                        .onChange(of: linkedDeviceMaxDistance) {
                            if let _ = deviceLinkModel.value {
                                deviceLinkModel.value?.maxDistance = linkedDeviceMaxDistance
                            }
                        }
                        LabeledDoubleSlider(
                            label: "Idle timeout",
                            description: "Device is considered absent if not found for too long, resulting in a screen lock. Unless you configure an active connection, both the host and target device will scan / broadcast at intervals that may vary e.g. due to low power settings. It is recommended to set at least 10-30 seconds.",
                            value: $linkedDeviceIdleTimeout, in: 0...10*60, step: 10, format: {formatMinSec(msec: $0)})
                        .onChange(of: linkedDeviceIdleTimeout) {
                            if let _ = deviceLinkModel.value {
                                deviceLinkModel.value?.idleTimeout = linkedDeviceIdleTimeout
                                deviceLinkModel = deviceLinkModel
                            }
                        }
                        HStack {
                            LabeledView(
                                label: "Require connection",
                                horizontal: true,
                                description: "When active, the app will attempt to maintain a bluetooth connection to the device, reconnecting as necessary. If the connection fails, the screen will lock.") {
                                    Toggle("", isOn: $linkedDeviceRequireConnection)
                                        .onChange(of: linkedDeviceRequireConnection) {
                                            if let _ = deviceLinkModel.value {
                                                deviceLinkModel.value?.requireConnection = linkedDeviceRequireConnection
                                            }
                                        }
                                }
                            Spacer()
                            Image(systemName: (deviceLinkModel.value?.deviceState?.connectionState != .disconnected) ? "cable.connector" : "cable.connector.slash")
                                .colorMultiply(linkedDeviceRequireConnection ? .white : .gray)
                        }
                    }
                    
                    DeviceMonitorView(
                        deviceLinkModel: $deviceLinkModel,
                        linkedDeviceRSSIRawSamples: $linkedDeviceRSSIRawSamples,
                        linkedDeviceRSSISmoothedSamples: $linkedDeviceRSSISmoothedSamples,
                        linkedDeviceDistanceSamples: $linkedDeviceDistanceSamples
                    )
                }
                .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                .onDrop(of: ["public.text"], isTargeted: nil) { providers in
                    self.onDeviceLinkDrop(providers)
                    return true
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { (old, new) in
            guard new == .active else { return }
            if let deviceLinkModel = deviceLinkModel.value {
                self.linkedDeviceId = deviceLinkModel.uuid
                self.linkedDeviceReferencePower = deviceLinkModel.referencePower
                self.linkedDeviceMaxDistance = deviceLinkModel.maxDistance
                self.linkedDeviceIdleTimeout = deviceLinkModel.idleTimeout ?? 0
                self.linkedDeviceRequireConnection = deviceLinkModel.requireConnection
                
            }
        }
    }
    
    func onDeviceLinkDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let uuidString = object as? String {
                        if let device = availableDevices.first(where: {$0.peripheral.identifier.uuidString == uuidString}) {
                            // todo, i dont think dispatch was required here
//                            DispatchQueue.main.async {
                                self.linkedDeviceId = device.peripheral.identifier
                            self.linkedDeviceReferencePower = device.lastSeenRSSI
                            self.linkedDeviceMaxDistance = device.lastSeenRSSI

                                self.deviceLinkModel.value = DeviceLinkModel(
                                    uuid: device.peripheral.identifier,
                                    deviceDetails: BluetoothDeviceDescription(
                                        name: device.peripheral.name,
                                        txPower: device.txPower
                                    ),
                                    deviceState: device,
                                    referencePower: device.lastSeenRSSI,
                                    maxDistance: linkedDeviceMaxDistance,
                                    idleTimeout: linkedDeviceIdleTimeout,
                                    requireConnection: linkedDeviceRequireConnection
                                )
//                            }
                        }
                    }
                }
            }
        }
    }
}
