import SwiftUI
import OSLog
import Combine
import CoreBluetooth
import ServiceManagement

@main
struct TooFarDidntLockApp: App {
    let logger = Log.Logger("App")

    @AppStorage("app.general.launchAtStartup") var launchAtStartup: Bool = false
    @AppStorage("app.general.showSettingsAtStartup") var showSettingsAtStartup: Bool = true
    @AppStorage("app.general.showInDock") var showInDock: Bool = true

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // TODO: debounce by group
    let bluetoothScanner: BluetoothScanner
    @State var bluetoothDebouncer: Debouncer<BluetoothDevice>
    var bluetoothMonitor: BluetoothMonitor
//    @Debounced(interval: 2.0) var domainModel = DomainModel(
    var domainModel: DomainModel
    var runtimeModel = RuntimeModel()
    
    let wifiScanner: WifiScanner
    let zoneEvaluator: ZoneEvaluator
    let bluetoothLinkEvaluator: BluetoothLinkEvaluator
    
    @AppStorage("applicationStorage") var applicationStorage = ApplicationStorage()

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openSettings) var openSettings

    @AppStorage("app.locking.enabled") var lockingEnabled = true
    let appStartTime = Date()

    @AppStorage("app.locking.safetyPeriodSeconds") var safetyPeriodSeconds: Int = 500
    let safetyPeriodTimer = Timed()
    @State var isSafetyActive: Bool = false
    @AppStorage("app.locking.cooldownPeriodSeconds") var cooldownPeriodSeconds: Int = 60
    let cooldownPeriodTimer = Timed()
    @State var isCooldownActive: Bool = false
    
    @State var menuIconFrame = 0
    
    @State var isScreenLocked = false
    
    init() {
        bluetoothScanner = BluetoothScanner(timeToLive: 120)
        bluetoothDebouncer = Debouncer(debounceInterval: 2)
        bluetoothMonitor = BluetoothMonitor(bluetoothScanner: bluetoothScanner)
        
        domainModel = DomainModel(
            version: 0,
            zones: [ManualZone(id: UUID(), name: "Default", active: true)],
            wellKnownBluetoothDevices: [],
            links: []
        )
        
        wifiScanner = try! WifiScanner()
        zoneEvaluator = ZoneEvaluator(
            manual: ManualZoneEvaluator(),
            wifi: WifiZoneEvaluator(wifi: wifiScanner))
        
        bluetoothLinkEvaluator = BluetoothLinkEvaluator(
            domainModel: domainModel,
            runtimeModel: runtimeModel,
            bluetoothScanner: bluetoothScanner,
            bluetoothMonitor: bluetoothMonitor
        )
    }
    
    var body: some Scene {
        // This window gets hidden, but we need a place to attach handlers
        Window("Too Far; Didn't Lock", id: "DummyWindowToProcessEvents") {
            EmptyView()
                .onReceive(cooldownPeriodTimer) { time in
                    stopCooldownPeriod();
                }
                .onReceive(safetyPeriodTimer) { time in
                    stopSafetyPeriod()
                }
                .onChange(of: lockingEnabled) {
                    // check again in case a link entered a lock state during the period
                    // since we may not get another signal. for now i avoid a "just in case" poll.
                    // TODO: is it really desirable to immediately lock when the user changes this?
                    maybeLock()
                }
                .onReceive(bluetoothLinkEvaluator.linkStateDidChange.eraseToAnyPublisher()) { _ in
                    maybeLock()
                }
                .onReceive(wifiScanner.didUpdate) { _ in
                    maybeLock()
                }
                .onReceive(domainModel.$version) { new in
                    logger.debug("onDomainChange(domain=(\(domainModel.version), \(new)); config=\(String(describing: applicationStorage.domainModel?.version))")
                    guard new > applicationStorage.domainModel?.version ?? 0
                    else {
                        logger.debug("onDomainChange.skip(domain=(\(domainModel.version), \(new)); config=\(String(describing: applicationStorage.domainModel?.version))")
                        return
                    }
//                    print("onChange(domain) \(old) -> \(new)")
                    applicationStorage.domainModel = domainModel
                    logger.debug("onDomainChange.updateStorage(domain=(\(domainModel.version), \(new)); config=\(String(describing: applicationStorage.domainModel?.version))")
                }
                .onChange(of: applicationStorage, initial: true) { (old, new) in
                    logger.debug("onStorageChange(domain=\(domainModel.version); config=(\(String(describing: old.domainModel?.version)), \(String(describing: new.domainModel?.version))))")
                    guard new.domainModel?.version ?? 0 > domainModel.version
                    else {
                        logger.debug("onStorageChange.skip(domain=\(domainModel.version); config=(\(String(describing: old.domainModel?.version)), \(String(describing: new.domainModel?.version))))")
                        return
                    }
                    logger.debug("onStorageChange.updateDomain(domain=\(domainModel.version); config=(\(String(describing: old.domainModel?.version)), \(String(describing: new.domainModel?.version))))")
                    domainModel.zones = new.domainModel!.zones
                    domainModel.wellKnownBluetoothDevices = new.domainModel!.wellKnownBluetoothDevices
                    domainModel.links = new.domainModel!.links
                    domainModel.setVersion(new.domainModel!.version)
                }
                .onChange(of: showInDock, initial: true) { (old, new) in
                    if (new) {
                        NSApp.setActivationPolicy(.regular)
                    } else {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
                .onChange(of: launchAtStartup) {
                    if (launchAtStartup) {
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About TooFar; Didn't Lock") {
                    appDelegate.statusBarDelegate.showAboutPanel()
                }
            }
        }
        Settings {
            SettingsView(
                         launchAtStartup: $launchAtStartup,
                         showSettingsAtStartup: $showSettingsAtStartup,
                         showInDock: $showInDock,
                         safetyPeriodSeconds: $safetyPeriodSeconds,
                         cooldownPeriodSeconds: $cooldownPeriodSeconds
            )
            .environmentObject(wifiScanner)
            .environmentObject(zoneEvaluator)
            .environmentObject(domainModel)
            .environmentObject(runtimeModel)
            .environmentObject(bluetoothMonitor)
        }
    }

    func maybeLock() {
        guard !isSafetyActive else { return }
        guard !isCooldownActive else { return }
        let activeZones = Set(domainModel.zones.filter{zoneEvaluator.isActive($0)}.map{$0.id})
        let activeZoneLinks = domainModel.links.filter {activeZones.contains($0.zoneId)}
        let activeLinkStates = activeZoneLinks.compactMap{a in runtimeModel.linkStates.first{$0.id == a.id}}
        let broken = activeLinkStates.filter{$0.state == .unlinked}
        guard broken.count > 0
        else {
            doUnLock()
            return
        }
        logger.info("Lock due to broken links: \(broken.map{$0.id})")
        doLock()
    }
    func doLock() {
        guard !isScreenLocked
        else { return }
        
        let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW)
        let sym = dlsym(handle, "SACLockScreenImmediate")
        let SACLockScreenImmediate = unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)

        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_XX")
        if lockingEnabled {
            let _ = SACLockScreenImmediate()
        }
    }
    func doUnLock() {
        guard isScreenLocked
        else { return }
        
        appDelegate.statusBarDelegate.setMenuIcon("MenuIcon_Neutral")
    }
        
    func onApplicationDidFinishLaunching() {
        assert(Thread.isMainThread)
        logger.debug("onStart")

        let window = NSApp.windows.first(where: {$0.identifier?.rawValue == "DummyWindowToProcessEvents"})
        // voodoo to make this window as non-existant as possible
        window?.ignoresMouseEvents = true
//        window?.styleMask = NSWindow.StyleMask.nonactivatingPanel // causes crashes sometimes? maybe it doesn't like main window being nonactivating
        window?.setContentSize(NSSize(width: 0, height: 0))
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
        
        if (showSettingsAtStartup) {
            openSettings()
        }
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
        
        // check again in case a link entered a lock state during the period
        // since we may not get another signal. for now i avoid a "just in case" poll.
        maybeLock()
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

        // check again in case a link entered a lock state during the period
        // since we may not get another signal. for now i avoid a "just in case" poll.
        maybeLock()
    }
}

// MenuBarExtra is all wonky and even with a hidden Window()
// change/receive are not always called.
class StatusBarDelegate: NSObject, NSMenuDelegate, ObservableObject {
    let logger = Log.Logger("StatusBarDelegate")

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
        logger.debug("setMenuIcon(\(name))")
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
    }
}
