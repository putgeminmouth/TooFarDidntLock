import SwiftUI
import Combine
import OSLog

protocol LinkEvaluator: ObservableObject {
    var linkStateDidChange: any Subject<(data: DeviceLinkModel, oldState: LinkState, newState: LinkState), Never> { get }
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
    
    var linkStateDidChange: any Subject<(data: DeviceLinkModel, oldState: LinkState, newState: LinkState), Never> = PassthroughSubject<(data: DeviceLinkModel, oldState: LinkState, newState: LinkState), Never>()
    
    func domainModelDidChange(_ old: [any Link], _ new: [any Link]) {}
}

class BluetoothLinkEvaluator: BaseLinkEvaluator {
    let logger = Log.Logger("BluetoothLinkEvaluator")

    let bluetoothScanner: BluetoothScanner
    let updateTimer = Timed().start(interval: 1)
    init(domainModel: DomainModel, runtimeModel: RuntimeModel, bluetoothScanner: BluetoothScanner) {
        self.bluetoothScanner = bluetoothScanner
        super.init(domainModel: domainModel, runtimeModel: runtimeModel)
        domainModel.$links.withPrevious([])
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
    func onUpdateLinkState(_ link: DeviceLinkModel) {
        guard let linkState = runtimeModel.linkStates.first(where:{$0.id == link.id}) as? DeviceLinkState
        else { return }

        let now = Date.now
        let maxAgeSeconds: Double? = link.idleTimeout

        var age: Double?
        var distance: Double?
        let peripheral = runtimeModel.bluetoothStates.first{$0.id == link.deviceId && (maxAgeSeconds == nil || $0.lastSeenAt.distance(to: now) < maxAgeSeconds!)}
        if let peripheral = peripheral  {
            age = peripheral.lastSeenAt.distance(to: now)

            if let d = linkState.distanceSmoothedSamples.last {
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
        // update well-known: even really worth doing? seems unlikely to ever change, and we already capture it initially
        if let index = domainModel.wellKnownBluetoothDevices.firstIndex{$0.id == update.id } {
            let known = domainModel.wellKnownBluetoothDevices[index]
            // not critical but avoid spam-updating due to current signal etc
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
        
        for var link in domainModel.links {
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
    

        for link in domainModel.links {
            if nil == runtimeModel.linkStates.firstIndex{$0.id == link.id} { continue }
            var stateIndex = runtimeModel.linkStates.firstIndex{$0.id == link.id}!
            var state = runtimeModel.linkStates[stateIndex] as! DeviceLinkState
            func tail(_ arr: [Tuple2<Date, Double>]) -> [Tuple2<Date, Double>] {
                return arr.filter{$0.a.distance(to: Date()) < 60}.suffix(1000)
            }
            
            let rssiSmoothedSample = state.smoothingFunc.update(measurement: state.rssiRawSamples.last?.b ?? 0)
            
            state.rssiRawSamples = tail(state.rssiRawSamples + [Tuple2(update.lastSeenAt, update.lastSeenRSSI)])
            assert(state.rssiRawSamples.count < 2 || zip(state.rssiRawSamples, state.rssiRawSamples.dropFirst()).allSatisfy { current, next in current.a <= next.a }, "\( zip(state.rssiRawSamples, state.rssiRawSamples.dropFirst()).map{"\($0.0.a);\($0.1.a)"})")
            
            state.rssiSmoothedSamples = tail(state.rssiSmoothedSamples + [Tuple2(update.lastSeenAt, rssiSmoothedSample)])
            assert(state.rssiSmoothedSamples.count < 2 || zip(state.rssiSmoothedSamples, state.rssiSmoothedSamples.dropFirst()).allSatisfy { current, next in current.a <= next.a })
            
            state.distanceSmoothedSamples = tail(state.distanceSmoothedSamples + [Tuple2(update.lastSeenAt, rssiDistance(referenceAtOneMeter: link.referencePower, current: rssiSmoothedSample))])
            assert(state.distanceSmoothedSamples.count < 2 || zip(state.distanceSmoothedSamples, state.distanceSmoothedSamples.dropFirst()).allSatisfy { current, next in current.a <= next.a })
            
            if link.requireConnection {
                if bluetoothScanner.connect(maintainConnectionTo: link.deviceId) != nil {
                    setLinked(link.id, true)
                } else {
                    logger.info("onBluetoothScannerUpdate: device not found on connect()")
                    setLinked(link.id, false)
                }
            }

            runtimeModel.linkStates[stateIndex] = state
        }
    }
    
    func onBluetoothDidDisconnect(_ uuid: UUID) {
        logger.info("Bluetooth disconnected")
        if domainModel.links.first?.requireConnection ?? false {
            setLinked(uuid, false)
        }
    }
    func onLinkModelsChange(_ old: [DeviceLinkModel], _ new: [DeviceLinkModel]) {
        let added = new.filter{n in !old.contains{$0.id == n.id}}
        let removed = old.filter{o in !new.contains{$0.id == o.id}}
        let changed = new.flatMap{ n in
            if let o = old.first{$0.id == n.id} {
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
        }
        for c in changed {
            if c.old.requireConnection != c.new.requireConnection {
                logger.info("link.requireConnection changed (\(c.new.requireConnection): will disconnect \(c.new.deviceId) and reconnect in a moment as needed")
                bluetoothScanner.disconnect(uuid: c.new.deviceId)
                setLinked(c.new.id, false)
            }
        }
        for a in added {
            let linkState = runtimeModel.linkStates.first{$0.id==a.id}.flatMap{$0 as? DeviceLinkState} ?? DeviceLinkState(id: a.id, state: Links.State.unlinked)
            
            if a.requireConnection {
                if let deviceState = runtimeModel.bluetoothStates.first{$0.id==a.deviceId} {
                    // technically we only need to erase the smoothing history if its a different device
                    linkState.smoothingFunc.state = deviceState.lastSeenRSSI ?? 0

                    if bluetoothScanner.connect(maintainConnectionTo: a.deviceId) != nil {
                        setLinked(a.id, true)
                    } else {
                        logger.warning("link added: device not found on connect: \(a.deviceId)")
                    }
                    
                }
            } else {
                setLinked(a.id, true)
            }
            
            runtimeModel.linkStates.updateOrAppend({linkState}, where: {$0.id == linkState.id})
        }
    }
}
