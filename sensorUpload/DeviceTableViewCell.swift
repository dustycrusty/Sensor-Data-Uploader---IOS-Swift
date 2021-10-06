//
//  DeviceTableViewCell.swift
//  sensorUpload
//
//  Created by 이승윤 on 2021/09/21.
//


import UIKit
import MetaWear

class DeviceTableViewCell: UITableViewCell {
    var model: ScannerModelItem! {
        didSet {
            model.stateDidChange = { [weak self] in
                DispatchQueue.main.async {
                    self?.updateView(cur: self!.model.device)
                }
            }
        }
    }
    var device: MetaWear? {
        didSet {
            if let device = device {
                DispatchQueue.main.async {
                    self.updateView(cur: device)
                }
            }
        }
    }
    
    func updateView(cur: MetaWear) {
        let uuid = viewWithTag(1) as! UILabel
        uuid.text = cur.mac ?? "Connect for MAC"
        
        let rssi = viewWithTag(2) as! UILabel
        rssi.text = String(cur.rssi)
        
        let connected = viewWithTag(3) as! UILabel
        if cur.peripheral.state == .connected {
            connected.isHidden = false
        } else {
            connected.isHidden = true
        }
        
        let name = viewWithTag(4) as! UILabel
        name.text = cur.name
        
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
}

