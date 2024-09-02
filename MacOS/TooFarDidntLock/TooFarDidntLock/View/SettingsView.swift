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
