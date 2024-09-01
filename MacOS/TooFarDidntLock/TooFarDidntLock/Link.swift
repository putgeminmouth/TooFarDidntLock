import SwiftUI
import Combine
import OSLog

protocol LinkEvaluator: ObservableObject {
    var linkStateDidChange: any Subject<(data: BluetoothLinkModel, oldState: LinkState, newState: LinkState), Never> { get }
    func domainModelDidChange(_ old: [any Link], _ new: [any Link])
}

class BaseLinkEvaluator: LinkEvaluator {
    let domainModel: DomainModel
    let runtimeModel: RuntimeModel
    var cancellables: [AnyCancellable] = []
    init(domainModel: DomainModel, runtimeModel: RuntimeModel) {
        self.domainModel = domainModel
        self.runtimeModel = runtimeModel
    }
    
    var linkStateDidChange: any Subject<(data: BluetoothLinkModel, oldState: LinkState, newState: LinkState), Never> = PassthroughSubject<(data: BluetoothLinkModel, oldState: LinkState, newState: LinkState), Never>()
    
    func domainModelDidChange(_ old: [any Link], _ new: [any Link]) {}
}

class BluetoothLinkEvaluator: BaseLinkEvaluator {
    let logger = Log.Logger("BluetoothLinkEvaluator")

    let bluetoothScanner: BluetoothScanner
    let bluetoothMonitor: BluetoothMonitor
    let updateTimer = Timed().start(interval: 1)
    init(
        domainModel: DomainModel, runtimeModel: RuntimeModel,
        bluetoothScanner: BluetoothScanner,
        bluetoothMonitor: BluetoothMonitor
    ) {
        self.bluetoothScanner = bluetoothScanner
        self.bluetoothMonitor = bluetoothMonitor
        super.init(domainModel: domainModel, runtimeModel: runtimeModel)
        domainModel.$links.withPrevious()
            .sink(receiveValue: self.onLinkModelsChange)
            .store(in: &cancellables)
        bluetoothScanner.didUpdate
            .sink(receiveValue: self.onBluetoothScannerUpdate)
            .store(in: &cancellables)
        bluetoothScanner.didDisconnect
            .sink(receiveValue: self.onBluetoothDidDisconnect)
            .store(in: &cancellables)
        
        updateTimer
            .sink{_ in self.onUpdateLinkState()}
            .store(in: &cancellables)
    }
    
    func setLinked(_ id: UUID, _ linked: Bool) {
        let newStateValue = linked ? Links.State.linked : Links.State.unlinked
        guard let link = domainModel.links.first{$0.id == id},
              var linkState = runtimeModel.linkStates.first{$0.id == link.id},
                  linkState.state != newStateValue
        else { return }
        logger.info("Link \(id) status; linked=\(linked);")
        let oldState = linkState
        var newState = linkState
        newState.state = newStateValue
        
        runtimeModel.linkStates.updateOrAppend(newState, where: {$0.id == id})
        linkStateDidChange.send((data: link, oldState: oldState as LinkState, newState: newState as LinkState))
    }
    
    func onUpdateLinkState() {
        for link in domainModel.links {
            onUpdateLinkState(link)
        }
    }
    func onUpdateLinkState(_ link: BluetoothLinkModel) {
        guard let linkState = runtimeModel.linkStates.first(where:{$0.id == link.id}) as? BluetoothLinkState
        else { return }

        let now = Date.now
        let maxAgeSeconds: Double? = link.idleTimeout

        var age: Double?
        var distance: Double?
        let peripheral = runtimeModel.bluetoothStates.first{$0.id == link.deviceId && (maxAgeSeconds == nil || $0.lastSeenAt.distance(to: now) < maxAgeSeconds!)}
        if let peripheral = peripheral  {
            age = peripheral.lastSeenAt.distance(to: now)

            if let d = linkState.monitorData.data.distanceSmoothedSamples?.last {
                distance = d.second
            }
        }

        var linkActive = !(distance ?? 0 > link.maxDistance)

        if linkActive {
            setLinked(link.id, true)
        } else {
            setLinked(link.id, false)
        }

    }
    
    func onBluetoothScannerUpdate(_ update: MonitoredPeripheral) {
        // update well-known: we only do this for infrequently updated properties
        // that are important for display purposes, like name
        if let index = domainModel.wellKnownBluetoothDevices.firstIndex{$0.id == update.id } {
            let known = domainModel.wellKnownBluetoothDevices[index]
            // RSSI and such deliberately ignored
            if known.name != update.name ||
                known.txPower != update.txPower {
                domainModel.wellKnownBluetoothDevices[index] = update
            }
        }
        
        // the main sync from CoreBT to domain
        if let index = runtimeModel.bluetoothStates.firstIndex{$0.id == update.id } {
            runtimeModel.bluetoothStates[index] = update
        } else {
            runtimeModel.bluetoothStates.append(update)
        }
        
        for link in domainModel.links {
            let linkState = runtimeModel.linkStates.first{$0.id == link.id} as! BluetoothLinkState
            let monitor = linkState.monitorData
            if let smoothingFunc = monitor.data.smoothingFunc {
                smoothingFunc.processNoise = link.environmentalNoise
            }

            // remember/cache linked-to devices. this is mainly for display purposes since the scan can
            // take a while to pick up a device or it may not currently be available
            if domainModel.wellKnownBluetoothDevices.first{$0.id == link.deviceId} == nil,
            let known = runtimeModel.bluetoothStates.first{$0.id == link.deviceId} {
                domainModel.wellKnownBluetoothDevices.append(known)
            }

            // conversely, ensure any cached devices are in the runtime list if they were not picked up by the scanner
            if runtimeModel.bluetoothStates.first{$0.id == link.deviceId} == nil,
            let known = domainModel.wellKnownBluetoothDevices.first{$0.id == link.deviceId} {
                runtimeModel.bluetoothStates.append(known)
            }
        }
        
        runtimeModel.bluetoothStates.sort(by: { (lhs, rhs) in
            let lhsId = lhs.id
            let lhsName = lhs.name
            let rhsId = rhs.id
            let rhsName = rhs.name
            
//            if domainModel.links.contains{$0.deviceId == lhsId} {
//                return true
//            }
//            if domainModel.links.contains{$0.deviceId == rhsId} {
//                return false
//            }
            switch (lhsName, rhsName) {
            case (nil, nil):
                return lhsId < rhsId
            case (nil, _):
                return false
            case (_, nil):
                return true
            default:
                return lhsName! < rhsName!
            }
        })
    

        // TODO: delete this, but double check first
//        for link in domainModel.links {
//            if link.requireConnection {
//                if bluetoothScanner.connect(maintainConnectionTo: link.deviceId) != nil {
//                    setLinked(link.id, true)
//                } else {
//                    logger.info("onBluetoothScannerUpdate: device not found on bluetooth update")
//                    setLinked(link.id, false)
//                }
//            }
//        }
    }
    
    func onBluetoothDidDisconnect(_ uuid: UUID) {
        logger.info("Bluetooth disconnected")
        if domainModel.links.first?.requireConnection ?? false {
            setLinked(uuid, false)
        }
    }
    func onLinkModelsChange(_ old: [BluetoothLinkModel]?, _ new: [BluetoothLinkModel]) {
        let added = new.filter{n in !(old ?? []).contains{$0.id == n.id}}
        let removed = (old ?? []).filter{o in !new.contains{$0.id == o.id}}
        let changed = new.compactMap{ n in
            if let o = (old ?? []).first{$0.id == n.id} {
                return (old: o, new: n)
            } else {
                return nil
            }
        }
        
        // mutually exclusive lists so the order we process in shouldn't matter?
        assert(Set(added.map{$0.id}).isDisjoint(with: Set(removed.map{$0.id})))
        assert(Set(removed.map{$0.id}).isDisjoint(with: Set(changed.map{$0.new.id})))
        assert(Set(added.map{$0.id}).isDisjoint(with: Set(changed.map{$0.new.id})))
        
        for r in removed {
            logger.info("link removed: will disconnect \(r.deviceId)")
            bluetoothScanner.disconnect(uuid: r.deviceId)
            setLinked(r.id, false)
            assert(runtimeModel.linkStates.contains{$0.id == r.id})
            runtimeModel.linkStates.removeAll{$0.id==r.id}
        }
        for c in changed {
            assert(runtimeModel.linkStates.contains{$0.id == c.new.id})
            let linkState = runtimeModel.linkStates.first{$0.id == c.new.id} as! BluetoothLinkState
            let monitor = linkState.monitorData
            monitor.data.referenceRSSIAtOneMeter = c.new.referencePower
            if let smoothingFunc = monitor.data.smoothingFunc {
                smoothingFunc.processNoise = c.new.environmentalNoise
            }

            if c.old.requireConnection != c.new.requireConnection {
                logger.info("link.requireConnection changed \(c.new.requireConnection): will disconnect \(c.new.deviceId) and reconnect in a moment as needed")
                bluetoothScanner.disconnect(uuid: c.new.deviceId)
                setLinked(c.new.id, false)
            }
        }
        for a in added {
            assert(!runtimeModel.linkStates.contains{$0.id == a.id})
            let monitor = bluetoothMonitor.startMonitoring(a.deviceId, referenceRSSIAtOneMeter: a.referencePower)
            if let smoothingFunc = monitor.data.smoothingFunc {
                smoothingFunc.processNoise = a.environmentalNoise
            }

            let linkState = BluetoothLinkState(id: a.id, state: Links.State.unlinked, monitorData: monitor)
            runtimeModel.linkStates.append(linkState)

            if a.requireConnection {
                if bluetoothScanner.connect(maintainConnectionTo: a.deviceId) != nil {
                    setLinked(a.id, true)
                } else {
                    logger.warning("link added: device not found on new link: \(a.deviceId)")
                }
            } else {
                setLinked(a.id, true)
            }
            
            runtimeModel.linkStates.updateOrAppend({linkState}, where: {$0.id == linkState.id})
        }
    }
}

class WifiLinkEvaluator: BaseLinkEvaluator {
    let logger = Log.Logger("WifiLinkEvaluator")

    let wifiScanner: WifiScanner
    let wifiMonitor: WifiMonitor
    // TODO: don't do this blocking call on .main
    let updateTimer = Timed().start(interval: 1)
    init(
        domainModel: DomainModel, runtimeModel: RuntimeModel,
        wifiScanner: WifiScanner,
        wifiMonitor: WifiMonitor
    ) {
        self.wifiScanner = wifiScanner
        self.wifiMonitor = wifiMonitor
        super.init(domainModel: domainModel, runtimeModel: runtimeModel)
        wifiScanner.didUpdate
            .sink(receiveValue: self.onWifiScannerUpdates)
            .store(in: &cancellables)
    }
    
    func onWifiScannerUpdates(_ updates: [MonitoredWifiDevice]) {
        for update in updates {
            onWifiScannerUpdate(update)
        }
    }
    
    func onWifiScannerUpdate(_ update: MonitoredWifiDevice) {
        // update well-known: we only do this for infrequently updated properties
        // that are important for display purposes, like name
        if let index = domainModel.wellKnownWifiDevices.firstIndex{$0.bssid == update.bssid } {
            let known = domainModel.wellKnownWifiDevices[index]
            // RSSI and such deliberately ignored
            if known.ssid != update.ssid ||
                known.noiseMeasurement != update.noiseMeasurement {
                domainModel.wellKnownWifiDevices[index] = update
            }
        }
        
        // the main sync from CoreBT to domain
        if let index = runtimeModel.wifiStates.firstIndex{$0.bssid == update.bssid } {
            runtimeModel.wifiStates[index] = update
        } else {
            runtimeModel.wifiStates.append(update)
        }

        runtimeModel.wifiStates.sort(by: { (lhs, rhs) in
            let lhsId = lhs.bssid
            let lhsName = lhs.ssid.map{$0.lowercased()}
            let rhsId = rhs.bssid
            let rhsName = rhs.ssid.map{$0.lowercased()}
            
//            if domainModel.links.contains{$0.deviceId == lhsId} {
//                return true
//            }
//            if domainModel.links.contains{$0.deviceId == rhsId} {
//                return false
//            }
            switch (lhsName, rhsName) {
            case (nil, nil):
                return lhsId < rhsId
            case (nil, _):
                return false
            case (_, nil):
                return true
            default:
                return lhsName! < rhsName!
            }
        })
    }
}
