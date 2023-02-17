//
//  SetupState.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation
// import UIKit

// struct Configuration : Sendable {
//    let region: String
//    let notifications: Int
//    let enpaKey: String
//    let encvKey: String
//    let startDate: Date
//    let configStartDate: Date
// }

func dateFor(key: String) -> Date {
    let d = UserDefaults.standard.double(forKey: key)
    if d == 0 {
        return defaultStart
    }
    return Date(timeIntervalSince1970: d)
}

func getTestServers() -> NSDictionary? {
    do {
        if let fileURL = Bundle.main.url(forResource: "testServers", withExtension: "json") {
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers]) as! NSDictionary

            return json
        }
        return nil
    } catch {
        return nil
    }
}

class SetupState: NSObject, ObservableObject { // }, UNUserNotificationCenterDelegate {
    static let shared = SetupState()

    static let faceIDKey = "faceIDKey"
    static let regionKey = "region"
    static let encvKeyKey = "encv"
    static let enpaKeyKey = "enpaKey"
    static let startKey = "startKey"
    static let notificationsKey = "notificationsKey"
    static let alertKey = "alertKey"
    static let configStartKey = "configStartKey"
    static let testServerKey = "testServerKey"
    static let daysRollupKey = "daysRollupKey"
    static let baselineExposureKey = "baselineExposureKey"
    static let highInfectiousnessWeightKey = "highInfectiousnessWeightKey"
    static let debuggingKey = "debuggingKey"

    func convertToUTCDay(_ date: Date) -> Date {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let s = df.string(from: date)
        df.timeZone = TimeZone(identifier: "UTC")!
        let ss = df.date(from: s)!
        return ss
    }

    var config: Configuration {
        Configuration(daysSinceExposureThreshold: 10, numDays: daysRollup, numCategories: notifications, region: region, enpaAPIKey: enpaKey, encvAPIKey: encvKey, startDate: convertToUTCDay(startDate), configStart: configStartDate,
                      durationBaselineMinutes: durationBaselineMinutes,
                      highInfectiousnessWeight: highInfectiousnessWeight,
                      useTestServers: useTestServers)
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

    @Published var alertDismissed: Bool = true {
        didSet {
            UserDefaults.standard.set(alertDismissed, forKey: Self.alertKey)
        }
    }

    @Published var durationBaselineMinutes: Double = 15.0 {
        didSet {
            UserDefaults.standard.set(durationBaselineMinutes, forKey: Self.baselineExposureKey)
        }
    }

    @Published var highInfectiousnessWeight: Int = 100 {
        didSet {
            UserDefaults.standard.set(highInfectiousnessWeight, forKey: Self.highInfectiousnessWeightKey)
        }
    }

    @Published var daysRollup: Int = 7 {
        didSet {
            UserDefaults.standard.set(daysRollup, forKey: Self.daysRollupKey)
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

    // Note: in local time zone
    @Published var startDate: Date = defaultStart {
        didSet {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .full
            print("Setting start date to \(dateFormatter.string(from: startDate))")
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

    let testEncvKey: String
    let testEnpaKey: String

    let disableTestServer: Bool

    @MainActor var usingTestData: Bool {
        get {
            isUsingTestData
        }
        set(newValue) {
            clear()
            if newValue {
                region = "US-EV"
                encvKey = testEncvKey
                enpaKey = testEnpaKey
                useTestServers = true
                notifications = 1
                daysRollup = 7
                startDate = defaultStart
                useTestServers = true
            }
        }
    }

    var isUsingTestData: Bool {
        useTestServers && encvKey == testEncvKey && enpaKey == testEnpaKey && testEncvKey != ""
    }

    @MainActor func clear() {
        region = ""
        encvKey = ""
        enpaKey = ""
        startDate = defaultStart
        configStartDate = nil // defaultStart
        notifications = 1
        daysRollup = 7
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
        daysRollup = 7
        region = "US-EV"
        if let testConfig = getTestServers() {
            testEncvKey = testConfig["testEncvKey"] as! String
            testEnpaKey = testConfig["testEnpaKey"] as! String
            disableTestServer = false
        } else {
            testEncvKey = ""
            testEnpaKey = ""
            disableTestServer = true
        }
        encvKey = testEncvKey
        enpaKey = testEnpaKey
        startDate = defaultStart
        configStartDate = nil
    }

    override init() {
        let faceid = UserDefaults.standard.bool(forKey: Self.faceIDKey)
        useFaceID = faceid
        if let data = UserDefaults.standard.string(forKey: Self.regionKey) {
            region = data
        }
        let baseline = UserDefaults.standard.double(forKey: Self.baselineExposureKey)
        durationBaselineMinutes = baseline == 0.0 ? 15.0 : baseline

        let hiw = UserDefaults.standard.integer(forKey: Self.highInfectiousnessWeightKey)
        highInfectiousnessWeight = hiw == 0 ? 100 : hiw

        notifications = max(1, UserDefaults.standard.integer(forKey: Self.notificationsKey))

        alertDismissed = UserDefaults.standard.bool(forKey: Self.alertKey)

        let dr = UserDefaults.standard.integer(forKey: Self.daysRollupKey)
        daysRollup = dr == 0 ? 7 : dr

        debuggingFeatures = UserDefaults.standard.bool(forKey: Self.debuggingKey)
        if let data = UserDefaults.standard.string(forKey: Self.encvKeyKey) {
            encvKey = data
        }
        if let data = UserDefaults.standard.string(forKey: Self.enpaKeyKey) {
            enpaKey = data
        }
        if let testConfig = getTestServers() {
            testEncvKey = testConfig["testEncvKey"] as! String
            testEnpaKey = testConfig["testEnpaKey"] as! String
            disableTestServer = false
        } else {
            testEncvKey = ""
            testEnpaKey = ""
            disableTestServer = true
        }

        startDate = dateFor(key: Self.startKey)
        configStartDate = nil // dateFor(key: Self.configStartKey)
        let uTestServers = UserDefaults.standard.bool(forKey: Self.testServerKey)
        useTestServers = uTestServers
        if disableTestServer, uTestServers {
            region = ""
            encvKey = ""
            enpaKey = ""
            useTestServers = false
        } else {
            useTestServers = uTestServers
        }
    }
}
