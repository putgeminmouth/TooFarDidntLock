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
    
    @EnvironmentObject var advancedMode: EnvVar<Bool>

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
                ] + [
                .divider,
                .tab(label: "Wifi", icon: Icons.wifi.toImage()) {
                    WifiSettingsView()
                },
                .tab(label: "Bluetooth", icon: Icons.bluetooth.toImage()) {
                    BluetoothSettingsView()
                }
                ].filter{_ in !advancedMode}}
        }
        
    }
}

struct GeneralSettingsView: View {
    let logger = Log.Logger("GeneralSettingsView")
    
    @EnvironmentObject var advancedMode: EnvVar<Bool>

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
            Toggle("Advanced Mode", isOn: $advancedMode.value)
            
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
