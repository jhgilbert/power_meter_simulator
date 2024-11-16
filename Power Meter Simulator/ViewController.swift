import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBPeripheralManagerDelegate {
    
    // UI components
    var wattageLabel: UILabel!
    var increaseButton: UIButton!
    var decreaseButton: UIButton!
    
    // Bluetooth properties
    var peripheralManager: CBPeripheralManager!
    var cyclingPowerCharacteristic: CBMutableCharacteristic?
    
    var subscribedCentrals: [CBCentral] = []
    
    // Timer for broadcasting power every 2 seconds
    var broadcastTimer: Timer?
    
    // Wattage variable
    var wattage: Int = 0 {
        didSet {
            wattageLabel.text = "\(wattage) w"
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize Bluetooth peripheral manager
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        setupUI()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        if peripheralManager.isAdvertising {
            print("App moved to background, continuing to advertise.")
        } else {
            print("Peripheral is not advertising. Consider restarting advertising.")
        }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        print("Peripheral Manager is ready to continue updating.")
    }
    
    func setupUI() {
        view.backgroundColor = .white
        
        // Wattage label
        wattageLabel = UILabel()
        wattageLabel.text = "\(wattage)  w"
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
        
        // Layout constraints
        NSLayoutConstraint.activate([
            wattageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wattageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            increaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 50),
            increaseButton.topAnchor.constraint(equalTo: wattageLabel.bottomAnchor, constant: 20),
            
            decreaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -50),
            decreaseButton.topAnchor.constraint(equalTo: wattageLabel.bottomAnchor, constant: 20)
        ])
    }
    
    @objc func increaseWattage() {
        wattage += 5
    }
    
    @objc func decreaseWattage() {
        wattage = max(0, wattage - 5)
    }
    
    // Bluetooth peripheral setup
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            setupBluetoothServices()
        } else {
            print("Bluetooth is not available")
        }
    }
    
    func setupBluetoothServices() {
        // Define the Cycling Power Service and Characteristic UUIDs
        let cyclingPowerServiceUUID = CBUUID(string: "1818")
        let cyclingPowerCharacteristicUUID = CBUUID(string: "2A63")
        
        // Create characteristic with properties and permissions
        cyclingPowerCharacteristic = CBMutableCharacteristic(
            type: cyclingPowerCharacteristicUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        
        // Create the Cycling Power Service
        let cyclingPowerService = CBMutableService(type: cyclingPowerServiceUUID, primary: true)
        cyclingPowerService.characteristics = [cyclingPowerCharacteristic!]
        
        // Add the service to the peripheral manager
        peripheralManager.add(cyclingPowerService)
        
        // Start advertising
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [cyclingPowerServiceUUID]])
        
        // Start broadcasting power every 2 seconds
        startBroadcastingPower()
    }
    
    func startBroadcastingPower() {
        // Invalidate any existing timer before creating a new one
        broadcastTimer?.invalidate()
        
        // Schedule the timer to call broadcastPower every 2 seconds
        broadcastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.broadcastPower()
        }
    }
    
    func broadcastPower() {
        // Ensure characteristic is not nil before attempting to update its value
        guard let cyclingPowerCharacteristic = cyclingPowerCharacteristic else {
            print("Cycling Power Characteristic is nil.")
            return
        }
        
        // Convert wattage to Data using `withUnsafeBytes` for reliability
        // let wattageData = withUnsafeBytes(of: UInt16(wattage).littleEndian) { Data($0) }
        
        // Set flags and energy to 0
        let flags: UInt16 = 0
        let energy: UInt16 = 0

        let powerValue = UInt16(wattage)

        // Convert to little-endian format
        let flagsData = flags.littleEndian
        let powerData = powerValue.littleEndian
        let energyData = energy.littleEndian

        // Create Data object
        var wattageData = Data()
        wattageData.append(contentsOf: [UInt8(flagsData & 0x00ff), UInt8((flagsData & 0xff00) >> 8)])
        wattageData.append(contentsOf: [UInt8(powerData & 0x00ff), UInt8((powerData & 0xff00) >> 8)])
        wattageData.append(contentsOf: [UInt8(energyData & 0x00ff), UInt8((energyData & 0xff00) >> 8)])
        
        /*
        print("Sending Wattage Data: \(wattageData)")

        // Log the bytes being sent
        for byte in wattageData {
            print(String(format: "%02x", byte))
        }
        
        for byte in wattageData {
            print(String(format: "%02x", byte))
        }
        */
        
        // Update characteristic value
        cyclingPowerCharacteristic.value = wattageData
        
        // Notify connected devices of the updated value
        let success = peripheralManager.updateValue(wattageData, for: cyclingPowerCharacteristic, onSubscribedCentrals: nil)
        
        // Debugging log
        if success {
            print("Successfully broadcasted wattage: \(wattage)w")
        } else {
            print("Failed to broadcast wattage")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("Central subscribed: \(central)")
        subscribedCentrals.append(central)
        listSubscribedCentrals()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("Central unsubscribed: \(central)")
        if let index = subscribedCentrals.firstIndex(of: central) {
            subscribedCentrals.remove(at: index)
        }
        listSubscribedCentrals()
    }

    func listSubscribedCentrals() {
        print("Subscribed centrals:")
        for central in subscribedCentrals {
            print(central)
        }
    }
}

