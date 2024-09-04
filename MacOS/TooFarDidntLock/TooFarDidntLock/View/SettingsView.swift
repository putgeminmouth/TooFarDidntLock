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

struct SettingsView: View {
    let logger = Log.Logger("SettingsView")

    @Binding var launchAtStartup: Bool
    @Binding var showSettingsAtStartup: Bool
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

            TabView {[
                .tab(label: "General", icon: Icons.settings.toImage()) {
                    GeneralSettingsView(
                        launchAtStartup: $launchAtStartup,
                        showSettingsAtStartup: $showSettingsAtStartup,
                        showInDock: $showInDock,
                        safetyPeriodSeconds: $safetyPeriodSeconds,
                        cooldownPeriodSeconds: $cooldownPeriodSeconds)
                },
                .tab(label: "Links", icon: Icons.link.toImage()) {
                    LinksSettingsView()
                },
                .tab(label: "Zones", icon: Icons.zone.toImage()) {
                    ZoneSettingsView()
                },
                .divider,
                .tab(label: "Wifi", icon: Icons.wifi.toImage()) {
                    WifiSettingsView()
                },
                .tab(label: "Bluetooth", icon: Icons.bluetooth.toImage()) {
                    BluetoothSettingsView()
                }
            ]}
        }
        
    }
}

struct GeneralSettingsView: View {
    let logger = Log.Logger("GeneralSettingsView")

    @Binding var launchAtStartup: Bool
    @Binding var showSettingsAtStartup: Bool
    @Binding var showInDock: Bool
    @Binding var safetyPeriodSeconds: Int
    @Binding var cooldownPeriodSeconds: Int

    var body: some View {
        VStack(alignment: .leading) {
            Toggle("Launch at startup", isOn: $launchAtStartup)
            Toggle("Show this screen on startup", isOn: $showSettingsAtStartup)
            Toggle("Show in dock", isOn: $showInDock)
            
            Divider()
                .padding(20)
            
            LabeledIntSlider(
                label: "Safety period",
                description: "When the app starts up, locking is disabled for a while. This provides a safety window to make sure you can't get permanently locked out.",
                value: $safetyPeriodSeconds, in: 0...900, step: 30, format: {formatMinSec(msec: $0)})
            LabeledIntSlider(
                label: "Cooldown period",
                description: "Prevents locking again too quickly each time the screen is unlocked in order to avoid getting permanently locked out.",
                value: $cooldownPeriodSeconds, in: 30...500, step: 10, format: {formatMinSec(msec: $0)})

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

struct LineChart: View {
    typealias Samples = [DataDesc: [DataSample]]
    
    @State var refreshViewTimer = Timed(interval: 2)
    @Binding var samples: Samples
    @State var xRange: Int
    @Binding var yAxisMin: Double
    @Binding var yAxisMax: Double
    var body: some View {
        // we want to keep the graph moving even if no new data points have come in
        // this binds the view render to the timer updates
        // TODO: is still working?
        let _ = refreshViewTimer
        let now = Date.now
        let xAxisMin = Calendar.current.date(byAdding: .second, value: -(xRange+1), to: now)!
        let xAxisMax = Calendar.current.date(byAdding: .second, value: 0, to: now)!

        let filteredSamples: [(key: DataDesc, value: [DataSample])] = samples
            .mapValues{$0.filter{$0.date > xAxisMin}}
            .sorted(by: {$0.key < $1.key})
        
        Chart {
            ForEach(Binding.constant(filteredSamples.map{(key: $0.key, value: $0.value)}), id: \.wrappedValue.key) {
                let filteredSampleKey = $0.wrappedValue.key //$0.wrappedValue.0
                let filteredSample = $0.wrappedValue.value // $0.wrappedValue.1
                if filteredSample.count > 2 {
                    ForEach(filteredSample, id: \.date) { sample in
                        // sereies just needs to be unique AFAICT, actual value doesn't matter
                        LineMark(x: .value("t", sample.date), y: .value("", sample.value), series: .value("", filteredSampleKey))
                        // second value is legend
                            .foregroundStyle(by: .value("", filteredSampleKey.lowercased()))
                        PointMark(x: .value("t", sample.date), y: .value("", sample.value))
                            .symbolSize(10)
                    }
                }
            }
        }
        .chartLegend(.visible)
        .chartLegend(position: .bottom)
        .overlay {
            if filteredSamples.contains { $0.value.count > 2 } {
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

struct SignalMonitorView: View {
    enum ChartType: CaseIterable {
        case rssiRaw
        case rssiSmoothed
        case distance
    }

    @State var monitorData: any SignalMonitorData
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
        .onReceive($monitorData.wrappedValue.publisher) { _ in
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
