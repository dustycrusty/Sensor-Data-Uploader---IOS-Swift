//
//  DevicesTableViewController.swift
//  sensorUpload
//
//  Created by 이승윤 on 2021/09/20.
//

import UIKit
import MetaWear
import MetaWearCpp
import MBProgressHUD
import iOSDFULibrary
import FirebaseAuth

fileprivate let scanner = MetaWearScanner()

class DevicesTableViewController: UITableViewController {
    var hud: MBProgressHUD?
    var scannerModel: ScannerModel!
    var connectedDevices: [MetaWear] = []
    
    var selectedDevices: [MetaWear] = []
    
    @IBOutlet weak var scanningSwitch: UISwitch!
    @IBOutlet weak var activity: UIActivityIndicatorView!
    
 
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationItem.setHidesBackButton(true, animated: false)
        setScanning(scanningSwitch.isOn)
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        setScanning(false)
    }
    
    func setScanning(_ on: Bool) {
        if on {
            activity.startAnimating()
            
                scannerModel = ScannerModel(delegate: self, scanner: scanner, adTimeout: 5) { device -> Bool in
                    return !device.isMetaBoot
                
            }
        } else {
            activity.stopAnimating()
        }
        scannerModel.isScanning = on
//        connectedDevices = scanner.deviceMap.filter{ $0.key.state == .connected }.map{ $0.value }
        tableView.reloadData()
    }

    @IBAction func scanningSwitchPressed(_ sender: UISwitch) {
        setScanning(sender.isOn)
    }
    
    @IBAction func goToDetailPressed(_ sender: Any) {
        performSegue(withIdentifier: "DeviceDetails", sender: selectedDevices)
    }
    
    
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return scannerModel.items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! DeviceTableViewCell
        if indexPath.section == 0 {
            cell.model = scannerModel.items[indexPath.row]
            cell.accessoryType = .none
        } else {
            cell.model = scannerModel.items[indexPath.row]
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Devices"
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if indexPath.section == 0 {
            let device =  scannerModel.items[indexPath.row].device
            if !selectedDevices.contains(device) {
                if let cell = tableView.cellForRow(at: indexPath) {
                    cell.accessoryType = .checkmark
                }

                selectedDevices.append(device)
            } else {
                tableView.deselectRow(at: indexPath, animated: false)
            }
        } else {
            tableView.deselectRow(at: indexPath, animated: false)
        }
//        let device = indexPath.section == 0 ? connectedDevices[indexPath.row] : scannerModel.items[indexPath.row].device
        
//        performSegue(withIdentifier: "DeviceDetails", sender: device)
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            let device =  scannerModel.items[indexPath.row].device
            if let index = selectedDevices.firstIndex(of: device) {
                selectedDevices.remove(at: index)
            }
            if let cell = tableView.cellForRow(at: indexPath) {
                cell.accessoryType = .none
            }
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let destination = segue.destination as! DeviceDetailViewController
        destination.devices = self.selectedDevices
    }
}

extension DevicesTableViewController: ScannerModelDelegate {
    func scannerModel(_ scannerModel: ScannerModel, didAddItemAt idx: Int) {
        let indexPath = IndexPath(row: idx, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
    }
    
    func scannerModel(_ scannerModel: ScannerModel, confirmBlinkingItem item: ScannerModelItem, callback: @escaping (Bool) -> Void) {
        
    }
    
    func scannerModel(_ scannerModel: ScannerModel, errorDidOccur error: Error) {
        
    }
}
