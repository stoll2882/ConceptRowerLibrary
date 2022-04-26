//
//  ConceptRowerManager.swift
//  Class for managing a Concept 2 rower via bluetooth. Leverages SDK specifications from here:
//  https://www.concept2.com/files/pdf/us/monitors/PM5_BluetoothSmartInterfaceDefinition.pdf
//
//  Created by Rod Toll on 11/28/20.
//

import Foundation
import CoreBluetooth

// Indicates current state of the rower manager
public enum RowerManagerState {
    case initialized // Manager has been created
    case startingUp  // Manager is being initialized. Between startup() being called and the process completed
    case idle        // Manager is initialized and not scanning.
    case scanning    // Manager is currently looking for devices
}

// Protocol for handling updates on Rower Manager state
public protocol CConceptRowerManagerDelegate {
    func conceptRowerManager(_ manager: CConceptRowerManager, didDiscover rower: CConceptRower );
    func conceptRowerManager(_ manager: CConceptRowerManager, oldState previousState: RowerManagerState, newState state: RowerManagerState );
}

// Class used to enumerate and connect to concept 2 rowers
public class CConceptRowerManager: NSObject {
    
    // Bluetooth manager object
    private var centralManager: CBCentralManager?;
    
    // Delegate which implements the protocol to receive status updates
    private var delegate: CConceptRowerManagerDelegate?;
    
    // Current state of the rower.
    private var state: RowerManagerState;
    
    // Map from unique device id to the concept rower objects
    // Ensures we don't add duplicates.
    private var deviceMap: [UUID : CConceptRower];
    
    // List of devices which have been discovered
    private var deviceList: [CConceptRower];
    
    // Constructs the rower manager
    init(delegate: CConceptRowerManagerDelegate?) {
        self.centralManager = nil;
        self.delegate = delegate;
        self.state = .initialized;
        self.deviceMap = [:]
        self.deviceList = []
    }
    
    // Helper function to initiate device connect. Need to be here as connect
    // is on the manager not on the device.
    internal func connect(_ rower: CConceptRower) {
        self.centralManager?.connect(rower.getCBPeripheral());
    }
    
    // Helper function to disconnect a device. Needs to be here as discconnect
    // is on the manager not on the device.
    internal func disconnect(_ rower: CConceptRower) {
        self.centralManager?.cancelPeripheralConnection(rower.getCBPeripheral());
    }
    
    // Returns the array of rowers that have been discovered
    func getRowers() -> [CConceptRower] {
        return self.deviceList;
    }
    
    // Starts up the manager making it ready to discover objects
    func startup() {
        if self.state != .initialized {
            self.logMessage("Rower manager is not able to be started up. State=\(self.state)")
            return;
        }
        self.transitionState(transitionTo: .startingUp);
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main);
    }
    
    // Starts scanning for rowing devices
    func startScan() {
        if self.state != .idle {
            self.logMessage("Rower manager is not scanning so request to stop scan ignored. State=\(self.state)")
            return
        }
        self.transitionState(transitionTo: .scanning)
        self.centralManager?.scanForPeripherals(withServices: [CConceptRower.rowerService])
    }
    
    // Stops scans for rowing devices
    func stopScan() {
        if self.state != .scanning {
            self.logMessage("Rower manager is not scanning so request to stop scan ignored. State=\(self.state)")
            return
        }
        self.centralManager?.stopScan();
        self.transitionState(transitionTo: .idle);
    }
    
    // Used to detect and log state changes and inform delegate about it
    private func transitionState(transitionTo newState: RowerManagerState) {
        let oldState = self.state
        if oldState != newState ) {
            self.state = newState;
            self.logMessage("State from \(oldState) -> \(newState)");
            self.delegate?.conceptRowerManager(self, oldState: oldState, newState: newState);
        }
    }
    
    // Logs a message for the class
    private func logMessage(_ message: String) {
        print("ROWERMANAGER: \(message)");
    }
}

// Extension implementing the CBCentralManager contract
extension CConceptRowerManager: CBCentralManagerDelegate {
    
    // Handles when manager state changes.
    // Will not transition to .idle until state enters powered on
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            self.logMessage("central.state is .unknown")
        case .resetting:
            self.logMessage("central.state is .resetting")
        case .unsupported:
            self.logMessage("central.state is .unsupported")
        case .unauthorized:
            self.logMessage("central.state is .unauthorized")
        case .poweredOff:
            self.logMessage("central.state is .poweredOff")
        case .poweredOn:
            self.logMessage("central.state is .poweredOn")
            self.transitionState(transitionTo: .idle);
        @unknown default:
            self.logMessage("unknown")
        }
    }
    
    // Handle connect result
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let deviceToNotify = self.deviceMap[peripheral.identifier] {
            self.logMessage("Got connect for device: \(peripheral.identifier)");
            deviceToNotify.handleConnectResult(wasSuccesful: true);
        } else {
            self.logMessage("Got connect success for an unrecognized device: \(peripheral.identifier)");
        }
    }
    
    // Handle update on disconnect of a peripheral
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let deviceToNotify = self.deviceMap[peripheral.identifier] {
            self.logMessage("Got disconnect success for device: \(peripheral.identifier)");
            deviceToNotify.handleConnectResult(wasSuccesful: (error != nil))
        } else {
            self.logMessage("Got disconnect success for an unrecognized device: \(peripheral.identifier)");
        }
    }
    
    // Handle discovery of a new rower object
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let _ = self.deviceMap[peripheral.identifier] {
            self.logMessage("Ignoring device already known");
        } else {
            let newRower = CConceptRower(self, peripheral, rssi: RSSI.int32Value );
            self.deviceList.append(newRower);
            self.deviceMap[newRower.id] = newRower;
            self.logMessage("Got new rower, id: \(newRower.id)");
            self.delegate?.conceptRowerManager(self, didDiscover: newRower);
        }
    }
}

