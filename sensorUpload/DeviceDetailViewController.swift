//
//  DeviceDetailViewController.swift
//  sensorUpload
//
//  Created by 이승윤 on 2021/09/20.
//

import UIKit
import StaticDataTableViewController
import MetaWear
import MetaWearCpp
import MessageUI
import BoltsSwift
import MBProgressHUD
import iOSDFULibrary
import Firebase

extension String {
    var drop0xPrefix: String {
        return hasPrefix("0x") ? String(dropFirst(2)) : self
    }
}

class DeviceDetailViewController: StaticDataTableViewController, UITextFieldDelegate {
    var devices: [MetaWear]!
    var bmi270: Bool = true
    
    @IBOutlet weak var connectionSwitch: UISwitch!
    @IBOutlet weak var connectionStateLabel: UILabel!
    
    @IBOutlet weak var recordTypeControl: UISegmentedControl!
    @IBOutlet weak var entryActionTypeControl: UISegmentedControl!
    
//    @IBOutlet var allCells: [UITableViewCell]!
    
    @IBOutlet var all: [UITableViewCell]!
    
    @IBOutlet weak var recordTrigger: UISwitch!
    
    @IBOutlet weak var accelerometerBMI160Cell: UITableViewCell!
    @IBOutlet weak var accelerometerBMI160Scale: UISegmentedControl!
    @IBOutlet weak var accelerometerBMI160Frequency: UISegmentedControl!
    
//    @IBOutlet weak var accelerometerBMI160Graph: APLGraphView!

    var accelerometerBMI160Data = [[String:Any]]()
    
    @IBOutlet weak var gyroBMI160Cell: UITableViewCell!
    @IBOutlet weak var gyroBMI160Scale: UISegmentedControl!
    @IBOutlet weak var gyroBMI160Frequency: UISegmentedControl!
//    @IBOutlet weak var gyroBMI160Graph: APLGraphView!
    var gyroBMI160Data = [[String:Any]]()
    
    @IBOutlet weak var sensorFusionCell: UITableViewCell!
    @IBOutlet weak var sensorFusionMode: UISegmentedControl!
    @IBOutlet weak var sensorFusionOutput: UISegmentedControl!
    
//    @IBOutlet weak var sensorFusionGraph: APLGraphView!
    
    @IBOutlet weak var activityText: UITextField!
    
    
    @IBOutlet weak var markAtBtnTimer:UIButton!
    
    
    var markerArr:[Int64] = []
    
    
    @IBAction func markAt(_ sender: Any) {
        let curr = Date().toMillis()!
        markerArr.append(curr)
    }
    
    func startTimer() {
        markerArr.removeAll()
        
    }
    
    var sensorFusionData = [[String:Any]]()
    
    var streamingEvents: Set<OpaquePointer> = []
    var streamingCleanup: [OpaquePointer: () -> Void] = [:]
    var loggers: [String: OpaquePointer] = [:]
    
    var disconnectTask: Task<MetaWear>?
    var isObservingOne = false {
        didSet {
            if self.isObservingOne {
                if !oldValue {
                    self.devices[0].peripheral.addObserver(self, forKeyPath: "state", options: .new, context: nil)
                    print("added OBserver1")
                }
            } else {
                if oldValue {
                    self.devices[0].peripheral.removeObserver(self, forKeyPath: "state")
                }
            }
        }
    }
    
    var isObservingTwo = false {
        didSet {
            if self.isObservingTwo {
                if !oldValue {
                    self.devices[1].peripheral.addObserver(self, forKeyPath: "state", options: .new, context: nil)
                    print("added OBserver2")
                }
            } else {
                if oldValue {
                    self.devices[1].peripheral.removeObserver(self, forKeyPath: "state")
                }
            }
        }
    }
    
    var hud: MBProgressHUD!
    
    var controller: UIDocumentInteractionController!
    var initiator: DFUServiceInitiator?
    var dfuController: DFUServiceController?
        
    var actionType: Int = 0
    
    let deviceDir_r = "r"
    let deviceI_r = 1
    let deviceDir_l = "l"
    let deviceI_l = 0
    
    var flashingLeft = false
    var flashingRight = false
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Use this array to keep track of all streaming events, so turn them off
        // in case the user isn't so responsible
        streamingEvents = []
        cell(sensorFusionCell, setHidden: false)
        cell(gyroBMI160Cell, setHidden: true)
        cell(accelerometerBMI160Cell, setHidden: true)
        reloadData(animated: false)
        // Write in the 2 fields we know at time zero
        connectionStateLabel.text! = nameForState()
        // Listen for state changes
        isObservingOne = true
        isObservingTwo = true

        // Start off the connection flow
        connectDevice(true)
        
        activityText.delegate = self
    }
    
    override func showHeader(forSection section: Int, vissibleRows: Int) -> Bool {
        return vissibleRows != 0
    }
    
    override func showFooter(forSection section: Int, vissibleRows: Int) -> Bool {
        return vissibleRows != 0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupHideKeyboardOnTap()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isObservingOne = false
        isObservingTwo = false
        streamingCleanup.forEach { $0.value() }
        streamingCleanup.removeAll()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        OperationQueue.main.addOperation {
            print("changed")
            self.connectionStateLabel.text! = self.nameForState()
            if self.devices[0].peripheral.state == .disconnected {
                self.deviceDisconnected()
            }
            if self.devices[1].peripheral.state == .disconnected {
                self.deviceDisconnected()
            }
        }
    }
    
    func nameForState() -> String {
        var count = 0
        for device in self.devices {
            switch device.peripheral.state {
                case .connected:
                    count += 1
                default:
                    count += 0
            }
        }
        return "\(count)/\(self.devices.count)"
    }
    
    func logCleanup(_ handler: @escaping (Error?) -> Void) {
        // In order for the device to actaully erase the flash memory we can't be in a connection
        // so temporally disconnect to allow flash to erase.
        isObservingOne = false
        isObservingTwo = false
        devices[0].connectAndSetup().continueOnSuccessWithTask { t -> Task<MetaWear> in
            self.devices[0].cancelConnection()
            return t
        }.continueOnSuccessWithTask { t -> Task<Task<MetaWear>> in
            return self.devices[0].connectAndSetup()
        }.continueWith { t in
            self.isObservingOne = true
            handler(t.error)
        }
        devices[1].connectAndSetup().continueOnSuccessWithTask { t -> Task<MetaWear> in
            self.devices[1].cancelConnection()
            return t
        }.continueOnSuccessWithTask { t -> Task<Task<MetaWear>> in
            return self.devices[1].connectAndSetup()
        }.continueWith { t in
            self.isObservingTwo = true
            handler(t.error)
        }
    }
    
    func showAlertTitle(_ title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Okay", style: .default, handler: nil))
        self.present(alertController, animated: true, completion: nil)
    }
    
    func deviceDisconnected() {
        connectionSwitch.setOn(false, animated: true)
        cells(self.all, setHidden: true)
        reloadData(animated: true)
    }
    
    func deviceConnectedReadAnonymousLoggers(device: MetaWear) {
    
    let task = device.createAnonymousDatasignals()
        task.continueWith(.mainThread) { t in
            //print(self.loggers)
            if let signals = t.result {
                for signal in signals {
                    let cString = mbl_mw_anonymous_datasignal_get_identifier(signal)!
                    let identifier = String(cString: cString)
                    self.loggers[identifier] = signal
                }
            }
            self.deviceConnected(device: device)
        }
    }
    
    func deviceConnected(device: MetaWear) {
        connectionSwitch.setOn(true, animated: true)
        // Perform all device specific setup
        print("ID: \(device.peripheral.identifier.uuidString) MAC: \(device.mac ?? "N/A")")
        // We always have the info and state features
        
        // Automaticaly send off some reads
        mbl_mw_settings_get_battery_state_data_signal(device.board).read().continueOnSuccessWith(.mainThread) {
            let battery: MblMwBatteryState = $0.valueAs()
            print(String(battery.charge))
        }
        
        reloadData(animated: true)
    }
    
    func connectDevice(_ on: Bool) {
        for device in devices
        {
            print("INDEX: \(devices.firstIndex(of: device))")
            if on {
            let hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
            hud.label.text = "Connecting..."
            device.connectAndSetup().continueWith(.mainThread) { t in

                hud.mode = .text
                if t.error != nil {
                    self.showAlertTitle("Error", message: t.error!.localizedDescription)
                    hud.hide(animated: false)
                } else {
                    self.deviceConnectedReadAnonymousLoggers(device: device)
                    hud.label.text! = "Connected!"
                    hud.hide(animated: true, afterDelay: 0.5)
                }
            }
        } else {
            device.cancelConnection()
        }}
    }
    
    @IBAction func connectionSwitchPressed(_ sender: Any) {
        connectDevice(connectionSwitch.isOn)
    }
    
    @IBAction func leftPressed(_ sender: Any) {
        
        flashLeft()
    }
    
    @IBAction func rightPressed(_ sender: Any) {
       flashRight()
    }
    
    func flashLeft() {
        if flashingLeft {
            devices[0].turnOffLed()
        } else {
            devices[0].flashLED(color: MBLColor.blue, intensity: 1.0)
        }
        
        flashingLeft = !flashingLeft
        
    }
    
    func flashRight() {
        if flashingRight {
            devices[1].turnOffLed()
        } else {
            devices[1].flashLED(color: MBLColor.red, intensity: 1.0)
        }
        flashingRight = !flashingRight
    }
    @IBAction func recordChanged(_ sender: UISwitch) {
        if sender.isOn {
            
            let txpower = Int8(0)
            for device in devices {
                mbl_mw_settings_set_tx_power(device.board, txpower)
            }
        
            
            if recordTypeControl.selectedSegmentIndex == 0 {
                startTimer()
                resetSensorFusionPressed()
                updateSensorFusionSettings()
                sensorFusionStartLogPressed()
                sensorFusionStartStreamPressed()
            } else {
                updateGyroBMI160Settings()
                updateAccelerometerBMI160Settings()
                gyroBMI160StartLogPressed()
                accelerometerBMI160StartLogPressed()
                accelerometerBMI160StartStreamPressed()
                gyroBMI160StartStreamPressed()
            }
        } else {
            if recordTypeControl.selectedSegmentIndex == 0 {
                sensorFusionStopLogPressed()
                sensorFusionStopStreamPressed()
                sensorFusionSendDataPressed()
            } else {
                gyroBMI160StopLogPressed()
                accelerometerBMI160StopLogPressed()
                gyroBMI160StopStreamPressed()
                accelerometerBMI160StopStreamPressed()
                gyroBMI160SendDataPressed()
                accelerometerBMI16SendDataPressed()
                
            }
        }
    }
    
    @IBAction func RecordModeChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            cell(sensorFusionCell, setHidden: false)
            cell(gyroBMI160Cell, setHidden: true)
            cell(accelerometerBMI160Cell, setHidden: true)
            self.tableView.reloadData()
        } else {
            cell(sensorFusionCell, setHidden: true)
            cell(gyroBMI160Cell, setHidden: false)
            cell(accelerometerBMI160Cell, setHidden: false)
            self.tableView.reloadData()
        }
    }
    
    @IBAction func recordActionTypeChanged(_ sender: UISegmentedControl) {
        actionType = sender.selectedSegmentIndex
    }

    func send(_ data: [[String:Any]], title: String) {
        // Get current Time/Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM_dd_yyyy-HH_mm_ss"
        let dateString = dateFormatter.string(from: Date())
        let name = ":t:\(title)_\(dateString):a:\(actionType):v:\(recordTypeControl.selectedSegmentIndex):actionrep:\(activityText.text ?? "NONE PROVIDED")"
        
        Database.database().reference().child(name).setValue(data)
        Database.database().reference().child(name + "_marker").setValue(markerArr)
        
        markerArr.removeAll()
    }
    

    func updateAccelerometerBMI160Settings() {
        for device in devices {
            switch self.accelerometerBMI160Scale.selectedSegmentIndex {
            case 0:
                mbl_mw_acc_bosch_set_range(device.board, MBL_MW_ACC_BOSCH_RANGE_2G)
            case 1:
                mbl_mw_acc_bosch_set_range(device.board, MBL_MW_ACC_BOSCH_RANGE_4G)
            case 2:
                mbl_mw_acc_bosch_set_range(device.board, MBL_MW_ACC_BOSCH_RANGE_8G)
            case 3:
                mbl_mw_acc_bosch_set_range(device.board, MBL_MW_ACC_BOSCH_RANGE_16G)
            default:
                fatalError("Unexpected accelerometerBMI160Scale value")
            }
        
            mbl_mw_acc_set_odr(device.board, Float(accelerometerBMI160Frequency.titleForSegment(at: accelerometerBMI160Frequency.selectedSegmentIndex)!)!)
            mbl_mw_acc_bosch_write_acceleration_config(device.board)
        }
    }

    func accelerometerBMI160StartStreamPressed() {
        
        updateAccelerometerBMI160Settings()
        accelerometerBMI160Data.removeAll()
        var device = devices[0]
        var signal = mbl_mw_acc_bosch_get_acceleration_data_signal(device.board)!
        mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
            let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)
//            DispatchQueue.main.async {
//                _self.accelerometerBMI160Graph.addX(Double(acceleration.x), y: Double(acceleration.y), z: Double(acceleration.z))
//            }
            let dat = [
                "epoch": obj!.pointee.epoch,
                "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                "dir": _self.deviceDir_l
            ] as [String:Any]
            _self.accelerometerBMI160Data.append(dat)
        }
        mbl_mw_acc_enable_acceleration_sampling(device.board)
        mbl_mw_acc_start(device.board)
        
        streamingCleanup[signal] = {
            mbl_mw_acc_stop(device.board)
            mbl_mw_acc_disable_acceleration_sampling(device.board)
            mbl_mw_datasignal_unsubscribe(signal)
        }
        device = devices[1]
        signal = mbl_mw_acc_bosch_get_acceleration_data_signal(device.board)!
        mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
            let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)
//            DispatchQueue.main.async {
//                _self.accelerometerBMI160Graph.addX(Double(acceleration.x), y: Double(acceleration.y), z: Double(acceleration.z))
//            }
            let dat = [
                "epoch": obj!.pointee.epoch,
                "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                "dir": _self.deviceDir_r
            ] as [String:Any]
            _self.accelerometerBMI160Data.append(dat)
        }
        mbl_mw_acc_enable_acceleration_sampling(device.board)
        mbl_mw_acc_start(device.board)
        
        streamingCleanup[signal] = {
            mbl_mw_acc_stop(device.board)
            mbl_mw_acc_disable_acceleration_sampling(device.board)
            mbl_mw_datasignal_unsubscribe(signal)
        }
    }

    func accelerometerBMI160StopStreamPressed() {
        for device in devices
       {
        let signal = mbl_mw_acc_bosch_get_acceleration_data_signal(device.board)!
        streamingCleanup.removeValue(forKey: signal)?()}
    }

    func accelerometerBMI160StartLogPressed() {
        
        updateAccelerometerBMI160Settings()
        var device = devices[0]
        var signal = mbl_mw_acc_bosch_get_acceleration_data_signal(device.board)!
        mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let cString = mbl_mw_logger_generate_identifier(logger)!
            let identifier = String(cString: cString) + _self.deviceDir_l
            _self.loggers[identifier + _self.deviceDir_l] = logger!
        }
        mbl_mw_logging_start(device.board, 0)
        mbl_mw_acc_enable_acceleration_sampling(device.board)
        
        mbl_mw_acc_start(device.board)
        
        device = devices[1]

        signal = mbl_mw_acc_bosch_get_acceleration_data_signal(device.board)!
        mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let cString = mbl_mw_logger_generate_identifier(logger)!
            let identifier = String(cString: cString) + _self.deviceDir_r
            _self.loggers[identifier + _self.deviceDir_r] = logger!
        }
        mbl_mw_logging_start(device.board, 0)
        mbl_mw_acc_enable_acceleration_sampling(device.board)
        mbl_mw_acc_start(device.board)
    }

    func accelerometerBMI160StopLogPressed() {
        
        var device = devices[0]
        
        guard var logger = loggers.removeValue(forKey: "acceleration" + deviceDir_l) else {
            return
        }
        
        mbl_mw_acc_stop(device.board)
        mbl_mw_acc_disable_acceleration_sampling(device.board)
        if bmi270 {
            mbl_mw_logging_flush_page(device.board)
        }
        
        
        hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
        hud.mode = .determinateHorizontalBar
        hud.label.text = "Downloading..."
        accelerometerBMI160Data.removeAll()
        mbl_mw_logger_subscribe(logger, bridge(obj: self)) { (context, obj) in
            let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)

            let dat = [
                "epoch": obj!.pointee.epoch,
                "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                "dir": _self.deviceDir_l
            ] as [String:Any]
            _self.accelerometerBMI160Data.append(dat)
        }
        
        var handlers = MblMwLogDownloadHandler()
        handlers.context = bridgeRetained(obj: self)
        handlers.received_progress_update = { (context, remainingEntries, totalEntries) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let progress = Double(totalEntries - remainingEntries) / Double(totalEntries)
            DispatchQueue.main.async {
                _self.hud.progress = Float(progress)
            }
            if remainingEntries == 0 {
                DispatchQueue.main.async {
                    _self.hud.mode = .indeterminate
                    _self.hud.label.text = "Clearing Log..."
                }
                _self.logCleanup { error in
                    DispatchQueue.main.async {
                        _self.hud.hide(animated: true)
                        if error != nil {
                            _self.deviceConnected(device: _self.devices[0])
                            
                        }
                    }
                }
            }
            
        }
        handlers.received_unknown_entry = { (context, id, epoch, data, length) in
            print("received_unknown_entry")
        }
        handlers.received_unhandled_entry = { (context, data) in
            print("received_unhandled_entry")
        }
        
        mbl_mw_logging_download(device.board, 100, &handlers)
        
        
        device = devices[1]
        
        guard var logger = loggers.removeValue(forKey: "acceleration" + deviceDir_r) else {
            return
        }
        
        mbl_mw_acc_stop(device.board)
        mbl_mw_acc_disable_acceleration_sampling(device.board)
        if bmi270 {
            mbl_mw_logging_flush_page(device.board)
        }
        
        
        hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
        hud.mode = .determinateHorizontalBar
        hud.label.text = "Downloading..."
        accelerometerBMI160Data.removeAll()
        mbl_mw_logger_subscribe(logger, bridge(obj: self)) { (context, obj) in
            let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)

            let dat = [
                "epoch": obj!.pointee.epoch,
                "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                "dir": _self.deviceDir_r
            ] as [String:Any]
            _self.accelerometerBMI160Data.append(dat)
        }
        
        handlers = MblMwLogDownloadHandler()
        handlers.context = bridgeRetained(obj: self)
        handlers.received_progress_update = { (context, remainingEntries, totalEntries) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let progress = Double(totalEntries - remainingEntries) / Double(totalEntries)
            DispatchQueue.main.async {
                _self.hud.progress = Float(progress)
            }
            if remainingEntries == 0 {
                DispatchQueue.main.async {
                    _self.hud.mode = .indeterminate
                    _self.hud.label.text = "Clearing Log..."
                }
                _self.logCleanup { error in
                    DispatchQueue.main.async {
                        _self.hud.hide(animated: true)
                        if error != nil {
                            _self.deviceConnected(device: _self.devices[1])
                            
                        }
                    }
                }
            }
            
        }
        handlers.received_unknown_entry = { (context, id, epoch, data, length) in
            print("received_unknown_entry")
        }
        handlers.received_unhandled_entry = { (context, data) in
            print("received_unhandled_entry")
        }
        
        mbl_mw_logging_download(device.board, 100, &handlers)
        
    }

    func accelerometerBMI16SendDataPressed() {
        send(self.accelerometerBMI160Data, title: "AccData")
    }
    
    func updateGyroBMI160Settings() {
        for device in devices
            {switch self.gyroBMI160Scale.selectedSegmentIndex {
            case 0:
                mbl_mw_gyro_bmi160_set_range(device.board, MBL_MW_GYRO_BOSCH_RANGE_125dps)
//                self.gyroBMI160Graph.fullScale = 1
            case 1:
                mbl_mw_gyro_bmi160_set_range(device.board, MBL_MW_GYRO_BOSCH_RANGE_250dps)
//                self.gyroBMI160Graph.fullScale = 2
            case 2:
                mbl_mw_gyro_bmi160_set_range(device.board, MBL_MW_GYRO_BOSCH_RANGE_500dps)
//                self.gyroBMI160Graph.fullScale = 4
            case 3:
                mbl_mw_gyro_bmi160_set_range(device.board, MBL_MW_GYRO_BOSCH_RANGE_1000dps)
//                self.gyroBMI160Graph.fullScale = 8
            case 4:
                mbl_mw_gyro_bmi160_set_range(device.board, MBL_MW_GYRO_BOSCH_RANGE_2000dps)
//                self.gyroBMI160Graph.fullScale = 16
            default:
                fatalError("Unexpected gyroBMI160Scale value")
            }
            switch self.gyroBMI160Frequency.selectedSegmentIndex {
            case 0:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_1600Hz)
            case 1:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_800Hz)
            case 2:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_400Hz)
            case 3:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_200Hz)
            case 4:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_100Hz)
            case 5:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_50Hz)
            case 6:
                mbl_mw_gyro_bmi160_set_odr(device.board, MBL_MW_GYRO_BOSCH_ODR_25Hz)
            default:
                fatalError("Unexpected gyroBMI160Frequency value")
            }
            mbl_mw_gyro_bmi160_write_config(device.board)}
    }

    func gyroBMI160StartStreamPressed() {
        
        updateGyroBMI160Settings()
        gyroBMI160Data.removeAll()
        var device = devices[0]
        if bmi270 {
            let signal = mbl_mw_gyro_bmi270_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let dat = [
                    "epoch": obj!.pointee.epoch,
                    "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                    "dir": _self.deviceDir_l
                ] as [String:Any]
                _self.gyroBMI160Data.append(dat)
            }
            mbl_mw_gyro_bmi270_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi270_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_gyro_bmi270_stop(device.board)
                mbl_mw_gyro_bmi270_disable_rotation_sampling(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        } else {
            let signal = mbl_mw_gyro_bmi160_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                    "epoch": obj!.pointee.epoch,
                    "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                    "dir": _self.deviceDir_l
                ] as [String:Any]
                _self.gyroBMI160Data.append(dat)
            }
            mbl_mw_gyro_bmi160_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi160_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_gyro_bmi160_stop(device.board)
                mbl_mw_gyro_bmi160_disable_rotation_sampling(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        }
        
        device = devices[1]
        if bmi270 {
            let signal = mbl_mw_gyro_bmi270_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let dat = [
                    "epoch": obj!.pointee.epoch,
                    "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                    "dir": _self.deviceDir_r
                ] as [String:Any]
                _self.gyroBMI160Data.append(dat)
            }
            mbl_mw_gyro_bmi270_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi270_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_gyro_bmi270_stop(device.board)
                mbl_mw_gyro_bmi270_disable_rotation_sampling(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        } else {
            let signal = mbl_mw_gyro_bmi160_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                    "epoch": obj!.pointee.epoch,
                    "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                    "dir": _self.deviceDir_r
                ] as [String:Any]
                _self.gyroBMI160Data.append(dat)
            }
            mbl_mw_gyro_bmi160_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi160_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_gyro_bmi160_stop(device.board)
                mbl_mw_gyro_bmi160_disable_rotation_sampling(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        }
    }

    func gyroBMI160StopStreamPressed() {
        var signal: OpaquePointer?
        for device in devices
        {if bmi270 {
            signal = mbl_mw_gyro_bmi270_get_rotation_data_signal(device.board)!
        } else {
            signal = mbl_mw_gyro_bmi160_get_rotation_data_signal(device.board)!
        
        streamingCleanup.removeValue(forKey: signal!)?()}
        }
    }

    func gyroBMI160StartLogPressed() {
        
        updateGyroBMI160Settings()
        
        var device = devices[0]
        if bmi270 {
            let signal = mbl_mw_gyro_bmi270_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let cString = mbl_mw_logger_generate_identifier(logger)!
                let identifier = String(cString: cString)
                _self.loggers[identifier + _self.deviceDir_l] = logger!
            }
            mbl_mw_logging_start(device.board, 0)
            mbl_mw_gyro_bmi270_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi270_start(device.board)
        } else {
            let signal = mbl_mw_gyro_bmi160_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let cString = mbl_mw_logger_generate_identifier(logger)!
                let identifier = String(cString: cString)
                _self.loggers[identifier + _self.deviceDir_l] = logger!
            }
            mbl_mw_logging_start(device.board, 0)
            mbl_mw_gyro_bmi160_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi160_start(device.board)
        }
        
        device = devices[1]
        if bmi270 {
            let signal = mbl_mw_gyro_bmi270_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_log(signal, bridge(obj: self))
            { (context, logger) in
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let cString = mbl_mw_logger_generate_identifier(logger)!
                let identifier = String(cString: cString)
                _self.loggers[identifier + _self.deviceDir_r] = logger!
            }
            mbl_mw_logging_start(device.board, 0)
            mbl_mw_gyro_bmi270_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi270_start(device.board)
        } else {
            let signal = mbl_mw_gyro_bmi160_get_rotation_data_signal(device.board)!
            mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let cString = mbl_mw_logger_generate_identifier(logger)!
                let identifier = String(cString: cString)
                _self.loggers[identifier + _self.deviceDir_r] = logger!
            }
            mbl_mw_logging_start(device.board, 0)
            mbl_mw_gyro_bmi160_enable_rotation_sampling(device.board)
            mbl_mw_gyro_bmi160_start(device.board)
        }
        
    }


    func gyroBMI160StopLogPressed() {
        
        var device = devices[0]
        
        guard let logger = loggers.removeValue(forKey: "angular-velocity" + deviceDir_l) else {
            return
        }
        
            if bmi270 {
                mbl_mw_gyro_bmi270_stop(device.board)
                mbl_mw_gyro_bmi270_disable_rotation_sampling(device.board)
                mbl_mw_logging_flush_page(device.board)
            } else {
                mbl_mw_gyro_bmi160_stop(device.board)
                mbl_mw_gyro_bmi160_disable_rotation_sampling(device.board)
            }
        

            hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
            hud.mode = .determinateHorizontalBar
            hud.label.text = "Downloading..."
            gyroBMI160Data.removeAll()
            mbl_mw_logger_subscribe(logger, bridge(obj: self)) { (context, obj) in
                let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
//                DispatchQueue.main.async {
//                    _self.gyroBMI160Graph.addX(Double(acceleration.x * 0.008), y: Double(acceleration.y * 0.008), z: Double(acceleration.z * 0.008))
//                }
                // Add data to data array for saving
                let dat = [
                    "epoch": obj!.pointee.epoch,
                    "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                    "dir": _self.deviceDir_l
                ] as [String:Any]
                _self.gyroBMI160Data.append(dat)
            }
            
            var handlers = MblMwLogDownloadHandler()
            handlers.context = bridgeRetained(obj: self)
            handlers.received_progress_update = { (context, remainingEntries, totalEntries) in
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let progress = Double(totalEntries - remainingEntries) / Double(totalEntries)
                DispatchQueue.main.async {
                    _self.hud.progress = Float(progress)
                }
                if remainingEntries == 0 {
                    DispatchQueue.main.async {
                        _self.hud.mode = .indeterminate
                        _self.hud.label.text = "Clearing Log..."
                    }
                    _self.logCleanup { error in
                        DispatchQueue.main.async {
                            _self.hud.hide(animated: true)
                            if error != nil {
                                _self.deviceConnected(device: _self.devices[0])
                            }
                        }
                    }
                }
            }
            handlers.received_unknown_entry = { (context, id, epoch, data, length) in
                print("received_unknown_entry")
            }
            handlers.received_unhandled_entry = { (context, data) in
                print("received_unhandled_entry")
            }
            mbl_mw_logging_download(device.board, 100, &handlers)
        
        
        
        device = devices[1]
        
        guard let logger = loggers.removeValue(forKey: "angular-velocity" + deviceDir_r) else {
            return
        }
        
            if bmi270 {
                mbl_mw_gyro_bmi270_stop(device.board)
                mbl_mw_gyro_bmi270_disable_rotation_sampling(device.board)
                mbl_mw_logging_flush_page(device.board)
            } else {
                mbl_mw_gyro_bmi160_stop(device.board)
                mbl_mw_gyro_bmi160_disable_rotation_sampling(device.board)
            }
        

            hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
            hud.mode = .determinateHorizontalBar
            hud.label.text = "Downloading..."
            gyroBMI160Data.removeAll()
            mbl_mw_logger_subscribe(logger, bridge(obj: self)) { (context, obj) in
                let acceleration: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
//                DispatchQueue.main.async {
//                    _self.gyroBMI160Graph.addX(Double(acceleration.x * 0.008), y: Double(acceleration.y * 0.008), z: Double(acceleration.z * 0.008))
//                }
                // Add data to data array for saving
                let dat = [
                    "epoch": obj!.pointee.epoch,
                    "x": acceleration.x,
                "y": acceleration.y,
                "z": acceleration.z,
                    "dir": _self.deviceDir_r
                ] as [String:Any]
                _self.gyroBMI160Data.append(dat)
            }
            
            handlers = MblMwLogDownloadHandler()
            handlers.context = bridgeRetained(obj: self)
            handlers.received_progress_update = { (context, remainingEntries, totalEntries) in
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let progress = Double(totalEntries - remainingEntries) / Double(totalEntries)
                DispatchQueue.main.async {
                    _self.hud.progress = Float(progress)
                }
                if remainingEntries == 0 {
                    DispatchQueue.main.async {
                        _self.hud.mode = .indeterminate
                        _self.hud.label.text = "Clearing Log..."
                    }
                    _self.logCleanup { error in
                        DispatchQueue.main.async {
                            _self.hud.hide(animated: true)
                            if error != nil {
            
                                _self.deviceConnected(device: _self.devices[1])
                                
                            }
                        }
                    }
                }
            }
            handlers.received_unknown_entry = { (context, id, epoch, data, length) in
                print("received_unknown_entry")
            }
            handlers.received_unhandled_entry = { (context, data) in
                print("received_unhandled_entry")
            }
            mbl_mw_logging_download(device.board, 100, &handlers)
    }

    func gyroBMI160SendDataPressed() {
        self.send(self.gyroBMI160Data, title: "GyroData")
    }

   


    func updateSensorFusionSettings() {
        for device in devices
        {mbl_mw_sensor_fusion_set_acc_range(device.board, MBL_MW_SENSOR_FUSION_ACC_RANGE_16G)
        mbl_mw_sensor_fusion_set_gyro_range(device.board, MBL_MW_SENSOR_FUSION_GYRO_RANGE_2000DPS)
        mbl_mw_sensor_fusion_set_mode(device.board, MblMwSensorFusionMode(UInt32(sensorFusionMode.selectedSegmentIndex + 1)))
        sensorFusionMode.isEnabled = false
        sensorFusionOutput.isEnabled = false
            sensorFusionData.removeAll()
            
        }
    }

    
    func resetSensorFusionPressed() {
        for device in devices
        { mbl_mw_sensor_fusion_reset_orientation(device.board)}
    }
    
    func sensorFusionStartStreamPressed() {
        updateSensorFusionSettings()
        sensorFusionData.removeAll()
        
        var device = devices[deviceI_l]
        
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
//            sensorFusionGraph.hasW = true
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let euler: MblMwEulerAngles = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                    "dir" : _self.deviceDir_l,
                    "epoch": obj!.pointee.epoch,
                    "pitch": euler.pitch,
                    "roll": euler.roll,
                    "yaw": euler.yaw,
                    "heading": euler.heading
                ] as [String : Any]
                _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        case 1:
//            sensorFusionGraph.hasW = true
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let quaternion: MblMwQuaternion = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                
                let dat = [
                    "dir" : _self.deviceDir_l,
                "epoch": obj!.pointee.epoch,
                "w": quaternion.w,
                "x": quaternion.x,
                "y": quaternion.y,
                "z": quaternion.z
            ] as [String : Any]
            _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        case 2:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                    "dir" : _self.deviceDir_l,
                    "epoch": obj!.pointee.epoch,
                    "x": acc.x,
                    "y": acc.y,
                    "z": acc.z
            ] as [String : Any]
                _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        case 3:
//            sensorFusionGraph.hasW = false
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                "dir" : _self.deviceDir_l,
                "epoch": obj!.pointee.epoch,
                "x": acc.x,
                "y": acc.y,
                "z": acc.z
            ] as [String : Any]
                
                _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_set_acc_range(device.board, MBL_MW_SENSOR_FUSION_ACC_RANGE_8G)
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        default:
            assert(false, "Added a new sensor fusion output?")
        }
        
        device = devices[deviceI_r]
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let euler: MblMwEulerAngles = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                    "dir" : _self.deviceDir_r,
                    "epoch": obj!.pointee.epoch,
                    "pitch": euler.pitch,
                    "roll": euler.roll,
                    "yaw": euler.yaw,
                    "heading": euler.heading
                ] as [String : Any]
                _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        case 1:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let quaternion: MblMwQuaternion = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                
                let dat = [
                    "dir" : _self.deviceDir_r,
                "epoch": obj!.pointee.epoch,
                "w": quaternion.w,
                "x": quaternion.x,
                "y": quaternion.y,
                "z": quaternion.z
            ] as [String : Any]
            _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        case 2:
//            sensorFusionGraph.hasW = false
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                    "dir" : _self.deviceDir_r,
                    "epoch": obj!.pointee.epoch,
                    "x": acc.x,
                    "y": acc.y,
                    "z": acc.z
            ] as [String : Any]
                _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        case 3:
//            sensorFusionGraph.hasW = false
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)!
            mbl_mw_datasignal_subscribe(signal, bridge(obj: self)) { (context, obj) in
                let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)

                let dat = [
                "dir" : _self.deviceDir_r,
                "epoch": obj!.pointee.epoch,
                "x": acc.x,
                "y": acc.y,
                "z": acc.z
            ] as [String : Any]
                
                _self.sensorFusionData.append(dat)
            }
            mbl_mw_sensor_fusion_set_acc_range(device.board, MBL_MW_SENSOR_FUSION_ACC_RANGE_8G)
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)
            mbl_mw_sensor_fusion_write_config(device.board)
            mbl_mw_sensor_fusion_start(device.board)
            
            streamingCleanup[signal] = {
                mbl_mw_sensor_fusion_stop(device.board)
                mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
                mbl_mw_datasignal_unsubscribe(signal)
            }
        default:
            assert(false, "Added a new sensor fusion output?")
        }
    }

    func sensorFusionStopStreamPressed() {
        
        sensorFusionMode.isEnabled = true
        sensorFusionOutput.isEnabled = true
        for device in devices
        {switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)!
            streamingCleanup.removeValue(forKey: signal)?()
        case 1:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)!
            streamingCleanup.removeValue(forKey: signal)?()
        case 2:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)!
            streamingCleanup.removeValue(forKey: signal)?()
        case 3:
            let signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)!
            streamingCleanup.removeValue(forKey: signal)?()
        default:
            assert(false, "Added a new sensor fusion output?")
        }}
    }

    func sensorFusionStartLogPressed() {
        
        updateSensorFusionSettings()
        
            var device = devices[0]
            mbl_mw_sensor_fusion_clear_enabled_mask(device.board)

        var signal: OpaquePointer
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)!
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)
        case 1:
            signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)!
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)
        case 2:
            signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)!
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)
        case 3:
            mbl_mw_sensor_fusion_set_acc_range(device.board, MBL_MW_SENSOR_FUSION_ACC_RANGE_8G)
            signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)!
            mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)
        default:
            fatalError("Added a new sensor fusion output?")
        }
        
        mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let cString = mbl_mw_logger_generate_identifier(logger)!
            let identifier = String(cString: cString) + _self.deviceDir_l
            _self.loggers[identifier] = logger!
        }
        mbl_mw_logging_start(device.board, 0)
        mbl_mw_sensor_fusion_write_config(device.board)
        mbl_mw_sensor_fusion_start(device.board)
        
        device = devices[1]
        mbl_mw_sensor_fusion_clear_enabled_mask(device.board)

//    let signal: OpaquePointer
    switch sensorFusionOutput.selectedSegmentIndex {
    case 0:
        signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)!
        mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_EULER_ANGLE)
    case 1:
        signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)!
        mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_QUATERNION)
    case 2:
        signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)!
        mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_GRAVITY_VECTOR)
    case 3:
        mbl_mw_sensor_fusion_set_acc_range(device.board, MBL_MW_SENSOR_FUSION_ACC_RANGE_8G)
        signal = mbl_mw_sensor_fusion_get_data_signal(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)!
        mbl_mw_sensor_fusion_enable_data(device.board, MBL_MW_SENSOR_FUSION_DATA_LINEAR_ACC)
    default:
        fatalError("Added a new sensor fusion output?")
    }
    
    mbl_mw_datasignal_log(signal, bridge(obj: self)) { (context, logger) in
        let _self: DeviceDetailViewController = bridge(ptr: context!)
        let cString = mbl_mw_logger_generate_identifier(logger)!
        let identifier = String(cString: cString) + _self.deviceDir_r
        _self.loggers[identifier] = logger!
    }
    mbl_mw_logging_start(device.board, 0)
    mbl_mw_sensor_fusion_write_config(device.board)
    mbl_mw_sensor_fusion_start(device.board)
    }

func sensorFusionStopLogPressed() {
        
        sensorFusionMode.isEnabled = true
        sensorFusionOutput.isEnabled = true
    var outloggers = [OpaquePointer?]()
    var outhandlers = [MblMwFnData]()
    
    
        var deviceDir = "l"
        var deviceI = 0
        var device = devices[deviceI]
    
        switch sensorFusionOutput.selectedSegmentIndex {
        case 0:
            outloggers.insert(loggers.removeValue(forKey: "euler-angles" + deviceDir), at: deviceI)
            
            let handler: MblMwFnData  = { (context, obj) in
                let euler: MblMwEulerAngles = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let dat = [
                    "dir" : _self.deviceDir_l,
                    "epoch": obj!.pointee.epoch,
                    "pitch": euler.pitch,
                    "roll": euler.roll,
                    "yaw": euler.yaw,
                    "heading": euler.heading
                ] as [String : Any]
                
                
                _self.sensorFusionData.append(dat)
            }
            outhandlers.insert(handler, at: deviceI)
        case 1:
            let logger = loggers.removeValue(forKey: "quaternion" + deviceDir)
            outloggers.insert(logger, at: deviceI)
            let handler: MblMwFnData = { (context, obj) in
                let quaternion: MblMwQuaternion = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let dat = [
                    "dir" : _self.deviceDir_l,
                "epoch": obj!.pointee.epoch,
                "w": quaternion.w,
                "x": quaternion.x,
                "y": quaternion.y,
                "z": quaternion.z
            ] as [String : Any]
            
                
            _self.sensorFusionData.append(dat)
            }
            outhandlers.insert(handler, at: deviceI)
        case 2:
//            sensorFusionGraph.hasW = false
            let logger = loggers.removeValue(forKey: "gravity" + deviceDir)
            outloggers.insert(logger, at: deviceI)
            let handler: MblMwFnData = { (context, obj) in
                let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let dat = [
                    "dir" : _self.deviceDir_l,
                "epoch": obj!.pointee.epoch,
                "x": acc.x,
                "y": acc.y,
                "z": acc.z
            ] as [String : Any]
            

                _self.sensorFusionData.append(dat)
            }
            outhandlers.insert(handler, at: deviceI)
        case 3:
            let logger = loggers.removeValue(forKey: "linear-acceleration" + deviceDir)
            
            outloggers.insert(logger, at: deviceI)
            
            let handler: MblMwFnData = { (context, obj) in
                let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
                let _self: DeviceDetailViewController = bridge(ptr: context!)
                let dat = [
                "dir" : _self.deviceDir_l,
                "epoch": obj!.pointee.epoch,
                "x": acc.x,
                "y": acc.y,
                "z": acc.z
            ] as [String : Any]
                
               
                _self.sensorFusionData.append(dat)
            }
            outhandlers.insert(handler, at: deviceI)
        default:
            fatalError("Added a new sensor fusion output?")
        }
        guard outloggers[deviceI] != nil else {
            return
        }
    
    
    deviceDir = "r"
    deviceI = 1
    device = devices[deviceI]

    switch sensorFusionOutput.selectedSegmentIndex {
    case 0:
        outloggers.insert(loggers.removeValue(forKey: "euler-angles" + deviceDir), at: deviceI)
        
        let handler: MblMwFnData  = { (context, obj) in
            let euler: MblMwEulerAngles = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let dat = [
                "dir" : _self.deviceDir_r,
                "epoch": obj!.pointee.epoch,
                "pitch": euler.pitch,
                "roll": euler.roll,
                "yaw": euler.yaw,
                "heading": euler.heading
            ] as [String : Any]
            
            
            _self.sensorFusionData.append(dat)
        }
        outhandlers.insert(handler, at: deviceI)
    case 1:
        let logger = loggers.removeValue(forKey: "quaternion" + deviceDir)
        outloggers.insert(logger, at: deviceI)
        let handler: MblMwFnData = { (context, obj) in
            let quaternion: MblMwQuaternion = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let dat = [
            "dir" : _self.deviceDir_r,
            "epoch": obj!.pointee.epoch,
            "w": quaternion.w,
            "x": quaternion.x,
            "y": quaternion.y,
            "z": quaternion.z
        ] as [String : Any]
      
        _self.sensorFusionData.append(dat)
        }
        outhandlers.insert(handler, at: deviceI)
    case 2:
//            sensorFusionGraph.hasW = false
        let logger = loggers.removeValue(forKey: "gravity" + deviceDir)
        outloggers.insert(logger, at: deviceI)
        let handler: MblMwFnData = { (context, obj) in
            let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let dat = [
            "dir" : _self.deviceDir_r,
            "epoch": obj!.pointee.epoch,
            "x": acc.x,
            "y": acc.y,
            "z": acc.z
        ] as [String : Any]

            _self.sensorFusionData.append(dat)
        }
        outhandlers.insert(handler, at: deviceI)
    case 3:
        let logger = loggers.removeValue(forKey: "linear-acceleration" + deviceDir)
        
        outloggers.insert(logger, at: deviceI)
        
        let handler: MblMwFnData = { (context, obj) in
            let acc: MblMwCartesianFloat = obj!.pointee.valueAs()
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let dat = [
            "dir" : _self.deviceDir_r,
            "epoch": obj!.pointee.epoch,
            "x": acc.x,
            "y": acc.y,
            "z": acc.z
        ] as [String : Any]
            
       
            _self.sensorFusionData.append(dat)
        }
        outhandlers.insert(handler, at: deviceI)
    default:
        fatalError("Added a new sensor fusion output?")
    }
    guard outloggers[deviceI] != nil else {
        return
    }
    
    // FINAL
    
    deviceDir = "l"
    deviceI = 0
    device = devices[deviceI]
    
        mbl_mw_sensor_fusion_stop(device.board)
        mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
        if bmi270 {
            mbl_mw_logging_flush_page(device.board)
        }
        
        hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
        hud.mode = .determinateHorizontalBar
        hud.label.text = "Downloading..."
        
        sensorFusionData.removeAll()
        mbl_mw_logger_subscribe(outloggers[deviceI], bridge(obj: self), outhandlers[deviceI])
        var handlers = MblMwLogDownloadHandler()
        handlers.context = bridgeRetained(obj: self)
        handlers.received_progress_update = { (context, remainingEntries, totalEntries) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let progress = Double(totalEntries - remainingEntries) / Double(totalEntries)
            DispatchQueue.main.async {
                _self.hud.progress = Float(progress)
            }
            if remainingEntries == 0 {
                DispatchQueue.main.async {
                    _self.hud.mode = .indeterminate
                    _self.hud.label.text = "Clearing Log..."
                }
                _self.logCleanup { error in
                    DispatchQueue.main.async {
                        _self.hud.hide(animated: true)
                        if error != nil {
                            _self.deviceConnected(device: _self.devices[_self.deviceI_l])
                        }
                    }
                }
            }
        }
        
            handlers.received_unknown_entry = { (context, id, epoch, data, length) in
                print("received_unknown_entry")
            }
            handlers.received_unhandled_entry = { (context, data) in
                print("received_unhandled_entry")
            }
            mbl_mw_logging_download(device.board, 100, &handlers)
        
    // FINAL
    
    deviceDir = "r"
    deviceI = 1
    device = devices[deviceI]
    
        mbl_mw_sensor_fusion_stop(device.board)
        mbl_mw_sensor_fusion_clear_enabled_mask(device.board)
        if bmi270 {
            mbl_mw_logging_flush_page(device.board)
        }
        
        hud = MBProgressHUD.showAdded(to: UIApplication.shared.keyWindow!, animated: true)
        hud.mode = .determinateHorizontalBar
        hud.label.text = "Downloading..."
        
        sensorFusionData.removeAll()
        mbl_mw_logger_subscribe(outloggers[deviceI], bridge(obj: self), outhandlers[deviceI])
        handlers = MblMwLogDownloadHandler()
        handlers.context = bridgeRetained(obj: self)
        handlers.received_progress_update = { (context, remainingEntries, totalEntries) in
            let _self: DeviceDetailViewController = bridge(ptr: context!)
            let progress = Double(totalEntries - remainingEntries) / Double(totalEntries)
            DispatchQueue.main.async {
                _self.hud.progress = Float(progress)
            }
            if remainingEntries == 0 {
                DispatchQueue.main.async {
                    _self.hud.mode = .indeterminate
                    _self.hud.label.text = "Clearing Log..."
                }
                _self.logCleanup { error in
                    DispatchQueue.main.async {
                        _self.hud.hide(animated: true)
                        if error != nil {
                            _self.deviceConnected(device: _self.devices[_self.deviceI_r])
                        }
                    }
                }
            }
        }
        
            handlers.received_unknown_entry = { (context, id, epoch, data, length) in
                print("received_unknown_entry")
            }
            handlers.received_unhandled_entry = { (context, data) in
                print("received_unhandled_entry")
            }
            mbl_mw_logging_download(device.board, 100, &handlers)
        
    }

    func sensorFusionSendDataPressed() {

        send(sensorFusionData, title: "SensorFusion")
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.endEditing(false)
        return true
    }
    

}

extension DeviceDetailViewController: DFUProgressDelegate {
    func dfuProgressDidChange(for part: Int, outOf totalParts: Int, to progress: Int, currentSpeedBytesPerSecond: Double, avgSpeedBytesPerSecond: Double) {
        hud?.progress = Float(progress) / 100.0
    }
}


extension UIViewController {
    /// Call this once to dismiss open keyboards by tapping anywhere in the view controller
    func setupHideKeyboardOnTap() {
        self.view.addGestureRecognizer(self.endEditingRecognizer())
        self.navigationController?.navigationBar.addGestureRecognizer(self.endEditingRecognizer())
    }

    /// Dismisses the keyboard from self.view
    private func endEditingRecognizer() -> UIGestureRecognizer {
        let tap = UITapGestureRecognizer(target: self.view, action: #selector(self.view.endEditing(_:)))
        tap.cancelsTouchesInView = false
        return tap
    }
}


extension Date {

    func toMillis() -> Int64! {
        return Int64(self.timeIntervalSince1970 * 1000)
    }

    init(millis: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(millis / 1000))
        self.addTimeInterval(TimeInterval(Double(millis % 1000) / 1000 ))
    }

}
