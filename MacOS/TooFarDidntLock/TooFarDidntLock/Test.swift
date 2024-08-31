//import SwiftUI
//import Combine
//import Foundation
//import CoreLocation
//import CoreBluetooth
//
//// http://www.davidgyoungtech.com/2020/05/07/hacking-the-overflow-area
//// https://stackoverflow.com/questions/61345954/want-to-run-advertising-peripheral-in-background-mode-ios-swift
//// https://stackoverflow.com/questions/29418388/ble-advertising-of-uuid-from-background-ios-app
//
//struct BeaconInfo: Hashable {
//    var uuid: UUID
//    var major: UInt16
//    var minor: UInt16
//    var measuredPower: Int8
//}
//
//class BluetoothScanner: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
//    var centralManager: CBCentralManager!
//    @Published var seenDevices: Set<UUID> = []
//    @Published var beacons: [BeaconInfo] = []
//    @Published var peripheral: CBPeripheral?
//
//    override init() {
//        super.init()
//        centralManager = CBCentralManager(delegate: self, queue: nil)
//    }
//    
//    func startScanning() {
//        centralManager.scanForPeripherals(withServices: nil, options: nil)
//    }
//    
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        if central.state == .poweredOn {
//            startScanning()
//        } else {
//            print("Bluetooth is not available.")
//        }
//    }
//    
//    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        print(NSDate(), "Detected \(peripheral.identifier) '\(peripheral.name ?? "unidentified")' at \(RSSI)")
//        return
//        let mamufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey]
//
//        if let data = mamufacturerData as? NSData, let info = parseAdvertisementData(data) {
//            if let index = self.beacons.firstIndex(where: {$0.uuid == info.uuid}) {
//                print(NSDate(), "Updated \(peripheral.identifier) '\(peripheral.name ?? "unidentified")' at \(RSSI)", data.count)
//                self.beacons[index] = info
//            } else {
//                print(NSDate(), "Discovered \(peripheral.identifier) '\(peripheral.name ?? "unidentified")' at \(RSSI)", data.count)
//                self.beacons.append(info)
////                self.centralManager.connect(peripheral)
//                self.peripheral = peripheral
//                peripheral.delegate = self
//            }
//        } else if peripheral.identifier == self.peripheral?.identifier {
//            let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey]
//            let manufacture = advertisementData[CBAdvertisementDataManufacturerDataKey]
//            print(NSDate(), "? \(peripheral.identifier) '\(peripheral.name ?? "unidentified")' at \(RSSI)", overflow)
//        }
//    }
//
//    func parseAdvertisementData(_ data: NSData) -> BeaconInfo? {
//        if data.count < 25 {
//            return nil
//        }
//        
//        var companyIdentifier: UInt16 = 0
//        var major: UInt16 = 0
//        var minor: UInt16 = 0
//        var measuredPower: Int8 = 0
//        var dataType: Int8 = 0
//        var dataLength: Int8 = 0
//        var uuidBytes = [UInt8](repeating: 0, count: 16)
//        
//        (data as NSData).getBytes(&companyIdentifier, range: NSRange(location: 0, length: 2))
//        if companyIdentifier != 0x4C {
//            return nil
//        }
//        
//        (data as NSData).getBytes(&dataType, range: NSRange(location: 2, length: 1))
//        if dataType != 0x02 {
//            return nil
//        }
//        
//        (data as NSData).getBytes(&dataLength, range: NSRange(location: 3, length: 1))
//        if dataLength != 0x15 {
//            return nil
//        }
//        
//        (data as NSData).getBytes(&uuidBytes, range: NSRange(location: 4, length: 16))
//        let proximityUUID = UUID(uuid: (uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3], uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7], uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11], uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]))
//        
//        (data as NSData).getBytes(&major, range: NSRange(location: 20, length: 2))
//        major = (major >> 8) | (major << 8)
//        
//        (data as NSData).getBytes(&minor, range: NSRange(location: 22, length: 2))
//        minor = (minor >> 8) | (minor << 8)
//        
//        (data as NSData).getBytes(&measuredPower, range: NSRange(location: 24, length: 1))
//        
//        let beaconAdvertisementData = BeaconInfo(
//            uuid: proximityUUID,
//            major: major,
//            minor: minor,
//            measuredPower: measuredPower
//        )
//        
//        return beaconAdvertisementData
//    }
//    
//    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
//        print("peripheralDidUpdateName")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: (any Error)?) {
//        print("peripheral", "didOpen")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
//        print("peripheral", "didModifyServices")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
//        print("peripheral", "didDiscoverServices")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: (any Error)?) {
//        print("peripheral", "didReadRSSI")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
//        print("peripheral", "didUpdateValueFor")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
//        print("peripheral", "didUpdateValueFor")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
//        print("peripheral", "didDiscoverDescriptorsFor")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
//        print("peripheral", "didDiscoverCharacteristicsFor")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
//        print("peripheral", "didUpdateNotificationStateFor")
//    }
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: (any Error)?) {
//        print("peripheral", "didDiscoverIncludedServicesFor")
//    }
//}
//
//class BeaconManager: NSObject, ObservableObject, CLLocationManagerDelegate {
//    private var locationManager: CLLocationManager?
//    private var monitor: CLMonitor?
//    @Published var beacons: [CLBeacon] = []
//
//    override init() {
//        super.init()
//        locationManager = CLLocationManager()
//        locationManager?.delegate = self
//        print("isRangingAvailable", CLLocationManager.isRangingAvailable())
//        locationManager?.requestAlwaysAuthorization()
//    }
//
//    func startScanning() {
//        let uuid = UUID(uuidString: "DA8647B3-EF41-4A5F-9C32-CC63B46E5698")!
//        let beaconRegion = CLBeaconRegion(uuid: uuid, identifier: "pgim.mybeacon")
//        
//        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
////        locationManager?.startMonitoring(for: CLBeaconRegion())
////        locationManager?.requestWhenInUseAuthorization()
////        locationManager?.requestAlwaysAuthorization()
//        print("isMonitoringAvailable", CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self))
//        locationManager?.startMonitoring(for: beaconRegion)
////        locationManager?.startRangingBeacons(satisfying: constraint)
//        print("startScanning")
//        Task {
//            monitor = await CLMonitor("mon1")
//            await monitor?.add(CLMonitor.BeaconIdentityCondition(uuid: uuid), identifier: "bee")
//            for identifier in await monitor!.identifiers {
//                guard let lastEvent = await monitor!.record(for: identifier)?.lastEvent else { continue }
//                print("record", identifier, lastEvent.state)
//            }
//
//            for try await event in await monitor!.events {
//                print("event", event.identifier, event)
//                
//            }
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
//        print("didVisit", visit)
//    }
//    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
//        print("didStartMonitoringFor", region)
//    }
//    func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: any Error) {
//        print("didFailRangingFor", error)
//    }
//    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
//        print("monitoringDidFailFor", error.localizedDescription, (error as! CLError).errorDescription)
//    }
//    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
//        self.beacons = beacons
//        print("didRangeBeacons")
//    }
//    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
//        print("didEnterRegion")
//    }
//    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
//        print("didFailWithError", error)
//    }
//    
//}
//
//struct ContentViewX: View {
//    @ObservedObject var beaconManager = BeaconManager()
//    @ObservedObject var bluetoothScanner = BluetoothScanner()
//
//    var body: some View {
//        HStack {
//            List(beaconManager.beacons, id: \.self) { beacon in
//                VStack(alignment: .leading) {
//                    Text("UUID: \(beacon.uuid.uuidString)")
//                    Text("Major: \(beacon.major)")
//                    Text("Minor: \(beacon.minor)")
//                    Text("Proximity: \(proximityString(for: beacon.proximity))")
//                    Text("RSSI: \(beacon.rssi)")
//                }
//                .padding()
//            }
//            List(bluetoothScanner.beacons, id: \.self) { peripheral in
//                VStack(alignment: .leading) {
//                    Text("UUID: \(peripheral.uuid)")
//                    Text("Major: \(peripheral.major)")
//                    Text("Minor: \(peripheral.minor)")
////                    Text("State: \(peripheral.state.rawValue)")
//                }
//                .padding()
//            }
//        }
//        .frame(minWidth: 400, minHeight: 300)
//        .onAppear() {
//        }.task {
//            beaconManager.startScanning()
//        }
//    }
//
//    private func proximityString(for proximity: CLProximity) -> String {
//        switch proximity {
//        case .immediate: return "Immediate"
//        case .near: return "Near"
//        case .far: return "Far"
//        case .unknown: return "Unknown"
//        @unknown default: return "Unknown"
//        }
//    }
//}
//
//extension CLError: LocalizedError {
//    public var errorDescription: String? {
//        switch self.code {
//        case .locationUnknown:
//            return "Location is currently unknown."
//        case .denied:
//            return "Access to location services is denied."
//        case .network:
//            return "Network error."
//        case .headingFailure:
//            return "Heading could not be determined."
//        case .regionMonitoringDenied:
//            return "Region monitoring access is denied."
//        case .regionMonitoringFailure:
//            return "Region monitoring failed."
//        case .regionMonitoringSetupDelayed:
//            return "Region monitoring setup delayed."
//        case .regionMonitoringResponseDelayed:
//            return "Region monitoring response delayed."
//        case .geocodeFoundNoResult:
//            return "Geocode found no result."
//        case .geocodeFoundPartialResult:
//            return "Geocode found partial result."
//        case .geocodeCanceled:
//            return "Geocode request was canceled."
//        case .deferredFailed:
//            return "Deferred mode failed."
//        case .deferredNotUpdatingLocation:
//            return "Deferred mode not updating location."
//        case .deferredAccuracyTooLow:
//            return "Deferred mode accuracy is too low."
//        case .deferredDistanceFiltered:
//            return "Deferred mode distance filtered."
//        case .deferredCanceled:
//            return "Deferred mode request was canceled."
//        case .rangingUnavailable:
//            return "Ranging unavailable."
//        case .rangingFailure:
//            return "Ranging failed."
//        @unknown default:
//            return "Unknown Core Location error."
//        }
//    }
//}
