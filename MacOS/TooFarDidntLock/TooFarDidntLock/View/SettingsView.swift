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
    init(horizontal label: String, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = true
        self.description = description
        self.content = content()
    }
    init(vertical label: String, description: String? = nil, @ViewBuilder _ content: @escaping () -> Content) {
        self.label = label
        self.horizontal = false
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
    let logger = Log.Logger("SettingsView")

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
                ATab("Zones", systemName: Icons.zone) {
                    ZoneSettingsView()
                }
                ATab("Bluetooth", resource: "Bluetooth") {
                    BluetoothSettingsView()
                }
            }
        }
        
    }
}

struct GeneralSettingsView: View {
    let logger = Log.Logger("GeneralSettingsView")

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
