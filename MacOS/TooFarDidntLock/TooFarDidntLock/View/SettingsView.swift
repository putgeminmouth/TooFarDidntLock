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
