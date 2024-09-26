import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers
import OSLog
import Charts

struct HVStack<Content: View>: View {
    enum Direction {
        case horizontal(VerticalAlignment)
        case vertical(HorizontalAlignment)
    }

    @State private var direction: Direction
    private let content: () -> Content
    
    init(_ direction: Direction, @ViewBuilder _ content: @escaping () -> Content) {
        self.direction = direction
        self.content = content
    }

    var body: some View {
        switch direction {
        case .horizontal(let alignment):
            HStack(alignment: alignment) {
                content()
            }
        case .vertical(let alignment):
            VStack(alignment: alignment) {
                content()
            }
        }
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

struct AnimatedImage: View {
    
    @State var timer: Timed
    @State var index: Int = 0
    @State var images: [Image]
    
    init(resources: [String], delay: TimeInterval) {
        images = resources.map{Image($0)}
        timer = Timed(interval: delay).start()
    }
    
    var body: some View {
        images[index]
            .onReceive(timer) { _ in
                index = (index + 1) % images.count
            }
    }
}

struct CalibrateView/*<Content: View>*/: View {
    enum Action {
        case `continue`
        case stop
    }
    typealias Content = AnyView
    let gaugeIcons = ["0", "33", "50", "67", "100"].map{"gauge.with.dots.needle.\($0)percent"}
    let spinnerIcons = ["left", "up", "right", "down"].map{"circle.grid.cross.\($0).filled"}
    @State var startAction: () -> Void
    @State var updateAction: ((startedAt: Date, elapsed: TimeInterval)) -> Action

    @State var timer = Timed(interval: 1)
    @State var startedAt: Date = Date.now
    @State var now: Date = Date.now
    @State var cancelable: AnyCancellable? = nil
    
    
    @State var isPresented = false
    @State var content: (Int) -> any View
    @State var duration: TimeInterval
    @State var page = 0

    init(
        onStart: @escaping () -> Void,
        onUpdate: @escaping ((startedAt: Date, elapsed: TimeInterval)) -> Action,
        duration: TimeInterval,
        isPresented: Bool = false,
        _ content: @escaping (Int) -> any View) {
            self.startAction = onStart
            self.updateAction = onUpdate
            self.content = content
            self._duration = State(wrappedValue: duration)
            
            self._isPresented = State(wrappedValue: isPresented)
        }

    var body: some View {
        VStack {
            Button {
                show()
            } label: {
                Image(systemName: "scope")
                    .font(.title)
                    .help("Calibrate")
            }
            .sheet(isPresented: $isPresented) {
                VStack {
                    VStack(alignment: .leading) {
                        HStack {
                            if page == 0 {
                                Text("Calibration")
                            } else {
                                let iconName = {
                                    let elapsed = startedAt.distance(to: now)
                                    let percent = min(elapsed/duration, 0.99999)
                                    let idx = percent * Double(gaugeIcons.count)
                                    return gaugeIcons[Int(idx) % gaugeIcons.count]
                                }()
                                ZStack {
                                    HStack {
                                        Text("Calibrating...")
                                        Spacer()
                                    }
                                    HStack {
                                        Image(systemName: iconName)
                                    }
                                }
                            }
                        }
                        .font(.system(size: 30))
                        .padding(5)
                        AnyView(content(page))
                        HStack {
                            Spacer()
                            if page == 0 {
                                Button("Start"){
                                    page = 1
                                    start()
                                }
                                Button("Cancel"){
                                    stop()
                                }
                            } else {
                                Button("Stop"){
                                    stop()
                                }
                            }
                        }
                    }.padding(.vertical, 25)
                    .padding(.horizontal, 10)
                }
            }
            .myButtonStyle()
        }
        .onReceive(timer) { _ in
            now = Date.now
            let elapsed = startedAt.distance(to: now)
            if updateAction((startedAt: startedAt, elapsed: elapsed)) == .stop {
                stop()
            }
        }
        .onAppear {
//            if autoStart {
//                self.show()
//            }
        }
    }
    
    func show() {
        page = 0
        isPresented = true
    }
    func start() {
        now = Date.now
        startedAt = now

        startAction()
        timer.restart()
    }
    func stop() {
        isPresented = false
        timer.stop()
        now = Date.distantPast
    }
}

struct LineChart: View {
    typealias Samples = [DataDesc: [DataSample]]
    
    @State var refreshViewTimer = Timed(interval: 1).start()
    @State var now: Date = Date()
    @Binding var samples: Samples
    @State var xRange: Int
    @Binding var yAxisMin: Double
    @Binding var yAxisMax: Double
    @Binding var ruleMarks: [Date]
    var body: some View {
        let xAxisMin = Calendar.current.date(byAdding: .second, value: -(xRange+1), to: now)!
        let xAxisMax = Calendar.current.date(byAdding: .second, value: 0, to: now)!

        let filteredSamples: [(key: DataDesc, value: [DataSample])] = samples
            // data can be sparse, e.g. because bluetooth scanner updates are unpredictable
            // so try and interpolate from out of bounds data when available, for a nicer graph
            .mapValues{
                var samples = $0
                
                let inBounds = samples.filter{$0.date >= xAxisMin}
                let outBounds = samples.filter{$0.date < xAxisMin}
                if let firstIn = inBounds.first,
                   let lastOut = outBounds.last {
                    let dx = lastOut.date.distance(to: firstIn.date)
                    let dy = firstIn.value - lastOut.value
                    let slope = dy/dx
                    let lerpX = lastOut.date.distance(to: xAxisMin)
                    let lerpY = lastOut.value + lerpX * slope
                    samples = [DataSample(xAxisMin, lerpY)] + samples
                }
                return samples
            }
            .mapValues{$0.filter{$0.date >= xAxisMin}}
            .sorted(by: {$0.key < $1.key})
        
        let filteredRuleMarks = ruleMarks
            .filter{$0 > xAxisMin}
        
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
                    
                    ForEach(filteredRuleMarks, id: \.self) { mark in
                        RuleMark(x: .value("t", mark))
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
        // we want to keep the graph moving even if no new data points have come in
        // this binds the view render to the timer updates (`now` is just a convenient state)
        .onReceive(refreshViewTimer) { _ in
            now = Date()
        }
    }
}

struct SignalMonitorView: View {
    enum ChartType: CaseIterable {
        case rssi
        case distance
    }

    @State var monitorData: any SignalMonitorData
    @State var availableChartTypes: Set<ChartType>
    @State var selectedChartTypes: Set<ChartType>
    
    @State private var chartSamples: LineChart.Samples = [:]
    @State private var chartYMin: Double = 0
    @State private var chartYMax: Double = 0
    @State private var chartYLastUpdated = Date()
    @Binding var ruleMarks: [Date]

    var body: some View {
        VStack(alignment: .leading) {
            if availableChartTypes.count > 1 {
                Menu("Select data series") {
                    Toggle("All", isOn: bindSetToggle($selectedChartTypes, availableChartTypes))
                        .toggleStyle(.button)
                    Divider()
                    if availableChartTypes.contains(.rssi) {
                        Toggle("Signal power (decibels)", isOn: bindSetToggle($selectedChartTypes, [.rssi]))
                            .toggleStyle(.checkbox)
                    }
                    if availableChartTypes.contains(.distance) {
                        Toggle("Calculated Distance (meters)", isOn: bindSetToggle($selectedChartTypes, [.distance]))
                            .toggleStyle(.checkbox)
                    }
                }
            }
            LineChart(
                samples: $chartSamples,
                xRange: 60,
                yAxisMin: $chartYMin,
                yAxisMax: $chartYMax,
                ruleMarks: $ruleMarks
            )
        }

        // is one better than the other?
//        .onReceive(monitorData.objectWillChange) { _ in
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
        if selectedChartTypes.contains(.rssi) {
            smoothInterpolateBounds(samples1)
            chartSamples[DataDesc("rssiRaw")] = samples1

            let samplesSmoothed = monitorData.rssiSmoothedSamples
            smoothInterpolateBounds(samplesSmoothed)
            chartSamples[DataDesc("rssiSmoothed")] = samplesSmoothed
        }
                
        if selectedChartTypes.contains(.distance),
           let samples3 = monitorData.distanceSmoothedSamples {
            smoothInterpolateBounds(samples3)
            chartYMin = max(0, chartYMin)
            chartSamples[DataDesc("distance")] = samples3
        }
    }
}
