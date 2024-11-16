import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBPeripheralManagerDelegate {
    
    // UI components
    var wattageLabel: UILabel!
    var increaseButton: UIButton!
    var decreaseButton: UIButton!
    var toggleBroadcastButton: UIButton!
    var statusLabel: UILabel!
    
    // Bluetooth properties
    var peripheralManager: CBPeripheralManager!
    var cyclingPowerCharacteristic: CBMutableCharacteristic?
    
    var subscribedCentrals: [CBCentral] = []
    
    // Timer for broadcasting power
    var timer: DispatchSourceTimer?
    
    // Background task for Bluetooth
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Wattage variable
    var wattage: Int = 0 {
        didSet {
            wattageLabel.text = "\(wattage) w"
        }
    }
    
    // Broadcasting state
    var isBroadcasting = false {
        didSet {
            updateBroadcastState()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize Bluetooth peripheral manager
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        setupUI()
        updateBroadcastState()
    }
    
    func setupUI() {
        view.backgroundColor = .white
        
        // Status label
        statusLabel = UILabel()
        statusLabel.text = "Press start to broadcast power data."
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 16)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        // Wattage label
        wattageLabel = UILabel()
        wattageLabel.text = "\(wattage) w"
        wattageLabel.textAlignment = .center
        wattageLabel.font = UIFont.systemFont(ofSize: 48)
        wattageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wattageLabel)
        
        // Increase button
        increaseButton = UIButton(type: .system)
        increaseButton.setTitle("+", for: .normal)
        increaseButton.titleLabel?.font = UIFont.systemFont(ofSize: 60)
        increaseButton.addTarget(self, action: #selector(increaseWattage), for: .touchUpInside)
        increaseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(increaseButton)
        
        // Decrease button
        decreaseButton = UIButton(type: .system)
        decreaseButton.setTitle("-", for: .normal)
        decreaseButton.titleLabel?.font = UIFont.systemFont(ofSize: 60)
        decreaseButton.addTarget(self, action: #selector(decreaseWattage), for: .touchUpInside)
        decreaseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(decreaseButton)
        
        // Toggle broadcast button
        toggleBroadcastButton = UIButton(type: .system)
        toggleBroadcastButton.setTitle("Start", for: .normal)
        toggleBroadcastButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        toggleBroadcastButton.addTarget(self, action: #selector(toggleBroadcasting), for: .touchUpInside)
        toggleBroadcastButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toggleBroadcastButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 100),
            
            wattageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wattageLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            
            increaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 50),
            increaseButton.topAnchor.constraint(equalTo: wattageLabel.bottomAnchor, constant: 20),
            
            decreaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -50),
            decreaseButton.topAnchor.constraint(equalTo: wattageLabel.bottomAnchor, constant: 20),
            
            toggleBroadcastButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toggleBroadcastButton.topAnchor.constraint(equalTo: increaseButton.bottomAnchor, constant: 40)
        ])
    }
    
    @objc func increaseWattage() {
        wattage += 5
    }
    
    @objc func decreaseWattage() {
        wattage = max(0, wattage - 5)
    }
    
    @objc func toggleBroadcasting() {
        if isBroadcasting {
            stopBroadcasting()
        } else {
            startBroadcasting()
        }
    }
    
    func startBroadcasting() {
        isBroadcasting = true
        setupBluetoothServices()
    }
    
    func stopBroadcasting() {
        isBroadcasting = false
        stopBroadcastingPower()
        peripheralManager.stopAdvertising()
    }
    
    func updateBroadcastState() {
        if isBroadcasting {
            toggleBroadcastButton.setTitle("Stop", for: .normal)
            statusLabel.text = "Broadcasting power data. Press stop to pause broadcasting."
        } else {
            toggleBroadcastButton.setTitle("Start", for: .normal)
            statusLabel.text = "Press start to broadcast power data."
        }
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("Bluetooth is ON.")
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    func setupBluetoothServices() {
        let cyclingPowerServiceUUID = CBUUID(string: "1818")
        let cyclingPowerCharacteristicUUID = CBUUID(string: "2A63")
        
        cyclingPowerCharacteristic = CBMutableCharacteristic(
            type: cyclingPowerCharacteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        
        let cyclingPowerService = CBMutableService(type: cyclingPowerServiceUUID, primary: true)
        cyclingPowerService.characteristics = [cyclingPowerCharacteristic!]
        
        peripheralManager.add(cyclingPowerService)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [cyclingPowerServiceUUID]])
        startBroadcastingPower()
    }
    
    func startBroadcastingPower() {
        timer?.cancel()
        let queue = DispatchQueue.global(qos: .background)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: 2.0)
        timer?.setEventHandler { [weak self] in
            self?.broadcastPower()
        }
        timer?.resume()
    }
    
    func stopBroadcastingPower() {
        timer?.cancel()
        timer = nil
    }
    
    func broadcastPower() {
        guard let cyclingPowerCharacteristic = cyclingPowerCharacteristic else { return }
        
        let flags: UInt16 = 0
        let powerValue = UInt16(wattage)
        let energy: UInt16 = 0
        
        var wattageData = Data()
        wattageData.append(contentsOf: [UInt8(flags & 0x00ff), UInt8((flags & 0xff00) >> 8)])
        wattageData.append(contentsOf: [UInt8(powerValue & 0x00ff), UInt8((powerValue & 0xff00) >> 8)])
        wattageData.append(contentsOf: [UInt8(energy & 0x00ff), UInt8((energy & 0xff00) >> 8)])
        
        // Notify connected devices of the updated value
        let success = peripheralManager.updateValue(wattageData, for: cyclingPowerCharacteristic, onSubscribedCentrals: nil)
        
        // Debugging log
        if success {
            print("Successfully broadcasted wattage: \(wattage) w")
        } else {
            print("Failed to broadcast wattage")
        }
    }
}
