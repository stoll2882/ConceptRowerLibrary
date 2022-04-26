//
//  ConceptRower.swift
//  Class for managing a Concept 2 rower via bluetooth. Leverages SDK specifications from here:
//  https://www.concept2.com/files/pdf/us/monitors/PM5_BluetoothSmartInterfaceDefinition.pdf
//
//  Created by Rod Toll on 11/29/20.
//
///

import Foundation
import CoreBluetooth

// Current state of the rower object
public enum ConceptRowerState {
    case initialized    // Rower is identified, but not yet connected
    case querying       // Rower is connected, but is querying for detailsl about the device
    case ready          // Rower is connected and ready to notify of changes as requested
}

// Type of machine the rower is.
// SDK equivalent -- OBJ_ERGMACHINETYPE_T
public enum MachineType: UInt32 {
    case staticD = 0
    case staticC = 1
    case staticA = 2
    case staticB = 3
    case staticE = 5
    case staticSimulation = 7
    case staticDynamic = 8
    case staticSlidesA = 16
    case staticSlidesB = 17
    case staticSlidesC = 18
    case staticSlidesD = 19
    case staticSlidesE = 20
    case staticSlidesDynamic = 32
    case staticDyno = 64
    case staticSki = 128
    case staticSkiSimulator = 143
    case bike = 192
    case bikeArms = 193
    case bikeNoArms = 194
    case bikeSimulator = 208
    case multiErgRow = 224
    case multiErgSki = 225
    case multiErgBike = 226
    
}

// Type of workout currently active on the machine
// API Equivalent: OBJ_WORKOUTTYPE_T
enum WorkoutType: UInt32 {
    case justRowNoSplits = 0
    case justRowSplits = 1
    case justRowFixedDistNoSplits = 2
    case justRowFixedDistSplits = 3
    case justRowFixedTimeNoSplits = 4
    case justRowFixedTimeSplits = 5
    case justRowFixedTimeInterval = 6
    case justRowFixedDistInterval = 7
    case variableInterval = 8
    case variableUndefinedRestInterval = 9
    case fixedCalorie = 10
    case fixedWattminutes = 11
    case fidexcalsInterval = 12
    case num = 13
}

// Type of interval active
// API Equivalent: OBJ_INTERVALTYPE_T
enum IntervalType: UInt32 {
    case time = 0
    case dist = 1
    case rest = 2
    case timeRestUndefined = 3
    case distanceRestUndefined = 4
    case restUndefined = 5
    case cal = 6
    case calRestUndefined = 7
    case wattMinute = 8
    case wattMinuteRestUndefined = 9
    case none = 255
}

// Workout state on the rower
// API Equivalent: OBJ_WORKOUTSTATE_T
enum WorkoutState: UInt32 {
    case waitToBegin = 0
    case workOutRow = 1
    case countDownPause = 2
    case intervalRest = 3
    case intervalWorkTime = 4
    case intervalWorkDistance = 5
    case intervalRestEndToWorkTime = 6
    case intervalRestEndToWorkDistance = 7
    case intervalWorkTimeToRest = 8
    case intervalWorkDistanceToRest = 9
    case workoutEnd = 10
    case terminate = 11
    case workoutLogged = 12
    case rearm = 13
}

// Rowing state on the rower
// API Equivalent: OBJ_ROWINGSTATE_T
enum RowingState: UInt32 {
    case inactive = 0
    case active = 1
}

// Stroke state on the rower
// API Equivalent: OBJ_STROKESTATE_T
enum StrokeState: UInt32 {
    case waitingForWheelToReachMinSpeedState = 0
    case waitingForWheelToAccelerateState = 1
    case drivingState = 2
    case dwellingAfterDriveState = 3
    case reocveryState = 4
}

// Workout Duration Type
// API Equivalent: DurationTypes
enum WorkoutDurationType: UInt32 {
    case timeDuration = 0
    case caloriesDuration = 0x40
    case distanceDuration = 0x80
    case wattsDuration = 0xC0
}

// Type of data to stream from the rower
enum RowerDataType {
    case rowingGeneralStatus
    case rowingAdditionalStatus
    case rowingEndGeneralStatus
}

// Represents characteristic CE060031-43E5-11E4-916C-0800200C9A66
public struct C2RowingGeneralStatus {
    var elapsedTime: Float
    var distance: Float
    var workoutType: WorkoutType
    var intervalType: IntervalType
    var workoutState: WorkoutState
    var rowingState: RowingState
    var strokeState: StrokeState
    var totalWorkDistance: Float
    var workoutDuration: Float
    var dragFactor: UInt8
}

// Represents data provided for characteristic CE060032-43E5-11E4-916C-0800200C9A66
public struct C2RowingAdditionalStatus {
    var elapsedTime: Float
    var speed: Float
    var strokeRate: UInt8
    var heartRate: UInt8
    var currentPace: Float
    var averagePace: Float
    var restDistance: UInt16
    var restTime: Float
}

// Represents data provided for characteristic CE060039-43E5-11E4-916C-0800200C9A66
public struct C2RowingEndGeneralStatus {
    var averageStrokeRate: Float
}

// Protocol for handling events out of the Rower objects
public protocol CConceptRowerDelegate {
    // State of the rower has changed
    func conceptRower(_ rower: CConceptRower, oldState previousState: ConceptRowerState, newState state: ConceptRowerState )
    
    // Rowing General Status update received
    func conceptRower(_ rower: CConceptRower, latestGeneralStatus: C2RowingGeneralStatus)
    
    // Rowing additional status update received
    func conceptRower(_ rower: CConceptRower, latestAdditionalStatus: C2RowingAdditionalStatus)
    
    // Rowing end status update received. Usually received when workout ends or is terminated
    func conceptRower(_ rower: CConceptRower, latestEndGeneralStatus: C2RowingEndGeneralStatus)
}

// Object representiing a single rower
public class CConceptRower: NSObject {
    
    // --------------------------------
    // Rower Bluetooth Services
    
    // Rower service. Used when searching for rowers in bluetooth devices
    static let rowerService = CBUUID(string: "CE060000-43E5-11E4-916C-0800200C9A66")
    
    // Rower main service
    static let rowerMainService = CBUUID(string: "CE060020-43E5-11E4-916C-0800200C9A66")
    
    // Rower control service
    static let rowerControlService = CBUUID(string: "CE060030-43E5-11E4-916C-0800200C9A66")
    
    // --------------------------------
    // Rower Characteristics - Readable
    
    static let characteristicModelNumber = CBUUID(string:"CE060011-43E5-11E4-916C-0800200C9A66")
    static let characteristicSerialNumber = CBUUID(string:"CE060012-43E5-11E4-916C-0800200C9A66")
    static let characteristicHardwareRevision = CBUUID(string:"CE060013-43E5-11E4-916C-0800200C9A66")
    static let characteristicFirmwareRevision = CBUUID(string:"CE060014-43E5-11E4-916C-0800200C9A66")
    static let characteristicManufacturer = CBUUID(string:"CE060015-43E5-11E4-916C-0800200C9A66")
    static let characteristicDeviceType = CBUUID(string:"CE060016-43E5-11E4-916C-0800200C9A66")
    
    
    // --------------------------------
    // Rower Characteristics - Notifiable
    
    
    static let characteristicRowingGeneralStatus = CBUUID(string:"CE060031-43E5-11E4-916C-0800200C9A66")
    static let characteristicRowingAdditionalStatus = CBUUID(string:"CE060032-43E5-11E4-916C-0800200C9A66")
    static let characteristicRowingEndGeneralStatus = CBUUID(string:"CE060039-43E5-11E4-916C-0800200C9A66")

    // List of properties that can be read
    static let characteristicReadProperties = [
        characteristicModelNumber,
        characteristicSerialNumber,
        characteristicHardwareRevision,
        characteristicFirmwareRevision,
        characteristicManufacturer,
        characteristicDeviceType
    ]
    
    // List of properties you can get notifications for
    static let characteristicNotifyProperties = [
        characteristicRowingGeneralStatus,
        characteristicRowingAdditionalStatus,
        characteristicRowingEndGeneralStatus
    ]
    
    // Unique identifier for the rower, corresponds to the UUID of the Bluetooth device
    var id: UUID
    
    // Name of the rower, if it has one
    var name: String?
    
    // RSSI level when the device is first discovered
    var originalRssi: Int32
    
    // Model number of the rower
    var modelNumber: String?
    
    // Serial number of the rower
    var serialNumber: String?
    
    // Hardware revision
    var hardwareRevision: String?
    
    // Firmware revision
    var firmwareRevision: String?
    
    // Manufacturer
    var manufacturer: String?
    
    // Device type -- Currently non-functional
    var deviceType: String?
    
    // Contains the underlying bluetooth object for this rower
    private var peripheral: CBPeripheral
    
    // Manager that created this rower
    private var manager: CConceptRowerManager
    
    // Current state of the rower, don't adjust without using setState()
    private var state: ConceptRowerState
    
    // Delegate to call with status changes to the rower
    var delegate: CConceptRowerDelegate?
    
    // Used to track if a particular property has had it's read results returned
    private var propertyTracker: [CBUUID: Bool]
    
    // Maps from characteristic CBUUID to the CBCharacteristic object
    private var characteristics: [CBUUID: CBCharacteristic]
    
    // Constructs a rower object tied to the specified manager, using the specified bluetooth object with the specified
    // original RSSI value
    internal init(_ manager: CConceptRowerManager, _ peripheral: CBPeripheral, rssi originalRssi: Int32) {
        self.id = peripheral.identifier
        self.name = peripheral.name
        self.originalRssi = originalRssi
        self.peripheral = peripheral
        self.manager = manager
        self.state = .initialized
        self.delegate = nil
        self.propertyTracker = [:]
        self.characteristics = [:]
    }
    
    // Initiates a connection to the rower represented by this object
    func connect(delegate: CConceptRowerDelegate?) {
        if self.state != .initialized {
            logMessage("Rower is not ready to connect. Current state=\(self.state) so connect attempt ignored.")
            return;
        }
        self.peripheral.delegate = self
        self.delegate = delegate
        self.propertyTracker = [:]
        self.characteristics = [:]
        self.manager.connect(self)
    }
    
    // Disconnects the bluetooth connection for this rower
    func disconnect() {
        if self.state != .ready {
            logMessage("Rower is not connected. Current state=\(self.state) so disconnect attempt ignored.")
            return
        }
        self.manager.disconnect(self)
    }
    
    // Activates callbacks with the specified characteristic
    func subscribeToData(dataType: RowerDataType) {
        if self.state != .ready {
            logMessage("Rower is not connected. Current state=\(self.state) so subscribe is ignored")
        }
        switch dataType {
        case .rowingGeneralStatus:
            self.peripheral.setNotifyValue(true, for: self.getCBCharacteristic(CConceptRower.characteristicRowingGeneralStatus)!)
        case .rowingAdditionalStatus:
            self.peripheral.setNotifyValue(true, for: self.getCBCharacteristic(CConceptRower.characteristicRowingAdditionalStatus)!)
        case .rowingEndGeneralStatus:
            self.peripheral.setNotifyValue(true, for: self.getCBCharacteristic(CConceptRower.characteristicRowingEndGeneralStatus)!)
        }
    }
    
    // Disables the callbacks with updates from the specified characteristic
    func unSubscribeToData(dataType: RowerDataType) {
        if self.state != .ready {
            logMessage("Rower is not connected. Current state=\(self.state) so unsubscribe is ignored")
        }
        switch dataType {
        case .rowingGeneralStatus:
            self.peripheral.setNotifyValue(false, for: self.getCBCharacteristic(CConceptRower.characteristicRowingGeneralStatus)!)
        case .rowingAdditionalStatus:
            self.peripheral.setNotifyValue(false, for: self.getCBCharacteristic(CConceptRower.characteristicRowingAdditionalStatus)!)
        case .rowingEndGeneralStatus:
            self.peripheral.setNotifyValue(false, for: self.getCBCharacteristic(CConceptRower.characteristicRowingEndGeneralStatus)!)
        }
    }
    
    // Gets current state of the rower
    func getState() -> ConceptRowerState {
        return self.state
    }
    
    // Accessor for the CBPeripheral object
    internal func getCBPeripheral() -> CBPeripheral {
        return self.peripheral
    }
    
    // Called by the manager when a connect result comes back and initiates service discovery
    internal func handleConnectResult(wasSuccesful result: Bool) {
        self.transitionState(transitionTo: .querying)
        peripheral.discoverServices(nil)
    }
    
    // Called by the manager when a disconnect is completed
    internal func handleDisconnectResult(wasSuccesful result: Bool) {
        self.transitionState(transitionTo: .initialized)
    }
    
    // Gets the CBCharacteristic object for the specified characteristic
    private func getCBCharacteristic(_ id: CBUUID) -> CBCharacteristic? {
        return self.characteristics[id]
    }
    
    // Handle state transition for the rower
    private func transitionState(transitionTo newState: ConceptRowerState) {
        let oldState = self.state
            if oldState != self.state {
            self.state = newState
            logMessage("State from \(oldState) -> \(newState)")
            self.delegate?.conceptRower(self, oldState: oldState, newState: newState)
        }
    }
    
    // Converts from the characteristic data value into a null terminated string
    private func characteristicToString(_ value: Data?) -> String {
        return String(decoding: value!, as: UTF8.self)
    }
    
    // Converts from the characteristic data value into a MachineType value
    private func characteristicToMachineType(_ value: Data?) -> MachineType {
        return MachineType(rawValue: UInt32(value!.first!))!
    }

    // Converts from a 3 byte value in characteristic data format into a UInt32
    private func get3ByteUInt(_ lower: UInt8, _ mid: UInt8, _ high: UInt8) -> UInt32 {
        let inputArray = [0, high, mid, lower]
        let data = Data(inputArray)
        return UInt32(bigEndian: data.withUnsafeBytes { $0.pointee })
    }
    
    // Converts from a 2 byte value in characteristic data format into a UInt16
    private func get2ByteUInt(_ lower: UInt8, _ high: UInt8) -> UInt16 {
        let inputArray = [high, lower]
        let data = Data(inputArray)
        return UInt16(bigEndian: data.withUnsafeBytes { $0.pointee })
    }
    
    // Converts from a 3 byte value in characteristic value into a Float representing elapsed time in seconds
    private func getElapsedTime(_ lower: UInt8, _ mid: UInt8, _ high: UInt8) -> Float {
        let rawTime = get3ByteUInt(lower, mid, high)
        return (Float(rawTime) * 0.01)
    }
    
    // Converts from a 3 byte value in characteristic value into a Float representing distance
    private func getDistance(_ lower: UInt8, _ mid: UInt8, _ high: UInt8) -> Float {
        let rawDistance = get3ByteUInt(lower, mid, high)
        return (Float(rawDistance) * 0.1)
    }
    
    // Converts from a 3 byte value in characteristic value into a Float representing speed
    private func getSpeed(_ lower: UInt8, _ high: UInt8) -> Float {
        let rawSpeed = get2ByteUInt(lower, high)
        return (Float(rawSpeed) * 0.001)
    }
    
    // Converts from a 3 byte value in characteristic value into a Float representing pace
    private func getPace(_ lower: UInt8, _ high: UInt8) -> Float {
        let rawPace = get2ByteUInt(lower, high)
        return (Float(rawPace) * 0.01)
    }
    
    // Converts from a characteristic value into a C2RowingGeneralStatus structure
    private func characteristicToRowingGeneralStatus(value: Data?) -> C2RowingGeneralStatus {
        let targetBuffer = [UInt8] (value!)

        let latestStatus: C2RowingGeneralStatus = C2RowingGeneralStatus(
            elapsedTime: getElapsedTime(targetBuffer[0], targetBuffer[1], targetBuffer[2]),
            distance: getDistance(targetBuffer[3], targetBuffer[4], targetBuffer[5]),
            workoutType: WorkoutType(rawValue: UInt32(targetBuffer[6]))!,
            intervalType: IntervalType(rawValue: UInt32(targetBuffer[7]))!,
            workoutState: WorkoutState(rawValue: UInt32(targetBuffer[8]))!,
            rowingState: RowingState(rawValue: UInt32(targetBuffer[9]))!,
            strokeState: StrokeState(rawValue: UInt32(targetBuffer[10]))!,
            totalWorkDistance: getDistance(targetBuffer[11], targetBuffer[12], targetBuffer[13]),
            workoutDuration: getElapsedTime(targetBuffer[14], targetBuffer[15], targetBuffer[16]),
            dragFactor: targetBuffer[18])
        return latestStatus
    }
    
    // Converts from a characteristic value into a C2RowingAdditionalStatus structure
    private func characteristicToRowingAdditionalStatus(value: Data?) -> C2RowingAdditionalStatus {
        let targetBuffer = [UInt8] (value!)
        
        let latestAdditionalStatus: C2RowingAdditionalStatus = C2RowingAdditionalStatus(
            elapsedTime: getElapsedTime(targetBuffer[0], targetBuffer[1], targetBuffer[2]),
            speed: getSpeed(targetBuffer[3], targetBuffer[4]),
            strokeRate: targetBuffer[5],
            heartRate: targetBuffer[6],
            currentPace: getPace(targetBuffer[7], targetBuffer[8]),
            averagePace: getPace(targetBuffer[9], targetBuffer[10]),
            restDistance: get2ByteUInt(targetBuffer[11], targetBuffer[12]),
            restTime: getElapsedTime(targetBuffer[13], targetBuffer[14], targetBuffer[15])
            //machineType: MachineType(rawValue: UInt32(targetBuffer[16]))!
        )
        
        return latestAdditionalStatus
 
    }
    
    // Converts from a characteristic value into a C2RowingEndGeneralStatus structure
    private func characteristicToRowingEndGeneralStatus(value: Data?) -> C2RowingEndGeneralStatus {
        let targetBuffer = [UInt8] (value!)

        let latestEndGeneralStatus: C2RowingEndGeneralStatus = C2RowingEndGeneralStatus(averageStrokeRate: Float(targetBuffer[10]))
        
        return latestEndGeneralStatus
    }
    
    // Prints out a log message prefixed by the rower id
    private func logMessage(_ message: String) {
        print("ROWER[\(self.id)]: \(message)")
    }
}

// Implements the CBPeripheralDelegate protocol for handling device updates
extension CConceptRower: CBPeripheralDelegate {
    
    // Handles incoming update for specified characteristic calling appropriate callbacks and updating internal state
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Keep track of which properties we have gotten updates for
        if self.propertyTracker[characteristic.uuid] == nil {
            self.propertyTracker[characteristic.uuid] = true
        }
        
        switch characteristic.uuid {
        case CConceptRower.characteristicModelNumber:
            self.modelNumber = characteristicToString(characteristic.value)
        case CConceptRower.characteristicSerialNumber:
            self.serialNumber = characteristicToString(characteristic.value)
        case CConceptRower.characteristicHardwareRevision:
            self.hardwareRevision = characteristicToString(characteristic.value)
        case CConceptRower.characteristicFirmwareRevision:
            self.firmwareRevision = characteristicToString(characteristic.value)
        case CConceptRower.characteristicManufacturer:
            self.manufacturer = characteristicToString(characteristic.value)
        case CConceptRower.characteristicDeviceType:
            self.deviceType = characteristicToString(characteristic.value)
        case CConceptRower.characteristicRowingGeneralStatus:
            self.delegate?.conceptRower(self, latestGeneralStatus: characteristicToRowingGeneralStatus(value: characteristic.value))
        case CConceptRower.characteristicRowingAdditionalStatus:
            self.delegate?.conceptRower(self, latestAdditionalStatus: characteristicToRowingAdditionalStatus(value: characteristic.value))
        case CConceptRower.characteristicRowingEndGeneralStatus:
            self.delegate?.conceptRower(self, latestEndGeneralStatus: characteristicToRowingEndGeneralStatus(value: characteristic.value))
        default:
            logMessage("Received update for unknown characteristic: \(characteristic.uuid)")
        }
        
        // If we have all our properties then we are good to go
        if self.propertyTracker.count == CConceptRower.characteristicReadProperties.count {
            self.transitionState(transitionTo: .ready)
        }
    }
    
    // Handles event when services for the device are discovered. INitiates discovering corresponding characteristics
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else{
            return
        }

        for service in services{
            peripheral.discoverCharacteristics(CConceptRower.characteristicReadProperties, for: service)
        }

        logMessage("Discovered Services: \(services)")
    }
    
    // Handles discovery of read characteristics
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else{
            return
        }

        logMessage("Found \(characteristics.count) characteristics for service: \(service.uuid)")

        for characteristic in characteristics {
            self.characteristics[characteristic.uuid] = characteristic
            for charToFind in CConceptRower.characteristicReadProperties {
                if charToFind == characteristic.uuid {
                    if(CConceptRower.characteristicReadProperties.contains(charToFind) ) {
                        peripheral.readValue(for: characteristic)
                    }
                }
            }
        }
    }
    

    
    
}
