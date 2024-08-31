import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement
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
    let content: Content
    
    init(label: String, horizontal: Bool, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = horizontal
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading) {
            if horizontal {
                HStack(alignment: .top) {
                    Text(label)
                    content
                }
            } else {
                VStack(alignment: .leading) {
                    Text(label)
                    content
                }
            }
            if let description {
                HStack() {
                    Text(description)
                        .fontWidth(.condensed)
                        .fontWeight(.light)
                        .italic()
                }.padding(EdgeInsets(top: 0, leading: 30, bottom: 0, trailing: 0))
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
            Text(format(value))
                .frame(minWidth: 50)
            Slider(value: $value, in: `in`, step: step)
        }
    }
}
struct LabeledDoubleSlider: View {
    
    var label: String
    let description: String?
    @Binding var value: Double
    let `in`: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledView(label: label, horizontal: true, description: description) {
            Text(format(value))
                .frame(minWidth: 50)
            Slider(value: $value, in: `in`, step: step)
        }
    }
}

struct SettingsView: View {
    let logger = Logger(subsystem: "TooFarDidntLock", category: "Settings")

    @Binding var deviceLinkModel: DeviceLinkModel?
    @Binding var availableDevices: [BluetoothDeviceModel]
    @Binding var linkedDeviceRSSIRawSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceRSSISmoothedSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceDistanceSamples: [Tuple2<Date, Double>]
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

    @EnvironmentObject var launchAtStartup: EnvVar<Bool>
    @Binding var safetyPeriodSeconds: Int
    @Binding var cooldownPeriodSeconds: Int

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Launch at startup", isOn: $launchAtStartup.wrappedValue)
                .onChange(of: launchAtStartup) {
                    if (launchAtStartup.wrappedValue) {
                        do {
                            try SMAppService.mainApp.register()
                        } catch {
                            logger.error("Failed to register service \(error)")
                        }
                    } else {
                        do {
                            try SMAppService.mainApp.unregister()
                        } catch {
                            logger.error("Failed to unregister service \(error)")
                        }
                    }
                }
            LabeledIntSlider(
                label: "Safety period",
                description: "Auto locking is disabled for a while on launch to prevent lockout if the app is bugged",
                value: $safetyPeriodSeconds, in: 0...900, step: 30, format: {formatMinSec(msec: $0)})
            LabeledIntSlider(
                label: "Cooldown period",
                description: "When the screen is unlocked, wait a while before activating again.",
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

    @Binding var deviceLinkModel: DeviceLinkModel?
    @Binding var availableDevices: [BluetoothDeviceModel]
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

    @Binding var availableDevices: [BluetoothDeviceModel]

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
                let items = showOnlyNamedDevices ? availableDevices.filter{$0.name?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 0} : availableDevices
                List(Binding.constant(items), id: \.uuid) { device in
                    VStack(alignment: .leading) {
                        DeviceView(
                            uuid: Binding.constant(device.wrappedValue.uuid.uuidString),
                            name: Binding.constant(device.wrappedValue.name),
                            rssi: Binding.constant(device.wrappedValue.rssi),
                            lastSeenAt: Binding.constant(nil))
                    }
                    .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrag({ NSItemProvider(object: device.wrappedValue.uuid.uuidString as NSString) })
                    .background(availableDevicesHover == device.wrappedValue.uuid ? Color.gray.opacity(0.3) : Color.clear)
                    .onHover { hovering in
                        availableDevicesHover = hovering ? device.wrappedValue.uuid : nil
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct LineChart: View {
    @Binding var samples: [Tuple2<Date, Double>]
    @State var xRange: Int
    @Binding var yAxisMin: Double
    @Binding var yAxisMax: Double
    var body: some View {
        let now = Date.now
        let xAxisMin = Calendar.current.date(byAdding: .second, value: -(xRange+1), to: now)!
        let xAxisMax = Calendar.current.date(byAdding: .second, value: 0, to: now)!
        
        let average: Double? = (samples.first != nil) && (samples.last != nil) ? (samples.first!.b + samples.last!.b) / 2.0 : nil
        let averageSamples: [Tuple2<Date, Double>]? = average != nil ? [Tuple2(xAxisMin, average!), Tuple2(xAxisMax, average!)] : nil
        
        Chart {
            if samples.count > 2 {
                ForEach(samples, id: \.a) { sample in
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
            if samples.count > 2 {
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

    @Binding var deviceLinkModel: DeviceLinkModel?
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
    
    @Binding var deviceLinkModel: DeviceLinkModel?
    @Binding var availableDevices: [BluetoothDeviceModel]
    @Binding var linkedDeviceRSSIRawSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceRSSISmoothedSamples: [Tuple2<Date, Double>]
    @Binding var linkedDeviceDistanceSamples: [Tuple2<Date, Double>]

    @State var linkedDeviceId: UUID?
    @State var linkedDeviceReferencePower: Double = 0
    @State var linkedDeviceMaxDistance: Double = 0
    @State var linkedDeviceIdleTimeout: Double = 10
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Drag and drop a device from the list here to link it.")
            GroupBox(label: Label("Linked device", systemImage: "")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        HStack {
                            let linkedDevice = deviceLinkModel?.deviceDetails
                            DeviceView(
                                uuid: Binding.constant(linkedDevice?.uuid.uuidString),
                                name: Binding.constant(linkedDevice?.name),
                                rssi: Binding.constant(linkedDevice?.rssi),
                                lastSeenAt: Binding.constant(linkedDevice?.lastSeenAt))
                                .padding(4)
                                .border(Color.gray, width: 1)
                                .cornerRadius(2)
                        }
                        HStack {
                            Text("Reference Power")
                            Slider(value: $linkedDeviceReferencePower, in: -100...0)
                            .onChange(of: linkedDeviceReferencePower) {
                                if let _ = deviceLinkModel {
                                    deviceLinkModel?.referencePower = linkedDeviceReferencePower
                                }
                            }
                            Text("\(String(format: "%.0f", linkedDeviceReferencePower))")
                        }
                        HStack {
                            Text("Max distance")
                            Slider(value: $linkedDeviceMaxDistance, in: 0.0...9.0, step: 0.25)
                            .onChange(of: linkedDeviceMaxDistance) {
                                if let _ = deviceLinkModel {
                                    deviceLinkModel?.maxDistance = linkedDeviceMaxDistance
                                }
                            }
                            Text("\(String(format: "%.2f", linkedDeviceMaxDistance))")
                        }
                        HStack {
                            Text("Idle timeout")
                            Slider(value: $linkedDeviceIdleTimeout, in: 0...10*60, step: 10)
                            .onChange(of: linkedDeviceIdleTimeout) {
                                let a = deviceLinkModel
                                let b = deviceLinkModel?.idleTimeout
                                let c = linkedDeviceIdleTimeout
                                if let _ = deviceLinkModel {
                                    deviceLinkModel?.idleTimeout = linkedDeviceIdleTimeout
                                    deviceLinkModel = deviceLinkModel
                                }
                            }
                            Text("\(formatMinSec(msec: linkedDeviceIdleTimeout))")
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
        .onChange(of: availableDevices) {
            if let linkedDevice = deviceLinkModel?.deviceDetails,
               let listedDevice = availableDevices.first(where: {$0.uuid == linkedDevice.uuid}) {
                deviceLinkModel?.deviceDetails = listedDevice
            }
        }
        .onAppear {
        }
        .onChange(of: scenePhase) { (old, new) in
            guard new == .active else { return }
            if let deviceLinkModel = deviceLinkModel {
                self.linkedDeviceId = deviceLinkModel.uuid
                self.linkedDeviceReferencePower = deviceLinkModel.referencePower
                self.linkedDeviceMaxDistance = deviceLinkModel.maxDistance
                self.linkedDeviceIdleTimeout = deviceLinkModel.idleTimeout ?? 0
                
            }
        }
    }
    
    func onDeviceLinkDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    if let uuidString = object as? String {
                        if let device = availableDevices.first(where: {$0.uuid.uuidString == uuidString}) {
                            DispatchQueue.main.async {
                                self.linkedDeviceId = device.uuid
                                self.linkedDeviceReferencePower = device.rssi
                                self.linkedDeviceMaxDistance = device.rssi

                                self.deviceLinkModel = DeviceLinkModel(
                                    uuid: device.uuid,
                                    deviceDetails: device,
                                    referencePower: device.rssi,
                                    maxDistance: linkedDeviceMaxDistance,
                                    idleTimeout: linkedDeviceIdleTimeout
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
