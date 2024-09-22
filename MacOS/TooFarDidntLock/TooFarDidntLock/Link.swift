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
    static let logger = Log.Logger("BluetoothLinkEvaluator")
    let logger = BluetoothLinkEvaluator.logger
    
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
            .sink{_ in self.onLinkStateUpdateTimer()}
            .store(in: &cancellables)
    }
    
    private func setLinked(_ id: UUID, _ linked: Bool) {
        guard let link = domainModel.links.first{$0.id == id},
        let oldState = runtimeModel.linkStates.first(where: {$0.id == link.id}).map({$0 as! BluetoothLinkState})
        else { return }
        guard let newState = Self.updatedLinkWithState(id, linked, oldState)
        else { return }
        
        logger.info("Link \(id) status; linked=\(linked);")
        runtimeModel.linkStates.updateOrAppend(newState, where: {$0.id == id})
        linkStateDidChange.send((data: link, oldState: oldState as LinkState, newState: newState as LinkState))
    }
    
    static private func updatedLinkWithState(_ id: UUID, _ linked: Bool, _ oldState: BluetoothLinkState) -> BluetoothLinkState? {
        let newStateValue = linked ? Links.State.linked : Links.State.unlinked
        guard oldState.state != newStateValue
        else { return nil }
        
        var newState = oldState
        newState.state = newStateValue
        let now = Date.now
        newState.stateChangedHistory = (newState.stateChangedHistory + [now]).filter{$0.distance(to: .now) < 70}
        return newState
    }
    
    func onLinkStateUpdateTimer() {
        for link in domainModel.links {
            updateLinkStateFromSignalData(link)
        }
    }
    
    private func updateLinkStateFromSignalData(_ link: BluetoothLinkModel) {
        guard let linkState = runtimeModel.linkStates.first(where:{$0.id == link.id}) as? BluetoothLinkState
        else { return }

        let now = Date.now
        let maxAgeSeconds: Double? = link.idleTimeout
        let peripheral = runtimeModel.bluetoothStates.first{$0.id == link.deviceId && (maxAgeSeconds == nil || $0.lastSeenAt.distance(to: now) < maxAgeSeconds!)}

        guard let newState = Self.calculateLinkStateFromSignalData(link, linkState, peripheral)
        else { return }
        
//        logger.info("Link \(link.id) status; linked=\(newState.state);")
        runtimeModel.linkStates.updateOrAppend(newState, where: {$0.id == link.id})
        linkStateDidChange.send((data: link, oldState: linkState as LinkState, newState: newState as LinkState))
    }
    
    static func calculateLinkStateFromSignalData(_ link: BluetoothLinkModel, _ linkState: BluetoothLinkState, _ peripheral: MonitoredPeripheral?) -> BluetoothLinkState? {
        let now = Date.now
        
        var age: Double?
        var distance: Double?
        if let peripheral = peripheral  {
            age = peripheral.lastSeenAt.distance(to: now)
            
            if let d = linkState.monitorData.data.distanceSmoothedSamples?.last {
                distance = d.value
            }
        }
        
        var linkActive = !(distance ?? 0 > link.maxDistance)
        guard (linkState.stateChangedHistory.last?.distance(to: now)).map{$0 > link.linkStateDebounce} ?? true
        else { return nil }
        
        if linkActive {
            return Self.updatedLinkWithState(link.id, true, linkState)
        } else {
            return Self.updatedLinkWithState(link.id, false, linkState)
        }
        
    }
    
    func onBluetoothScannerUpdate(_ update: MonitoredPeripheral) {
        // update well-known: we only do this for infrequently updated properties
        // that are important for display purposes, like name
        if let index = domainModel.wellKnownBluetoothDevices.firstIndex{$0.id == update.id } {
            let known = domainModel.wellKnownBluetoothDevices[index]
            // RSSI and such deliberately ignored
            if known.name != update.name ||
                known.transmitPower != update.transmitPower {
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
        
        // TODO: do this on a timer, or by subscribing to the monitor isntead
        // we should stop assuming how the monitor gets its updates from the scanner's polling
        for idx in domainModel.links.filter{$0.autoMeasureVariance}.indices {
            if let linkState = runtimeModel.linkStates.first{$0.id == domainModel.links[idx].id} as? BluetoothLinkState {
                Self.autoTuneMeasureVariance(model: &domainModel.links[idx], data: linkState.monitorData.data)
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
                smoothingFunc.processVariance = c.new.processVariance
                smoothingFunc.measureVariance = c.new.measureVariance
            }
            
            if c.old.requireConnection != c.new.requireConnection {
                logger.info("link.requireConnection changed \(c.new.requireConnection): will disconnect \(c.new.deviceId) and reconnect in a moment as needed")
                bluetoothScanner.disconnect(uuid: c.new.deviceId)
                setLinked(c.new.id, false)
            }
        }
        for a in added {
            assert(!runtimeModel.linkStates.contains{$0.id == a.id})
            let monitor = bluetoothMonitor.startMonitoring(
                a.deviceId,
                smoothing: (referenceRSSIAtOneMeter: a.referencePower, processNoise: a.processVariance, measureNoise: a.measureVariance))
            
            let linkState = BluetoothLinkState(id: a.id, state: Links.State.unlinked, stateChangedHistory: [], monitorData: monitor)
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
    
    static func autoTuneMeasureVariance(model: inout BluetoothLinkModel, data: BluetoothMonitorData) {
        // some idea that using 30 sec lagged data lets us be reactive if things were
        // stable, but as soon as there is activity we get more conservative
        let backHalf = DataSample.tail(data.rssiRawSamples, 30)
        guard !backHalf.isEmpty else { return }
        

        var rawMax = backHalf.map{$0.value}.max()!
        var rawMin = backHalf.map{$0.value}.min()!

        var delta = abs(rawMax - rawMin) * 1.5

        model.measureVariance = delta

        data.smoothingFunc?.measureVariance = delta

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
