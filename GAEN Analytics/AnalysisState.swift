//
//  AnalysisState.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation
@_predatesConcurrency import TabularData
import UIKit

@MainActor
class AnalysisState: NSObject, ObservableObject {
    static let shared = AnalysisState()
    var region: String {
        if let region = config?.region {
            return region
        }
        return ""
    }

    @Published var enpaDate: Date? = nil
    @Published var encvDate: Date? = nil
    @Published var enpaAvailable: Bool = false
    @Published var encvAvailable: Bool = false

    @Published var config: Configuration? = nil
    @Published var status: String = "Fetch analytics"
    @Published var inProgress: Bool = false
    @Published var available: Bool = false
    @Published var iOSENPA: DataFrame?
    @Published var AndroidENPA: DataFrame?
    @Published var combinedENPA: DataFrame?
    @Published var encvComposite: DataFrame?
    @Published var rollingAvg: DataFrame?
    @Published var enpaCharts: [ChartOptions] = []
    @Published var encvCharts: [ChartOptions] = []
    @Published var enpaSummary: String = ""
    @Published var encvSummary: String = ""
    @Published var csvExport: CSVFile? = nil
    @Published var csvExportReady = false

    func export(csvFile: CSVFile) {
        print("exporting \(csvFile.name)")
        csvExport = csvFile
        csvExportReady = true
    }

    static func exportToURL(name: String, dataframe: DataFrameProtocol) -> URL? {
        do {
            let writingOptions = CSVWritingOptions(dateFormat: "yyyy-MM-dd")

            let csv = try dataframe.csvRepresentation(options: writingOptions)

            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
            let n = name.replacingOccurrences(of: "/", with: "%2F")

            guard let path = documents?.appendingPathComponent(n) else {
                print("could not get path")
                return nil
            }

            try csv.write(to: path, options: .atomicWrite)
            return path
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }

    static func exportToFileDocument(name: String, dataframe: DataFrameProtocol) -> CSVFile? {
        do {
            let writingOptions = CSVWritingOptions(dateFormat: "yyyy-MM-dd")
            let csv = try dataframe.csvRepresentation(options: writingOptions)
            let string = String(data: csv, encoding: .utf8)

            return CSVFile(name: name, csv)

        } catch {
            print(error.localizedDescription)
            return nil
        }
    }

    func start(config: Configuration) {
        self.config = config
        inProgress = true
        available = false
        enpaSummary = ""
        encvSummary = ""
        enpaCharts = []
        encvCharts = []
    }

    func finish() {
        inProgress = false
        available = true
        status = "Update analytics"
    }

    func gotENCV(composite: DataFrame?) {
        encvComposite = composite
    }

    func gotRollingAvg(rollingAvg: DataFrame?) {
        self.rollingAvg = rollingAvg
        makeENCVCharts()
        encvAvailable = true
        encvDate = Date()
    }

    func log(enpa: [String]) {
        if !enpaSummary.isEmpty {
            enpaSummary.append("\n")
        }
        let joined = enpa.joined(separator: "\n")
        print("log enpa:")
        print(joined)
        enpaSummary.append(joined)
    }

    func log(encv: [String]) {
        if !encvSummary.isEmpty {
            encvSummary.append("\n")
        }
        let joined = encv.joined(separator: "\n")
        print("log encv:")
        print(joined)
        encvSummary.append(joined)
    }

    func analyzedENPA(ios: DataFrame, android: DataFrame, combined: DataFrame) {
        iOSENPA = ios
        AndroidENPA = android
        combinedENPA = combined
        encvDate = Date()
        makeENPACharts()
        enpaAvailable = true
    }

    func update(encv: String? = nil, enpa: String? = nil) {
        if let encv = encv {
            status = encv
            encvDate = Date()
        }
        if let enpa = enpa {
            status = enpa
            encvDate = Date()
        }
    }

    func makeENPACharts() {
        if let enpa = combinedENPA, let config = config {
            print("enpa columns: ")
            print("\(enpa.columns.count) enpa Columns: \(enpa.columns.map(\.name))")
            enpaCharts =
                Array(
                    [
                        notificationsPerUpload(enpa: enpa, config: config),
                        notificationsPer100K(enpa: enpa, config: config),
                        arrivingPromptly(enpa: enpa, config: config),
                        estimatedUsers(enpa: enpa, config: config),
                        enpaOptIn(enpa: enpa, config: config),
                    ].compacted())
        } else {
            enpaCharts = []
        }
    }

    func makeENCVCharts() {
        if let encv = rollingAvg, let config = config {
            if false {
                print("\(encv.columns.count) enpa Columns: \(encv.columns.map(\.name))")
            }
            let hasUserReports = encv.indexOfColumn("user_report_claim_rate") != nil

            let hasSMSerrors = encv.indexOfColumn("sms_error_rate") != nil
            encvCharts =
                Array(
                    [
                        claimedConsent(encv: encv, hasUserReports: hasUserReports, config: config),
                        userReportRate(encv: encv, hasUserReports: hasUserReports, config: config),
                        tokensClaimed(encv: encv, hasUserReports: hasUserReports, config: config),
                        // publishRequests(encv: encv, config: config),
                        systemHealth(encv: encv, hasSMS: hasSMSerrors, config: config),
                    ].compacted())
            if hasUserReports {}
        } else {
            encvCharts = []
        }
    }
}

func computeEstimatedDevices(_ codesClaimed: Int?, _ cv: Double?) -> Int? {
    guard let codesClaimed = codesClaimed, let cv = cv else {
        return nil
    }
    return Int((Double(codesClaimed * 100_000) / cv).rounded())
}

actor AnalysisTask {
    func analyzeENPA(config: Configuration, encvAverage: DataFrame?, result: AnalysisState) async {
        await result.update(enpa: "fetching enpa")
        do {
            var raw = RawMetrics(config)
            let readThese = ["userRisk",
                             "notification",
                             "notificationInteractions",
                             "codeVerified",
                             "keysUploaded",
                             "dateExposure"]
            for m in readThese {
                await result.update(enpa: "fetching \(m)")
                if let error = raw.addMetric(names: [m]) {
                    await result.log(enpa: [error])
                    return
                }
            }

            let metrics = raw.metrics

            let iOSDataFrame = try getRollingAverageIOSMetrics(metrics, options: config)
            let androidDataFrame = try getRollingAverageAndroidMetrics(metrics, options: config)
            let combinedDataFramePlain = try getRollingAverageKeyMetrics(metrics, options: config)
            let combinedDataFrame: DataFrame
            if let encv = encvAverage {
                let codes_claimed = encv.selecting(columnNames: ["date", "codes claimed"])
                var joined = combinedDataFramePlain.joined(codes_claimed, on: "date", kind: .left)
                // print("\(joined.columns.count)  Columns in join: \(joined.columns.map(\.name))")
                joined.removeJoinNames()
                // print("\(joined.columns.count)  Columns in join: \(joined.columns.map(\.name))")
                let codesClaimed = joined["codes claimed", Int.self]
                let vc = joined["vc", Double.self]
                let result = zip(codesClaimed, vc).map { computeEstimatedDevices($0.0, $0.1) }
                joined.append(column: Column(name: "est users", contents: result))
                joined.addColumnPercentage("vc count", "est users", giving: "ENPA %")
                combinedDataFrame = joined
            } else {
                combinedDataFrame = combinedDataFramePlain
            }
            await result.analyzedENPA(ios: iOSDataFrame, android: androidDataFrame, combined: combinedDataFrame)
            let combined = summarize("combined", combinedDataFrame, categories: config.numCategories)
            let iOS = summarize("iOS", iOSDataFrame, categories: config.numCategories)
            let android = summarize("Android", androidDataFrame, categories: config.numCategories)
            let all = combined + iOS + android
            await result.log(enpa: all)

        } catch {
            await result.log(enpa: ["\(error)"])
        }
    }

    func analyzeENCV(config: Configuration, result: AnalysisState) async -> ENCVAnalysis {
        if !config.hasENCV {
            return ENCVAnalysis(encv: nil, average: nil, log: ["Skipping ENCV"])
        }
        guard let
            encvAPIKey = config.encvAPIKey, !encvAPIKey.isEmpty,
            let composite = getENCVDataFrame("composite.csv", apiKey: encvAPIKey, useTestServers: config.useTestServers)
        else {
            return ENCVAnalysis(encv: nil, average: nil, log: ["Failed to get ENCV composite.csv"])
        }

        let smsData: DataFrame? = getENCVDataFrame("sms-errors.csv", apiKey: config.encvAPIKey!, useTestServers: config.useTestServers)

        let analysis = GAEN_Analytics.analyzeENCV(composite: composite, smsData: smsData)
        await result.gotENCV(composite: analysis.encv)
        await result.gotRollingAvg(rollingAvg: analysis.average)
        await result.log(encv: analysis.log)
        return analysis
    }

    func analyze(config: Configuration, result: AnalysisState) async {
        print("Starting analysis")
        await result.start(config: config)
        let encv: ENCVAnalysis?
        if config.hasENCV {
            print("Starting analyzeENCV")
            encv = await analyzeENCV(config: config, result: result)
            print("Finished analyzeENCV")
        } else {
            encv = nil
            await result.log(encv: ["Skipping ENCV"])
        }
        if config.hasENPA {
            print("Starting analyzeENPA")
            await analyzeENPA(config: config, encvAverage: encv?.average, result: result)
            print("Finished analyzeENPA")
        } else {
            await result.log(enpa: ["Skipping ENPA"])
        }

        await result.finish()
    }
}
