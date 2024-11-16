import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBPeripheralManagerDelegate {
    
    // UI components and setup ------------------------------------------------
    
    var wattageLabel: UILabel!
    var increaseButton: UIButton!
    var decreaseButton: UIButton!
    var toggleBroadcastButton: UIButton!
    var statusLabel: UILabel!
    
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
        toggleBroadcastButton.setTitleColor(.white, for: .normal) // Set text color to white
        toggleBroadcastButton.backgroundColor = .systemBlue       // Set background color to blue
        toggleBroadcastButton.layer.cornerRadius = 10            // Add rounded corners
        toggleBroadcastButton.clipsToBounds = true               // Ensure corners are clipped
        toggleBroadcastButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20) // Add padding
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
    
    // Update the status label and the broadcast toggle button label
    func updateDisplayedBroadcastState() {
        if isBroadcasting {
            toggleBroadcastButton.setTitle("Stop", for: .normal)
            statusLabel.text = "Broadcasting power data ..."
        } else {
            toggleBroadcastButton.setTitle("Start", for: .normal)
            statusLabel.text = "Press start to broadcast power data."
        }
    }
    
    // Wattage data management ------------------------------------------------
    
    // Wattage variable
    var wattage: Int = 0 {
        didSet {
            wattageLabel.text = "\(wattage) w"
        }
    }
    
    @objc func increaseWattage() {
        wattage += 5
    }
    
    @objc func decreaseWattage() {
        wattage = max(0, wattage - 5)
    }
    
    @objc func buildWattageDataForTransmission() -> Data {
        let flags: UInt16 = 0
        let powerValue = UInt16(wattage)
        let energy: UInt16 = 0
        
        var wattageData = Data()
        wattageData.append(contentsOf: [UInt8(flags & 0x00ff), UInt8((flags & 0xff00) >> 8)])
        wattageData.append(contentsOf: [UInt8(powerValue & 0x00ff), UInt8((powerValue & 0xff00) >> 8)])
        wattageData.append(contentsOf: [UInt8(energy & 0x00ff), UInt8((energy & 0xff00) >> 8)])
        
        return wattageData;
    }
    
    // Bluetooth logic --------------------------------------------------------
    
    // Bluetooth properties
    var peripheralManager: CBPeripheralManager!
    var cyclingPowerCharacteristic: CBMutableCharacteristic?
    
    var subscribedCentrals: [CBCentral] = []
    
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
        startBroadcastingTimer()
    }
    
    func broadcastPower() {
        guard let cyclingPowerCharacteristic = cyclingPowerCharacteristic else { return }
        
        var wattageData = buildWattageDataForTransmission()
        
        // Notify connected devices of the updated value
        let success = peripheralManager.updateValue(wattageData, for: cyclingPowerCharacteristic, onSubscribedCentrals: nil)
        
        // Debugging log
        if success {
            print("Successfully broadcasted wattage: \(wattage) w")
        } else {
            print("Failed to broadcast wattage")
        }
    }
    
    // Broadcasting toggle management -----------------------------------------
    
    var isBroadcasting = false {
        didSet {
            updateDisplayedBroadcastState()
        }
    }
    
    var timer: DispatchSourceTimer?
    
    func startBroadcastingTimer() {
        timer?.cancel()
        let queue = DispatchQueue.global(qos: .background)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: 2.0)
        timer?.setEventHandler { [weak self] in
            self?.broadcastPower()
        }
        timer?.resume()
    }
    
    func stopBroadcastingTimer() {
        timer?.cancel()
        timer = nil
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
        stopBroadcastingTimer()
        peripheralManager.stopAdvertising()
    }
    
    // Background task management ---------------------------------------------
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    func registerBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
        print("Background task registered")
    }

    func endBackgroundTask() {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        print("Background task ended")
    }
    
    // Handle opening and closing of app --------------------------------------
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Ensure advertising continues
        if (isBroadcasting) {
            if !peripheralManager.isAdvertising {
                let cyclingPowerServiceUUID = CBUUID(string: "1818")
                peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [cyclingPowerServiceUUID]])
            }
            // Ensure timer continues
            startBroadcastingTimer()
            
            
            registerBackgroundTask()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        endBackgroundTask()
    }
    
    // Initial application load -----------------------------------------------
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize Bluetooth peripheral manager
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        setupUI()
        updateDisplayedBroadcastState()
    }
}
