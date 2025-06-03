//
//  Notification+Extension.swift
//  Babymonitor
//
//  Created by Krijn Haasnoot on 25/03/2025.
//

import Foundation

extension Notification.Name {
    static let babyNoiseDetected = Notification.Name("babyNoiseDetected")
    static let cameraToggle = Notification.Name("cameraToggle")
    static let batteryLow = Notification.Name("batteryLow")
    static let connectionStatusChanged = Notification.Name("connectionStatusChanged")
}
