//
//  SetupState.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation
// import UIKit

let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df
}()

let defaultStart = dateFormatter.date(from: "2021-12-01")!

private func dateFor(key: String) -> Date {
    let d = UserDefaults.standard.double(forKey: key)
    if d == 0 {
        return defaultStart
    }
    return Date(timeIntervalSince1970: d)
}

// struct Configuration : Sendable {
//    let region: String
//    let notifications: Int
//    let enpaKey: String
//    let encvKey: String
//    let startDate: Date
//    let configStartDate: Date
// }

class SetupState: NSObject, ObservableObject { // }, UNUserNotificationCenterDelegate {
    static let shared = SetupState()

    static let faceIDKey = "faceIDKey"
    static let regionKey = "region"
    static let encvKeyKey = "encv"
    static let enpaKeyKey = "enpaKey"
    static let startKey = "startKey"
    static let notificationsKey = "notificationsKey"
    static let configStartKey = "configStartKey"
    static let testServerKey = "testServerKey"
    static let debuggingKey = "debuggingKey"

    var config: Configuration {
        Configuration(daysSinceExposureThreshold: 10, numDays: 7, numCategories: notifications, region: region, enpaAPIKey: enpaKey, encvAPIKey: encvKey, startDate: startDate, configStart: configStartDate, useTestServers: useTestServers)
    }

    @Published var region: String = "" {
        didSet {
            UserDefaults.standard.set(region, forKey: Self.regionKey)
        }
    }

    @Published var useFaceID: Bool = true {
        didSet {
            UserDefaults.standard.set(useFaceID, forKey: Self.faceIDKey)
        }
    }

    @Published var notifications: Int = 1 {
        didSet {
            UserDefaults.standard.set(notifications, forKey: Self.notificationsKey)
        }
    }

    @Published var encvKey: String = "" {
        didSet {
            Task(priority: .userInitiated) {
                await AnalysisState.shared.deleteComposite()
            }
            UserDefaults.standard.set(encvKey, forKey: Self.encvKeyKey)
        }
    }

    @Published var enpaKey: String = "" {
        didSet {
            UserDefaults.standard.set(enpaKey, forKey: Self.enpaKeyKey)
        }
    }

    @Published var startDate: Date = defaultStart {
        didSet {
            UserDefaults.standard.set(startDate.timeIntervalSince1970, forKey: Self.startKey)
        }
    }

    @Published var configStartDate: Date? = defaultStart {
        didSet {
            if let date = configStartDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.configStartKey)
            }
        }
    }

    @Published var useTestServers: Bool = false {
        didSet {
            UserDefaults.standard.set(useTestServers, forKey: Self.testServerKey)
        }
    }

    @Published var debuggingFeatures: Bool = false {
        didSet {
            UserDefaults.standard.set(debuggingFeatures, forKey: Self.debuggingKey)
        }
    }

    var build: String {
        guard let info = Bundle.main.infoDictionary else {
            return "unknown"
        }
        return info["CFBundleVersion"] as? String ?? "unknown"
    }

    var appVersion: String {
        guard let info = Bundle.main.infoDictionary else {
            return "unknown"
        }
        return info["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var setupNeeded: Bool {
        region.isEmpty || encvKey.isEmpty && enpaKey.isEmpty
    }

    static let testEncvKey = "x2TtU303DaAGRxUibfMG9rqT-D9l0A942JiP_6o7bamUJV4s0BiJ8bPsTU-B2n3XiBVnO3BKlc9Y7jKoRnHtOQ.1.DM6RDGij9f-wno9I_o6VbcBC3kZ9Y4CF0XvIyN3sBBV6a5rodTKDeEPmWOkPZI3Fy78LZJBopZNUFPJLk-I-2Q"
    static let testEnpaKey = "436b5bda-8336-4a2c-84c9-52cf5558b238.a1fbbeaad15842696fe56fc45522de112ac089f51e8bdebbd4193b17a77d7a1b"

    @MainActor var usingTestData: Bool {
        get {
            isUsingTestData
        }
        set(newValue) {
            clear()
            if newValue {
                region = "US-EV"
                encvKey = SetupState.testEncvKey
                enpaKey = SetupState.testEnpaKey
                useTestServers = true
                notifications = 1
                startDate = defaultStart
                useTestServers = true
            } 
        }
    }

    var isUsingTestData: Bool {
        useTestServers && encvKey == SetupState.testEncvKey && enpaKey == SetupState.testEnpaKey
    }

    @MainActor func clear() {
        region = ""
        encvKey = ""
        enpaKey = ""
        startDate = defaultStart
        configStartDate = nil // defaultStart
        notifications = 1
        useFaceID = false
        useTestServers = false
        AnalysisState.shared.clear()
    }

    var isClear: Bool {
        region.isEmpty && encvKey.isEmpty && enpaKey.isEmpty
    }

    init(testConfigWithNotifications: Int) {
        useFaceID = false
        notifications = testConfigWithNotifications
        useTestServers = true
        region = "US-EV"
        encvKey = SetupState.testEncvKey
        enpaKey = SetupState.testEnpaKey
        startDate = defaultStart
        configStartDate = nil
    }

    override init() {
        let faceid = UserDefaults.standard.bool(forKey: Self.faceIDKey)
        useFaceID = faceid
        if let data = UserDefaults.standard.string(forKey: Self.regionKey) {
            region = data
        }
        notifications = max(1, UserDefaults.standard.integer(forKey: Self.notificationsKey))
        useTestServers = UserDefaults.standard.bool(forKey: Self.testServerKey)
        debuggingFeatures = UserDefaults.standard.bool(forKey: Self.debuggingKey)
        if let data = UserDefaults.standard.string(forKey: Self.encvKeyKey) {
            encvKey = data
        }
        if let data = UserDefaults.standard.string(forKey: Self.enpaKeyKey) {
            enpaKey = data
        }

        startDate = dateFor(key: Self.startKey)
        configStartDate = nil // dateFor(key: Self.configStartKey)
    }
}
