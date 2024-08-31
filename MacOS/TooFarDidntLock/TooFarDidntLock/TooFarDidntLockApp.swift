import SwiftUI
import OSLog
import Combine

@main
struct TooFarDidntLockApp: App {
    let logger = Logger(subsystem: "TooFarDidntLock", category: "App")

    @AppStorage("app.general.launchAtStartup") var launchAtStartup: Bool = false

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State var deviceLinkModel: DeviceLinkModel?
    let bluetoothScanner = BluetoothScanner(timeoutSeconds: 120, notifyMinIntervalMillis: 1000)
    @State var availableDevices = [BluetoothDeviceModel]()

    @State var linkedDeviceRSSIRawSamples = [Tuple2<Date, Double>]()
    @State var linkedDeviceRSSISmoothedSamples = [Tuple2<Date, Double>]()
    @State var linkedDeviceDistanceSamples = [Tuple2<Date, Double>]()
    var smoothingFunc = KalmanFilter(initialState: 0, initialCovariance: 0.01, processNoise: 0.1, measurementNoise: 5.01)

    @AppStorage("applicationStorage") var applicationStorage = ApplicationStorage()
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openSettings) var openSettings

    @AppStorage("app.locking.enabled") var lockingEnabled = true
    let deviceLinkRefreshTimer = Timed().start(interval: 1)
    let appStartTime = Date()

    @AppStorage("app.locking.safetyPeriodSeconds") var safetyPeriodSeconds: Int = 500
    let safetyPeriodTimer = Timed()
    @State var isSafetyActive: Bool = false
    @AppStorage("app.locking.cooldownPeriodSeconds") var cooldownPeriodSeconds: Int = 500
    let cooldownPeriodTimer = Timed()
    @State var isCooldownActive: Bool = false
    
    @State var menuIconFrame = 0
    
    @State var isScreenLocked = false

    
    var body: some Scene {
        // This window gets hidden, but we need a place to attach handlers
        Window("", id: "DummyWindowToProcessEvents") {
            EmptyView()
                .onReceive(cooldownPeriodTimer) { time in
                    stopCooldownPeriod();
                }
                .onReceive(safetyPeriodTimer) { time in
                    stopSafetyPeriod()
                }
                .onReceive(deviceLinkRefreshTimer) { _ in
                    // TODO
                    guard !isCooldownActive else { return }
                    guard !isSafetyActive else { return }
                    guard let link = deviceLinkModel else { return }
                    
                    let now = Date.now
                    let maxAgeSeconds: Double? = link.idleTimeout

                    var age: Double?
                    var distance: Double?
                    if let peripheral = bluetoothScanner.peripherals.first{$0.peripheral.identifier == link.uuid && (maxAgeSeconds == nil || $0.lastSeenAt.distance(to: now) < maxAgeSeconds!)} {
                        age = peripheral.lastSeenAt.distance(to: now)
                        
                        if let rssi = linkedDeviceRSSISmoothedSamples.last?.b {
                            distance = rssiDistance(referenceAtOneMeter: link.referencePower, current: rssi)
                        }
                    }
                    if let maxAgeSeconds = maxAgeSeconds {
                        switch age {
                        case .some(let x) where x < maxAgeSeconds/2.0:
                            appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Neutral")
                        case .some(let x) where x >= maxAgeSeconds/2.0:
                            appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Worry")
                        case .some(let x) where x > maxAgeSeconds:
                            appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Dizzy")
                        case .none:
                            appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Dizzy")
                        default:
                            break
                        }
                    }

                    var shouldLock = false
                    if distance ?? 0 > link.maxDistance {
                        shouldLock = true
                    }
                    
                    if shouldLock {
                        let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
                        let sym = dlsym(handle, "SACLockScreenImmediate")
                        let SACLockScreenImmediate = unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)

                        logger.info("would lock \(distance ?? -1) > \(link.maxDistance)")
                        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_XX")
                        if lockingEnabled {
                            let _ = SACLockScreenImmediate()
                        }
                    }
                    
                }
                .onChange(of: deviceLinkModel, initial: false) { (old, new) in
//                    guard old. != new else { return }
                    if let newValue = new {
                        applicationStorage.deviceLink = DeviceLinkStorage(
                            uuid: newValue.uuid.uuidString,
                            deviceDetails: BluetoothDeviceDetailsStorage(
                                uuid: newValue.deviceDetails.uuid.uuidString,
                                name: newValue.deviceDetails.name,
                                rssi: newValue.deviceDetails.rssi
                            ),
                            referencePower: newValue.referencePower,
                            maxDistance: newValue.maxDistance,
                            idleTimeout: newValue.idleTimeout
                        )
                        if old?.uuid != new?.uuid {
                            smoothingFunc.state = newValue.deviceDetails.rssi
                        }
                    } else {
                        applicationStorage.deviceLink = nil
                    }
                }
                .onChange(of: applicationStorage, initial: true) { (old, new) in
                    logger.debug("applicationStorage changed")
                    if let link = new.deviceLink,
                       let uuid = UUID(uuidString: link.uuid) {
                        deviceLinkModel = DeviceLinkModel(
                            uuid: uuid,
                            deviceDetails: BluetoothDeviceModel(
                                uuid: uuid,
                                name: link.deviceDetails.name,
                                rssi: link.deviceDetails.rssi,
                                lastSeenAt: Date.now),
                            referencePower: link.referencePower,
                            maxDistance: link.maxDistance,
                            idleTimeout: link.idleTimeout
                        )
                    }
                }
                .onReceive(bluetoothScanner) { peripherals in
                    onBluetoothScannerUpdate(peripherals)
                }
                .onReceive(appDelegate.statusBarDelegate.willShow) { _ in
                    appDelegate.statusBarDelegate.setItemVisible(tag: 1, visible: isSafetyActive)
                    appDelegate.statusBarDelegate.setItemVisible(tag: 2, visible: isCooldownActive)
                }
                .onReceive(appDelegate.statusBarDelegate.aboutAction) { _ in
                    appDelegate.aboutWindow.show()
                }
                .onReceive(appDelegate.statusBarDelegate.settingsAction) { _ in
                    openSettings()
                }
                .onReceive(appDelegate.statusBarDelegate.safetyPeriodAction) { _ in
                    stopSafetyPeriod()
                }
                .onReceive(appDelegate.statusBarDelegate.cooldownPeriodAction) { _ in
                    stopCooldownPeriod()
                }
                .onReceive(appDelegate.statusBarDelegate.lockingEnabledAction) { _ in
                    self.lockingEnabled = !self.lockingEnabled
                    appDelegate.statusBarDelegate.setItemState(tag: 3, state: self.lockingEnabled)
                }
                .onReceive(appDelegate.statusBarDelegate.quitAction) { _ in
                    NSApplication.shared.terminate(nil)
                }
                .onAppear() {
                    self.onApplicationDidFinishLaunching()
                }
        }
        Settings {
            SettingsView(deviceLinkModel: $deviceLinkModel, 
                         availableDevices: $availableDevices,
                         linkedDeviceRSSIRawSamples: $linkedDeviceRSSIRawSamples,
                         linkedDeviceRSSISmoothedSamples: $linkedDeviceRSSISmoothedSamples,
                         linkedDeviceDistanceSamples: $linkedDeviceDistanceSamples,
                         safetyPeriodSeconds: $safetyPeriodSeconds,
                         cooldownPeriodSeconds: $cooldownPeriodSeconds)
            .environmentObject(EnvVar<Bool>($launchAtStartup.wrappedValue))
//            .environmentObject(EnvVar<Bool>($requireDeviceFound.wrappedValue))
        }
    }
        
    func onApplicationDidFinishLaunching() {
        assert(Thread.isMainThread)
        logger.debug("onStart")

        let window = NSApp.windows.first(where: {$0.identifier?.rawValue == "DummyWindowToProcessEvents"})
        window?.orderOut(nil)

        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(forName: .init("com.apple.screenIsLocked"),
                        object: nil, queue: .main) { _ in
            self.isScreenLocked = true
        }

        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                        object: nil, queue: .main) { _ in
            self.isScreenLocked = false
            startCooldownPeriod()
        }

        appDelegate.statusBarDelegate.setItemState(tag: 3, state: self.lockingEnabled)
        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Neutral", tooltip: "")

        startSafetyPeriod()
    }

    func startSafetyPeriod() {
        guard !self.isSafetyActive else { return }
        logger.info("startSafetyPeriod")

        self.isSafetyActive = true

        safetyPeriodTimer.start(interval: safetyPeriodSeconds)

        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_zzz", tooltip: "")
    }
    
    func stopSafetyPeriod() {
        guard self.isSafetyActive else { return }
        logger.info("stopSafetyPeriod")

        self.isSafetyActive = false

        safetyPeriodTimer.stop()
        
        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Neutral", tooltip: "")
    }
    
    func startCooldownPeriod() {
        guard !self.isCooldownActive else { return }
        logger.info("startCooldownPeriod")

        self.isCooldownActive = true
        self.cooldownPeriodTimer.start(interval: cooldownPeriodSeconds)
        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_zzz", tooltip: "")
    }
    func stopCooldownPeriod() {
        guard self.isCooldownActive else { return }
        logger.info("stopCooldownPeriod")

        self.isCooldownActive = false
        self.cooldownPeriodTimer.stop()
    }
    
    func onBluetoothScannerUpdate(_ updates: [MonitoredPeripheral]) {
        for update in updates {
            if let index = availableDevices.firstIndex(where: {$0.uuid == update.peripheral.identifier }) {
                var device = availableDevices[index]
                device.name = update.peripheral.name
                device.rssi = update.lastSeenRSSI
                device.lastSeenAt = update.lastSeenAt
                availableDevices[index] = device
            } else {
                var device = BluetoothDeviceModel(
                    uuid: update.peripheral.identifier,
                    name: update.peripheral.name,
                    rssi: update.lastSeenRSSI,
                    txPower: update.txPower,
                    lastSeenAt: update.lastSeenAt)
                availableDevices.append(device)
            }
        }
        availableDevices.sort(by: { (lhs, rhs) in
                switch (lhs.name, rhs.name) {
                case (nil, nil):
                    return lhs.uuid < rhs.uuid
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                default:
                    return lhs.name! < rhs.name!
                }
            })

        if let linked = updates.first(where: {$0.peripheral.identifier == deviceLinkModel?.uuid}) {
            func tail(_ arr: [Tuple2<Date, Double>]) -> [Tuple2<Date, Double>] {
                return arr.filter{$0.a.distance(to: Date()) < 60}.suffix(1000)
            }
            
//            let linkedDeviceRSSISmoothedSample = (linkedDeviceRSSIRawSamples.lastNSeconds(seconds: 20).map{$0.b}.suffix(1000).average() + linked.lastSeenRSSI) / 2.0
            let linkedDeviceRSSISmoothedSample = smoothingFunc.update(measurement: linkedDeviceRSSIRawSamples.last?.b ?? 0)

            linkedDeviceRSSIRawSamples.append(Tuple2(linked.lastSeenAt, linked.lastSeenRSSI))
            linkedDeviceRSSIRawSamples = tail(linkedDeviceRSSIRawSamples)
            
            linkedDeviceRSSISmoothedSamples.append(Tuple2(linked.lastSeenAt, linkedDeviceRSSISmoothedSample))
            linkedDeviceRSSISmoothedSamples = tail(linkedDeviceRSSISmoothedSamples)
            
            linkedDeviceDistanceSamples.append(Tuple2(linked.lastSeenAt, rssiDistance(referenceAtOneMeter: deviceLinkModel!.referencePower, current: linkedDeviceRSSISmoothedSample)))
            linkedDeviceDistanceSamples = tail(linkedDeviceDistanceSamples)
        }
    }
}

// MenuBarExtra is all wonky and even with a hidden Window()
// change/receive are not always called.
class StatusBarDelegate: NSObject, NSMenuDelegate, ObservableObject {
    private let aboutWindow: AboutWindow

    private var aboutBoxWindowController: NSWindowController?
    private var statusBarItem: NSStatusItem!
    private var enabled: Bool = false
    
    let willShow = PassthroughSubject<Void, Never>()
    
    let aboutAction = PassthroughSubject<Void, Never>()
    let settingsAction = PassthroughSubject<Void, Never>()
    let safetyPeriodAction = PassthroughSubject<Void, Never>()
    let cooldownPeriodAction = PassthroughSubject<Void, Never>()
    let lockingEnabledAction = PassthroughSubject<Void, Never>()
    let quitAction = PassthroughSubject<Void, Never>()
    
    init(_ aboutWindow: AboutWindow) {
        assert(Thread.isMainThread)
        self.aboutWindow = aboutWindow
        
        super.init()

        self.createStatusBar()
        self.setupMenuItems()
    }

    func showAboutPanel() {
        aboutWindow.show()
    }
    
    func setMenuIcon(_ name: String, tooltip: String? = nil) {
        statusBarItem.button?.image = NSImage(named: name)
        if let tooltip = tooltip {
            statusBarItem.button?.toolTip = tooltip
        }
    }
    
    func setItemVisible(tag: Int, visible: Bool) {
        statusBarItem.menu?.item(withTag: tag)?.isHidden = !visible
    }

    func setItemState(tag: Int, state: Bool) {
        statusBarItem.menu?.item(withTag: tag)?.state = state ? .on : .off
    }

    private func createStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.menu = NSMenu()
        statusBarItem.menu!.delegate = self
        statusBarItem.button?.toolTip = "TF;DL"
        statusBarItem.button?.image = NSImage(named: "MenuIcon_Blank")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        willShow.send()
    }
    
    private func setupMenuItems() {
        let menu = statusBarItem.menu!
        menu.removeAllItems()

        let aboutItem = NSMenuItem(title: "About", action: #selector(notifyAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(notifySettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())
        
        let safetyPeriodItem = NSMenuItem(title: "Safety period active", action: #selector(notifySafetyPeriod), keyEquivalent: "")
        safetyPeriodItem.target = self
        safetyPeriodItem.state = .on
        safetyPeriodItem.tag = 1
        menu.addItem(safetyPeriodItem)

        let cooldownPeriodItem = NSMenuItem(title: "Cooldown period active", action: #selector(notifyCooldownPeriod), keyEquivalent: "")
        cooldownPeriodItem.target = self
        cooldownPeriodItem.state = .on
        cooldownPeriodItem.tag = 2
        menu.addItem(cooldownPeriodItem)

        let lockingEnabledItem = NSMenuItem(title: "Locking Enabled", action: #selector(notifyLockingEnabled), keyEquivalent: "")
        lockingEnabledItem.target = self
        lockingEnabledItem.state = .on
        lockingEnabledItem.tag = 3
        menu.addItem(lockingEnabledItem)

        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(notifyQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func notifyAbout() {
        aboutAction.send()
    }
    
    @objc private func notifySettings() {
        settingsAction.send()
    }
    
    @objc private func notifySafetyPeriod() {
        safetyPeriodAction.send()
    }
    
    @objc private func notifyCooldownPeriod() {
        cooldownPeriodAction.send()
    }
    
    @objc private func notifyLockingEnabled() {
        lockingEnabledAction.send()
    }
    
    @objc private func notifyQuit() {
        quitAction.send()
    }
    
}

class AboutWindow {
    let window: NSWindow
    let aboutBoxWindowController: NSWindowController

    init() {
        window = NSWindow()
        window.styleMask = [.closable, .miniaturizable,/* .resizable,*/ .titled]
        window.title = "About: Too Far; Didn't Lock"
        window.contentView = NSHostingView(rootView: AboutView())

        aboutBoxWindowController = NSWindowController(window: window)
    }

    func show() {
        aboutBoxWindowController.showWindow(aboutBoxWindowController.window)
        aboutBoxWindowController.window?.orderFrontRegardless()
        aboutBoxWindowController.window?.center()
    }
    

}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let statusBarDelegate: StatusBarDelegate
    let aboutWindow: AboutWindow

    override init() {
        self.aboutWindow = AboutWindow()
        self.statusBarDelegate = StatusBarDelegate(aboutWindow)

        super.init()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
