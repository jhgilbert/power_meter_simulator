import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBPeripheralManagerDelegate {
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
    let debug = false
    
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
        statusLabel.text = "Press start to begin broadcasting."
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont.systemFont(ofSize: 21)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0 // Allow multiple lines
        view.addSubview(statusLabel)
        
        // Wattage label
        wattageLabel = UILabel()
        wattageLabel.text = "\(wattage)\u{202F}w"
        wattageLabel.textAlignment = .center
        wattageLabel.font = UIFont.systemFont(ofSize: 70)
        wattageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wattageLabel)
        
        // Increase button
        increaseButton = UIButton(type: .system)
        increaseButton.setTitle("+", for: .normal)
        increaseButton.titleLabel?.font = UIFont.systemFont(ofSize: 90)
        increaseButton.setTitleColor(.systemTeal, for: .normal) // Set text color to orange
        increaseButton.addTarget(self, action: #selector(increaseWattage), for: .touchUpInside)
        increaseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(increaseButton)
        
        // Decrease button
        decreaseButton = UIButton(type: .system)
        decreaseButton.setTitle("–", for: .normal)
        decreaseButton.titleLabel?.font = UIFont.systemFont(ofSize: 90)
        decreaseButton.setTitleColor(.systemTeal, for: .normal) // Set text color to orange
        decreaseButton.addTarget(self, action: #selector(decreaseWattage), for: .touchUpInside)
        decreaseButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(decreaseButton)
        
        // Toggle broadcast button
        toggleBroadcastButton = UIButton(type: .system)
        toggleBroadcastButton.setTitle("Start", for: .normal)
        toggleBroadcastButton.titleLabel?.font = UIFont.systemFont(ofSize: 50)
        toggleBroadcastButton.setTitleColor(.white, for: .normal) // Set text color to white
        toggleBroadcastButton.backgroundColor = .orange       // Set background color to orange
        toggleBroadcastButton.layer.cornerRadius = 10            // Add rounded corners
        toggleBroadcastButton.clipsToBounds = true               // Ensure corners are clipped
        toggleBroadcastButton.contentEdgeInsets = UIEdgeInsets(top: 15, left: 25, bottom: 15, right: 25) // Add padding
        toggleBroadcastButton.addTarget(self, action: #selector(toggleBroadcasting), for: .touchUpInside)
        toggleBroadcastButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toggleBroadcastButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 200),
            // statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            // statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            
            wattageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wattageLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 50),
            
            increaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 70),
            increaseButton.topAnchor.constraint(equalTo: wattageLabel.bottomAnchor, constant: 20),
            
            decreaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -70),
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
            statusLabel.text = "Press start to begin broadcasting."
        }
    }
    
    // Wattage data management ------------------------------------------------
    
    var wattage: Int = 0 {
        didSet {
            wattageLabel.text = "\(wattage)\u{202F}w"
        }
    }
    
    @objc func increaseWattage() {
        wattage += 5
    }
    
    @objc func decreaseWattage() {
        wattage = max(0, wattage - 5)
    }
    
    @objc func buildPowerDataForTransmission() -> Data {
        if (debug) {
            print("\nBuilding power data for transmission...")
        }
        
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
    
    let cyclingPowerServiceUUID = CBUUID(string: "1818")
    var cyclingPowerServiceAdded: Bool = false
    
    // Bluetooth properties
    var peripheralManager: CBPeripheralManager!
    var cyclingPowerCharacteristic: CBMutableCharacteristic?
    
    var subscribedCentrals: [CBCentral] = []
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            if (debug) {
                print("Bluetooth is ON.")
            }
            if (!cyclingPowerServiceAdded) {
                setupCyclingPowerService()
            }
        } else {
            if (debug) {
                print("Bluetooth is not available.")
            }
        }
    }
    
    // Create a cycling power service
    // and add it to the peripheralManager
    func setupCyclingPowerService() {
        if (debug) {
            print("\nSetting up cycling power service...")
        }
        
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
        cyclingPowerServiceAdded = true
    }
    
    // Calculate the current power data
    // and update its value for the cycling power service
    func sendPowerData() {
        guard let cyclingPowerCharacteristic = cyclingPowerCharacteristic else { return }
        
        let powerData = buildPowerDataForTransmission()
        
        // Notify connected devices of the updated value
        let success = peripheralManager.updateValue(powerData, for: cyclingPowerCharacteristic, onSubscribedCentrals: nil)
        
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
            if (isBroadcasting) {
                if (debug) {
                    print("\nisBroadcasting set to true, attempting to resume broadcasting...")
                }
                startBroadcastingTimer()
                peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [cyclingPowerServiceUUID]])
            } else {
                if (debug) {
                    print("\nisBroadcasting set to false, attempting to stop broadcasting...")
                }
                stopBroadcastingTimer()
                peripheralManager.stopAdvertising()
            }
        }
    }
    
    var timer: DispatchSourceTimer?
    
    // Send power data (if available) at an interval
    func startBroadcastingTimer() {
        if (debug) {
            print("\nStarting broadcasting timer ...")
        }
        
        timer?.cancel()
        let queue = DispatchQueue.global(qos: .background)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: 2.0)
        timer?.setEventHandler { [weak self] in
            self?.sendPowerData()
        }
        timer?.resume()
    }
    
    func stopBroadcastingTimer() {
        if (debug) {
            print("\nStopping broadcasting timer ...")
        }
        
        timer?.cancel()
        timer = nil
    }
    
    @objc func toggleBroadcasting() {
        isBroadcasting = !isBroadcasting
    }
    
    // Background task management ---------------------------------------------
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    func registerBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
        
        if (debug) {
            print("Background task registered")
        }
    }

    func endBackgroundTask() {
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        
        if (debug) {
            print("Background task ended")
        }
    }
    
    // Handle opening and closing of app --------------------------------------
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        if (debug) {
            print("applicationDidEnterBackground called.")
        }
        
        if isBroadcasting {
            if (debug) {
                print("Broadcasting is active; setting up background task.")
            }
            
            registerBackgroundTask()
            
            if !peripheralManager.isAdvertising {
                if (debug) {
                    print("Peripheral manager not advertising; restarting advertising.")
                }
                peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [cyclingPowerServiceUUID]])
            }
            
            startBroadcastingTimer()
        } else {
            if (debug) {
                print("Not broadcasting; no background task registered.")
            }
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        if (debug) {
            print("\nThe application will enter the foreground.")
        }
        
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
