//
//  AnalysisState.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation
import os.log
import TabularData
import UniformTypeIdentifiers
import ZIPFoundation

private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "AnalyzeState")

private let logExports = false

@MainActor
class AnalysisState: NSObject, ObservableObject {
    static let shared = AnalysisState()
    var region: String {
        if let region = config?.region {
            return region
        }
        return SetupState.shared.region
    }

    @Published var enpaDate: Date? = nil
    @Published var encvDate: Date? = nil
    @Published var enpaAvailable: Bool = false
    @Published var encvAvailable: Bool = false
    @Published var config: Configuration? = nil
    @Published var status: String = "Fetch analytics"
    @Published var nextAction: String = "Fetch analytics"
    @Published var inProgress: Bool = false
    var progressSteps: Double = 0.0
    @Published var progress: Double = 0.0
    @Published var enpaArchiveCount: Int = 0
    var progressCount: Double {
        let enpaCount: Int
        if SetupState.shared.useArchivalData {
            enpaCount = 11 + 5
        } else {
            enpaCount = standardMetrics.count + additionalMetrics.count + 5
        }
        return Double(enpaCount + 3)
    }

    @Published var available: Bool = false {
        didSet {
            print("available changed to \(available)")
        }
    }

    @Published var availableAt: Date?
    var availableAtMessage: String {
        guard let availableAt = availableAt else {
            return "Not available"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: availableAt)
    }

    @Published var rawENPA: RawMetrics?
    @Published var iOSENPA: DataFrame?
    @Published var AndroidENPA: DataFrame?
    @Published var combinedENPA: DataFrame?
    @Published var durationAnalysis: DataFrame?
    @Published var dateExposureAnalysis: DataFrame?
    // persisted
    @Published var encvComposite: DataFrame?
    @Published var smsErrors: DataFrame?

    @Published var worksheet: DataFrame?
    @Published var rollingAvg: DataFrame?
    @Published var enpaCharts: [ChartOptions] = []
    @Published var appendixCharts: [ChartOptions] = []
    @Published var appendixENPACharts: [ChartOptions] = []

    @Published var encvCharts: [ChartOptions] = []
    @Published var enpaSummary: String = ""
    @Published var encvSummary: String = ""
    @Published var csvExport: CSVFile? = nil
    @Published var csvExportReady = false
    @Published var additionalMetrics: Set<String> = []
    @Published var durationSummary: String? = nil

    func metricSelected(_ name: String) -> Bool {
        additionalMetrics.contains(name)
    }

    func toggleMetric(_ name: String) {
        if metricSelected(name) {
            additionalMetrics.remove(name)
        } else {
            additionalMetrics.insert(name)
            rawENPA = nil
        }
        print("additional metrics: \(additionalMetrics)")
    }

    func export(csvFile: CSVFile) {
        if logExports {
            logger.log("exporting \(csvFile.name, privacy: .public)")
        }
        csvExport = csvFile
        csvExportReady = true
    }

    static func exportToURL(csvFile: CSVFile) -> URL? {
        if logExports {
            logger.log("exporting \(csvFile.name, privacy: .public)")
        }
        do {
            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)

            let n = csvFile.name.replacingOccurrences(of: "/", with: "%2F")

            let path = temporaryDirectoryURL.appendingPathComponent(n)

            try csvFile.data.write(to: path, options: .atomicWrite)
            return path
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func exportToURL(name: String, dataframe: DataFrame) -> URL? {
        if logExports {
            logger.log("Exporting \(name, privacy: .public) to URL")
        }
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)
            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)

            let n = name.replacingOccurrences(of: "/", with: "%2F")

            let path = temporaryDirectoryURL.appendingPathComponent(n)

            try csv.write(to: path, options: .atomicWrite)
            // logger.log("Exported \(name, privacy: .public) to URL")
            return path
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func exportToURL(name: String, dataframe: DataFrame.Slice) -> URL? {
        if logExports {
            logger.log("Exporting \(name, privacy: .public) to URL")
        }
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)

            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)

            let n = name.replacingOccurrences(of: "/", with: "%2F")

            let path = temporaryDirectoryURL.appendingPathComponent(n)

            try csv.write(to: path, options: .atomicWrite)
            // logger.log("Exported \(name, privacy: .public) to URL")
            return path
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func deleteComposite() {
        encvComposite = nil
        logger.log("Deleting composite")
        do {
            guard let url = urlForComposite else {
                return
            }
            let path = url.path
            let fileManager = FileManager.default

            // Check if file exists
            if fileManager.fileExists(atPath: path) {
                // Delete file
                try fileManager.removeItem(atPath: path)
            }
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    var urlForComposite: URL? {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        guard let path = documents?.appendingPathComponent("composite.csv") else {
            logger.error("Could not get path")
            return nil
        }
        return path
    }

    func loadComposite() {
        guard let url = urlForComposite, FileManager.default.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else {
            return
        }
        do {
            let composite = try DataFrame(csvData: data, options: readingOptions)
            logger.log("Loaded composite, got \(composite.rows.count, privacy: .public) rows")
            encvComposite = composite
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    func loadComposite(_ url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                logger.error("No permission to access \(url)")

                return
            }
            guard FileManager.default.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url)
            else {
                url.stopAccessingSecurityScopedResource()
                logger.error("Could access \(url)")
                return
            }
            url.stopAccessingSecurityScopedResource()
            let composite = try DataFrame(csvData: data, options: readingOptions)
            logger.log("Loaded composite, got \(composite.rows.count, privacy: .public) rows")
            encvComposite = composite
            saveComposite()
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    static let writingOptions = CSVWritingOptions(dateFormat: "yyyy-MM-dd")
    func saveComposite() {
        guard let encvComposite = encvComposite else {
            return
        }
        do {
            let csv = try encvComposite.csvRepresentation(options: AnalysisState.writingOptions)

            guard let path = urlForComposite else {
                return
            }
            try csv.write(to: path, options: .atomicWrite)
            if encvComposite.requireColumn("date", Date.self) {
                let dates = encvComposite["date", Date.self]
                print("wrote composites to \(path), first date \(dateFormatter.string(from: dates.first!!))")
            }

        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    static func exportToFileDocument(name: String, dataframe: DataFrame) -> CSVFile? {
        if logExports {
            logger.log("Exporting \(name, privacy: .public) to File")
        }
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)

            return CSVFile(name: name, csv: csv)

        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func exportToFileDocument(name: String, dataframe: DataFrame.Slice) -> CSVFile? {
        if logExports {
            logger.log("Exporting \(name, privacy: .public) to File")
        }
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)

            return CSVFile(name: name, csv: csv)

        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func clear() {
        config = nil
        available = false
        enpaSummary = ""
        encvSummary = ""
        enpaCharts = []
        encvCharts = []
        appendixENPACharts = []
        appendixCharts = []
        rawENPA = nil
        iOSENPA = nil
        AndroidENPA = nil
        combinedENPA = nil
        durationAnalysis = nil
        dateExposureAnalysis = nil
        durationSummary = nil
        encvComposite = nil
        worksheet = nil
        rollingAvg = nil
        deleteComposite()
        encvComposite = nil
        status = "Fetch analytics"
        nextAction = "Fetch analytics"
    }

    func start(config: Configuration) {
        print("starting")
        self.config = config

        progress = 0.0
        progressSteps = 0
        available = false

        enpaSummary = "waiting for ENPA data..."
        encvSummary = "waiting for ENCV data..."
        nextAction = "Getting analytics"
        enpaCharts = []
        encvCharts = []
        appendixENPACharts = []
        appendixCharts = []
        durationSummary = nil
        inProgress = true
    }

    func finish() {
        inProgress = false
        progress = 1.0
        available = true
        availableAt = Date()
        status = "Update analytics"
        nextAction = "Update analytics"
    }

    func gotENCV(composite: DataFrame?, smsErrors: DataFrame?) {
        encvComposite = composite
        saveComposite()
        self.smsErrors = smsErrors
    }

    func gotRollingAvg(rollingAvg: DataFrame?) {
        self.rollingAvg = rollingAvg
        makeENCVCharts()
        print("made encv charts")
        encvAvailable = true
        encvDate = Date()
    }

    func log(enpa: [String]) {
        if !enpaSummary.isEmpty {
            enpaSummary.append("\n")
        }
        let joined = enpa.joined(separator: "\n")

        enpaSummary.append(joined)
    }

    func log(encv: [String]) {
        if !encvSummary.isEmpty {
            encvSummary.append("\n")
        }
        let joined = encv.joined(separator: "\n")

        encvSummary.append(joined)
    }

    func analyzedENPA(config: Configuration, raw: RawMetrics, ios: DataFrame, android: DataFrame?, combined: DataFrame, worksheet: DataFrame?, durationAnalysis: DataFrame?, dateExposureAnalysis: DataFrame?) {
        rawENPA = raw
        iOSENPA = ios
        AndroidENPA = android
        combinedENPA = combined
        self.worksheet = worksheet
        self.durationAnalysis = durationAnalysis
        self.dateExposureAnalysis = dateExposureAnalysis
        if let da = durationAnalysis {
            durationSummary = summarizeDurations(da, baselineDuration: config.durationBaselineMinutes).joined(separator: "\n")
        }

        encvDate = Date()
        makeENPACharts()
        enpaAvailable = true
    }

    func update(encv: String? = nil, enpa: String? = nil) {
        progressSteps = progressSteps + 1
        progress = min(progressSteps / progressCount, 1.0)

        if progressSteps > progressCount {
            print("Progress count is too small; \(progressSteps) > \(progressCount)")
        }
        if let encv = encv {
            encvDate = Date()
            status = encv
            print("PS #\(progressSteps) \(progress): \(encv)")
            logger.log("encv: \(encv, privacy: .public)")
        }
        if let enpa = enpa {
            encvDate = Date()
            status = enpa
            print("PS #\(progressSteps) \(progress): \(enpa)")
            logger.log("enpa: \(enpa, privacy: .public)")
        }
    }

    func makeENPACharts() {
        if let enpa = combinedENPA, let config = config {
            let maybeCharts: [ChartOptions?] = [
                notificationsPer100K(enpa: enpa, config: config),
                notificationsShare(enpa: enpa, config: config),
                notificationsPerUpload(enpa: enpa, config: config),
            ]
                + (1 ... config.numCategories).map { secondaryAttackRateSpread(enpa: enpa, config: config, notification: $0) }
                + [
                    arrivingPromptly(enpa: enpa, config: config),
                    averageDaysUntilNotification(enpa: enpa, config: config),

                    daysUntilNotification(dateExposureAnalysis: dateExposureAnalysis, config: config),

                    detectedEncounterGraph(enpa: enpa, config: config),

                    estimatedUsers(enpa: enpa, config: config),
                    enpaOptIn(enpa: enpa, config: config),
                    scaledNotifications(enpa: enpa, config: config),
                ]

            enpaCharts = maybeCharts.compactMap { $0 }
            let maybeAppendixENPACharts: [ChartOptions?] = [showingNotifications(enpa: enpa, config: config),
                                                            relativeRisk(enpa: enpa, config: config),
                                                            hadNotificationsWhenPositive(enpa: enpa, config: config),
                                                            weightedDurationGraph(enpa: enpa, config: config),
                                                            sumScoreGraph(enpa: enpa, config: config),
                                                            maxScoreGraph(enpa: enpa, config: config),
                                                            attenuationsGraph(enpa: enpa, config: config),
                                                            deviceAttenuations(worksheet: worksheet),
                                                            beaconsGraph(worksheet: worksheet, suffix: "typical", config: config),
                                                            beaconsGraph(worksheet: worksheet, suffix: "unbusy", config: config),
                                                            beaconsGraph(worksheet: worksheet, suffix: "busy", config: config)]
                + ((1 ... config.numCategories).map { dateExposure14(enpa: enpa, config: config, notification: $0) })
                + ((1 ... config.numCategories).map { excessSecondaryAttackRateSpread(enpa: enpa, config: config, notification: $0) })

            appendixENPACharts = maybeAppendixENPACharts.compactMap { $0 }

        } else {
            enpaCharts = []
            appendixENPACharts = []
        }
    }

    func makeENCVCharts() {
        if let encv = rollingAvg, let config = config {
            let hasUserReports = encv.indexOfColumn("user reports claim rate") != nil

            let hasSMSerrors = encv.indexOfColumn("sms error rate") != nil
            if false {
                print("\(encv.columns.count) encv Columns: \(encv.columns.map(\.name))")
                if hasUserReports {
                    print("has user reports")
                }
                if hasSMSerrors {
                    print("has SMS errors")
                }
            }
            let temp = [
                claimedConsent(encv: encv, hasUserReports: hasUserReports, config: config),
                userReportRate(encv: encv, hasUserReports: hasUserReports, config: config),
                tokensClaimed(encv: encv, hasUserReports: hasUserReports, config: config),
                systemHealth(encv: encv, hasSMS: hasSMSerrors, config: config),
                invalidCodes(encv: encv, config: config),
            ]
            encvCharts = temp.compactMap { $0 }
            print("Got \(encvCharts.count) envc charts")

            let tmp = [
                timeToClaimCodes(encv: encv, hasUserReports: hasUserReports, config: config),
                tekUploads(encv: encv, config: config),
                onsetToUpload(encv: encv, hasUserReports: hasUserReports, config: config),
                publishRequests(encv: encv, config: config),
            ]
            print("Got \(tmp.count) maybe envc appendix charts")
            appendixCharts = tmp.compactMap { $0 }
            print("Got \(appendixCharts.count) envc appendix charts")
        } else {
            encvCharts = []
            appendixCharts = []
        }
    }
}

func computeEstimatedDevices(_ codesClaimed: Int?, _ cvData: (Double?, Double?)) -> Int? {
    let (cv, cvstd) = cvData
    guard let codesClaimed = codesClaimed, let cv = cv, let cvstd = cvstd, cv >= 3.0 * cvstd else {
        return nil
    }
    return Int((Double(codesClaimed * 100_000) / cv).rounded())
}

func makeMap(_ encv: DataFrame, _ encvColumn: String) -> [Date: Int] {
    let dates = encv["date", Date.self]
    let codes_claimed = encv[encvColumn, Int.self]
    var map: [Date: Int] = [:]
    for (date, cc) in zip(dates, codes_claimed) {
        if let date = date {
            map[date] = cc
        }
    }
    return map
}

func computeEstimatedUsersFromNationalRollup(platform: String, enpa: DataFrame, _ enpaColumn: String)
    -> DataFrame
{
    var result = enpa
    let date = result["date", Date.self]
    let usOptin = date.map { getUSOptin(date: $0) }
    let c2 = Column(name: "US ENPA %", contents: usOptin)
    result.append(column: c2)
    result.addColumnDividing("\(enpaColumn) count", "US ENPA %", giving: "est \(platform)users using US ENPA %")
    return result
}

func computeEstimatedUsers(platform: String, encv: DataFrame, _ encvColumn: String, enpa: DataFrame, _ enpaColumn: String) -> DataFrame {
    logger.log("Computing \(platform, privacy: .public) est. users from \(encvColumn, privacy: .public) and \(enpaColumn, privacy: .public)")
    encv.checkUniqueColumnNames()
    enpa.checkUniqueColumnNames()
    guard
        encv.requireColumn("date", Date.self),
        encv.requireColumn(encvColumn, Int.self)
    else {
        return enpa
    }
    var result = enpa
    let newEncvColumn: Column<Int>
    if false {
        let map = makeMap(encv, encvColumn)
        logger.log("make map from encv data")
        let dates = enpa["date", Date.self]

        let encv_values = dates.map { map[$0!] }
        newEncvColumn = Column(name: encvColumn, contents: encv_values)
        result.append(column: newEncvColumn)
    } else {
        newEncvColumn = result.addColumn(encvColumn, Int.self, from: encv)
    }
    logger.log("added encv data to enpa data")

    let date = result["date", Date.self]
    let vc = result[enpaColumn, Double.self]
    let vcstd = result[enpaColumn + " std", Double.self]
    let estUsers = zip(newEncvColumn, zip(vc, vcstd)).map { computeEstimatedDevices($0.0, $0.1) }
    let estUsersColumnName = "est \(platform)users from \(enpaColumn)"
    logger.log("\(estUsersColumnName) computed")
    let c = Column(name: estUsersColumnName, contents: estUsers)
    result.append(column: c)
    result.addColumnPercentage("\(enpaColumn) count", estUsersColumnName, giving: "\(platform)\(enpaColumn) ENPA %")

    return result
}

func estimatedNotifications(nt: Double?, estUsers: Int?) -> Double? {
    if let nt = nt, let estUsers = estUsers {
        return nt / 100_000.0 * Double(estUsers)
    }
    return nil
}

let standardMetrics = ["userRisk", "riskParameters",
                       "notification",
                       "notificationInteractions",
                       "codeVerified",
                       "keysUploaded",
                       "beaconCount",
                       "dateExposure", "dateExposure14d", "codeVerifiedWithReportType14d", "keysUploadedWithReportType14d", "secondaryAttack14d",
                       // "periodicExposureNotification14d"
]
actor AnalysisTask {
    
    func getNestedJson(zipData: Data) -> (String, NSDictionary)? {
        guard let nestedArchive = Archive(data: zipData, accessMode: .read) else {
            return nil
        }
        do {
            for entry in nestedArchive {
                let url = URL(fileURLWithPath: entry.path)
                let name = url.lastPathComponent
                var nestedData = Data()
                try nestedArchive.extract(entry, bufferSize: 200_000_000, consumer: { (dataChunk) in
                    nestedData.append(dataChunk)
                })
                if let json = try? JSONSerialization.jsonObject(with: nestedData, options: []) as? NSDictionary {
                    return (name, json)
                }
            }
            return nil
        } catch {
            return nil
        }
    }
    
    func loadENPAArchive(config: Configuration, _ url: URL, result: AnalysisState) async -> RawMetrics? {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                await result.update(enpa: "No permission to access \(url)")
                logger.error("No permission to access \(url)")

                return nil
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                url.stopAccessingSecurityScopedResource()
                await result.update(enpa: "Could access \(url)")
                logger.error("Could access \(url)")
                return nil
            }
            var rawENPA = RawMetrics(config)

            guard let archive = Archive(url: url, accessMode: .read) else {
                return nil
            }
            await result.start(config: config)
            for file in archive {
                let url = URL(fileURLWithPath: file.path)
                let name = url.lastPathComponent
                if file.type != .file{
                    continue
                }
                
                try _ = archive.extract(file, bufferSize: 200_000_000) { data in
                    if name.hasSuffix(".json") {
                        if data.count < 200_000_000, let json = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary {
                            print("Got json for \(name), \(data.count)")
                            Task { await result.update(enpa: "loading \(name)") }
                            if let rawData = json["rawData"] as? [NSDictionary] {
                                for m in rawData {
                                    rawENPA.processRaw(name, m)
                                }
                            }
                            
                        } else {
                            Task {
                                await result.log(enpa: ["Couldn't get json for \(name), \(data.count) bytes"])
                            }
                        }
                    } else if name.hasSuffix("-raw-json.zip"), let (name, json) = getNestedJson(zipData: data) {
                        if let rawData = json["rawData"] as? [NSDictionary] {
                            for m in rawData {
                                rawENPA.processRaw(name, m)
                            }
                        }
                    } // -raw-json.zip
                } //extract
            } //for file in archive

            // rawENPA.load(url, result: self)

            url.stopAccessingSecurityScopedResource()
            await result.log(enpa: ["loaded ENPA archive"])
            return rawENPA

        } catch {
            await result.log(enpa: ["error \(error.localizedDescription)"])
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func fetchENPA(config: Configuration, result: AnalysisState) async -> RawMetrics? {
        var raw = RawMetrics(config)

        for m in standardMetrics {
            await result.update(enpa: "fetching ENPA \(m)")
            let errors = raw.addMetric(m)
            if !errors.isEmpty {
                await result.log(enpa: errors)
                return nil
            }
        } // for m
        if false {
            let additional = await result.additionalMetrics
            for m in additional {
                await result.update(enpa: "fetching ENPA \(m)")
                let errors = raw.addMetric(m)
                if !errors.isEmpty {
                    await result.log(enpa: errors)
                }
            } // for m
        }
        return raw
    }

    func getAndAnalyzeENPA(config: Configuration, enpa: RawMetrics, encvAverage: DataFrame?, result: AnalysisState) async {
        do {
            let metrics = enpa.metrics
            await result.update(enpa: "Analyzing iOS enpa")
            var iOSDataFrame = try getRollingAverageIOSMetrics(metrics, options: config)

            var androidDataFrame: DataFrame?
            var combinedDataFrame: DataFrame
            if MetricSet.hasAndroid(metrics) {
                await result.update(enpa: "Analyzing Android enpa")
                androidDataFrame = try getRollingAverageAndroidMetrics(metrics, options: config)
                await result.update(enpa: "Analyzing Combined enpa")
                combinedDataFrame = try getRollingAverageKeyMetrics(metrics, options: config)
            } else {
                await result.update(enpa: "Analyzing Combined enpa")
                combinedDataFrame = try getRollingAverageIOSMetrics(metrics, options: config)
            }
            await result.update(enpa: "Computing enpa worksheet")

            var worksheet: DataFrame
            combinedDataFrame = computeEstimatedUsersFromNationalRollup(platform: "", enpa: combinedDataFrame, "vc")
            combinedDataFrame.addColumnComputation("nt", "est users using US ENPA %", giving: "est scaled notifications/day", estimatedNotifications)
            combinedDataFrame.addRollingSumDouble("est scaled notifications/day", giving: "est total notifications")

            if let encv = encvAverage {
                combinedDataFrame = computeEstimatedUsers(platform: "", encv: encv, "codes claimed", enpa: combinedDataFrame, "vc")

                combinedDataFrame = computeEstimatedUsers(platform: "", encv: encv, "publish requests", enpa: combinedDataFrame, "ku")

                combinedDataFrame.addRollingMedianInt("est users from vc", giving: "median est users from regional ENPA %", days: 14)
                combinedDataFrame.addRollingMedianDouble("vc ENPA %", giving: "regional ENPA %", days: 14)

                combinedDataFrame.addColumnComputation("nt", "median est users from regional ENPA %", giving: "est scaled notifications/day from regional ENPA %", estimatedNotifications)

                combinedDataFrame.addRollingSumDouble("est scaled notifications/day from regional ENPA %", giving: "est total notifications from regional ENPA %")

                iOSDataFrame = computeEstimatedUsers(platform: "iOS ", encv: encv, "publish requests ios", enpa: iOSDataFrame, "ku")
                if let tmp = androidDataFrame {
                    androidDataFrame = computeEstimatedUsers(platform: "Android ", encv: encv, "publish requests android", enpa: tmp, "ku")
                }
                combinedDataFrame.requireColumns("date", "vc count", "vc", "ku", "nt", "est users from vc", "vc ENPA %")
                combinedDataFrame.requireColumns("est users from ku", "ku ENPA %")
                worksheet = combinedDataFrame.selecting(columnNames: "date", "vc count", "vc", "ku", "nt", "codes claimed", "est users from vc", "vc ENPA %", "est users from ku", "ku ENPA %")

                worksheet.addColumn("codes issued", Int.self, from: encv)
                worksheet.addColumn("tokens claimed", Int.self, from: encv)
                worksheet.addColumn("publish requests", Int.self, from: encv)
                worksheet.addColumn("publish failure rate", Double.self, from: encv)

            } else {
                worksheet = combinedDataFrame.selecting(columnNames: "date", "vc count", "vc", "ku", "nt")
            }

            worksheet.renameColumn("vc count", to: "enpa users")
            worksheet.addColumn("vc count", Int.self, newName: "iOS enpa users", from: iOSDataFrame)
            worksheet.addColumn("vc", Double.self, newName: "iOS vc", from: iOSDataFrame)
            worksheet.addColumn("ku", Double.self, newName: "iOS ku", from: iOSDataFrame)
            worksheet.addColumn("nt", Double.self, newName: "iOS nt", from: iOSDataFrame)
            worksheet.addOptionalColumn("publish requests ios", Int.self, from: iOSDataFrame)
            worksheet.addOptionalColumn("est iOS users from ku", Int.self, from: iOSDataFrame)
            worksheet.addOptionalColumn("iOS ku ENPA %", Double.self, from: iOSDataFrame)
            worksheet.addOptionalColumn("publish requests ios", Int.self, from: encvAverage)

            if let androidDataFrame = androidDataFrame {
                worksheet.addColumn("vc count", Int.self, newName: "android enpa users", from: androidDataFrame)
                worksheet.addColumn("vc", Double.self, newName: "android vc", from: androidDataFrame)
                worksheet.addColumn("ku", Double.self, newName: "android ku", from: androidDataFrame)
                worksheet.addColumn("nt", Double.self, newName: "android nt", from: androidDataFrame)
                worksheet.addOptionalColumn("publish requests android", Int.self, from: androidDataFrame)
                worksheet.addOptionalColumn("est Android users from ku", Int.self, from: androidDataFrame)
                worksheet.addOptionalColumn("Android ku ENPA %", Double.self, from: androidDataFrame)
            }

            worksheet.addOptionalColumn("publish requests android", Int.self, from: encvAverage)
            worksheet.addOptionalColumn("android publish share", Double.self, from: encvAverage)
            if true {
                for db in [60, 70, 75] {
                    if let androidDataFrame = androidDataFrame {
                        worksheet.addColumn("<= \(db) dB %", Double.self, newName: "Android <= \(db) dB %", from: androidDataFrame)
                    }
                    let iOS_db = db + 5
                    worksheet.addColumn("<= \(iOS_db) dB %", Double.self, newName: "iOS <= \(iOS_db) dB %", from: iOSDataFrame)
                }

                worksheet.addColumn("<= 65 dB %", Double.self, newName: "iOS <= 65 dB %", from: iOSDataFrame)

                worksheet.addColumn("<= 75 dB %", Double.self, newName: "iOS <= 75 dB %", from: iOSDataFrame)
                if let androidDataFrame = androidDataFrame {
                    worksheet.addColumn("<= 70 dB %", Double.self, newName: "Android <= 70 dB %", from: androidDataFrame)

                    worksheet.addColumn("<= 80 dB %", Double.self, newName: "Android <= 80 dB %", from: androidDataFrame)
                }
            }
            if let beaconCountAnalysis = analyzeBeaconCounts(config: config, metrics) {
                worksheet.addAllColumns(type: Double.self, from: beaconCountAnalysis)
                worksheet.printColumnNames()
            }
            await result.update(enpa: "Computing enpa duration analysis")

            let durationAnalysis = try? computeDurationSummary(combinedDataFrame.rows[combinedDataFrame.rows.count - 2], highInfectiousnessWeight: config.highInfectiousnessWeight)
            logger.log("completed computeDurationSummary")
            let dateExposureAnalysis = try? computeDateExposureCurves(combinedDataFrame.rows[combinedDataFrame.rows.count - 2], categories: config.numCategories)
            logger.log("completed computeDateExposureCurves")
            await result.analyzedENPA(config: config, raw: enpa, ios: iOSDataFrame, android: androidDataFrame, combined: combinedDataFrame, worksheet: worksheet,
                                      durationAnalysis: durationAnalysis, dateExposureAnalysis: dateExposureAnalysis)
            let combined = summarize("combined", combinedDataFrame, categories: config.numCategories)
            let iOS = summarize("iOS", iOSDataFrame, categories: config.numCategories)
            let android: [String]
            if let androidDataFrame = androidDataFrame {
                android = summarize("Android", androidDataFrame, categories: config.numCategories)
            } else {
                android = ["No Android ENPA data"]
            }
            let all = combined + iOS + android
            await result.log(enpa: all)

        } catch {
            print("\(error.localizedDescription)")
            await result.log(enpa: ["\(error.localizedDescription)"])
        }
    }

    func getAndAnalyzeENCV(config: Configuration, archivalData: Bool = false, existingComposite: DataFrame?, result: AnalysisState) async -> ENCVAnalysis {
        let composite: DataFrame
        let smsData: DataFrame?
        if archivalData {
            if let existingComposite = existingComposite {
                composite = existingComposite
                smsData = nil
            } else {
                return ENCVAnalysis(encv: nil, average: nil, log: ["Failed to get archival ENCV composite.csv"])
            }
        } else {
            if !config.hasENCV {
                return ENCVAnalysis(encv: nil, average: nil, log: ["no ENCV API key, Skipping ENCV"])
            }
            await result.update(encv: "Fetching enpa composite")
            guard let
                encvAPIKey = config.encvAPIKey, !encvAPIKey.isEmpty
            else {
                await result.log(encv: ["No ENCV API key"])
                logger.log("No ENCV API key")
                return ENCVAnalysis(encv: nil, average: nil, log: ["No ENCV API key"])
            }

            let (newComposite, message) = getENCVDataFrame("composite.csv", apiKey: encvAPIKey, useTestServers: config.useTestServers)
            if let newComposite = newComposite {
                if let existingComposite = existingComposite {
                    composite = existingComposite.merge(key: "date", Date.self, adding: newComposite)
                } else {
                    composite = newComposite
                }
                logger.log("Got ENCV composite.csv, requesting sms-errors.csv")

                await result.update(encv: "Fetching sms errors")

                let (df, status) = getENCVDataFrame("sms-errors.csv", apiKey: config.encvAPIKey!, useTestServers: config.useTestServers)
                smsData = df
            } else {
                // no new composite
                logger.log("\(message, privacy: .public)")
                await result.log(encv: [message])
                if let existingComposite = existingComposite {
                    await result.log(encv: ["Using just archived ENCV data"])
                    composite = existingComposite
                } else {
                    return ENCVAnalysis(encv: nil, average: nil, log: [message])
                }
                smsData = nil
            }
            

           
        }

        await result.update(encv: "Analyzing encv")
        let analysis = analyzeENCV(config: config, composite: composite, smsData: smsData)
        await result.log(encv: ["Analyzed encv"])
        await result.gotENCV(composite: composite, smsErrors: smsData)
        await result.log(encv: ["Computing encv rolling averages"])
        await result.gotRollingAvg(rollingAvg: analysis.average)
        await result.log(encv: ["Computed encv rolling averages"])
        await result.log(encv: analysis.log)
        print("Done with encv")
        return analysis
    }

    func crash() {
        logger.error("deliberate crash of GAEN analytics")
        let foo: String? = nil
        print("\(foo!.count)")
    }

    func analyze(config: Configuration, result: AnalysisState, archivalData: Bool = false,
                 analyzeENCV: Bool = true, analyzeENPA: Bool = true) async
    {
        let info = Bundle.main.infoDictionary!

        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let appVersion = info["CFBundleShortVersionString"] as? String ?? "unknown"

        logger.log("Starting analysis, GAEN Analytics version \(appVersion), build \(build)")

        let encv: ENCVAnalysis?
        let existingComposite = await result.encvComposite
        if analyzeENCV, config.hasENCV || archivalData {
            logger.log("Starting analyzeENCV")
            encv = await getAndAnalyzeENCV(config: config, archivalData: archivalData, existingComposite: existingComposite, result: result)
            logger.log("Finished analyzeENCV")
        } else {
            encv = nil
            logger.log("skipping ENCV")
            if config.hasENCV {
                await result.log(encv: ["no ENCV api key, Skipping ENCV"])
            } else {
                await result.log(encv: ["Skipping ENCV"])
            }
        }
        if analyzeENPA {
            if archivalData {
                if var enpa = await result.rawENPA {
                    enpa.configuration = config
                    await getAndAnalyzeENPA(config: config, enpa: enpa, encvAverage: encv?.average, result: result)
                } else {
                    await result.log(enpa: ["No archival ENPA data"])
                }
            } else if config.hasENPA {
                logger.log("Starting analyzeENPA")
                if let enpa = await fetchENPA(config: config, result: result) {
                    await getAndAnalyzeENPA(config: config, enpa: enpa, encvAverage: encv?.average, result: result)
                }
                logger.log("Finished analyzeENPA")
            } else {
                await result.log(enpa: ["Skipping ENPA \(analyzeENPA) \(config.hasENPA)"])
            }
        }

        await result.finish()
    }
}

struct ChartOptions: Identifiable {
    let title: String
    let data: DataFrame
    let columns: [String]
    let minBound: Double?
    let maxBound: Double?
    let doubleDouble: Bool
    var id: String {
        title
    }

    static func maybe(title: String, data: DataFrame, columns: [String], minBound: Double? = nil, maxBound: Double? = nil) -> ChartOptions? {
        var columnsFound: [String] = []
        for c in columns {
            if data.indexOfColumn(c) != nil, !data.isEmpty(column: c) {
                columnsFound.append(c)
            }
        }
        if columnsFound.isEmpty {
            logger.log("No columns for chart \(title, privacy: .public)")
            return nil
        }
        return ChartOptions(title: title, data: data, columns: columnsFound, minBound: minBound, maxBound: maxBound, doubleDouble: false)
    }

    init(title: String, data: DataFrame, columns: [String], minBound: Double? = nil, maxBound: Double? = nil, doubleDouble: Bool = false) {
        self.title = title
        // print("\(data.columns.count) data Columns: \(data.columns.map(\.name))")
        logger.log("Making chart \(title, privacy: .public)")

        for c in columns {
            // print("MakeChart,\(title),\(c)")
            if data.indexOfColumn(c) == nil {
                logger.error("Column \(c, privacy: .public) doesn't exist")
                data.printColumnNames()
            }
        }

        self.data = data.selecting(columnNames: ["date"] + columns)
        self.columns = columns
        self.minBound = minBound
        self.maxBound = maxBound
        self.doubleDouble = doubleDouble
    }

    init(title: String, data: DataFrame, xAxis: String, columns: [String]) {
        self.title = title
        // print("\(data.columns.count) data Columns: \(data.columns.map(\.name))")
        logger.log("Making chart \(title, privacy: .public)")
        for c in columns {
            // print("MakeChart,\(title),\(c)")
            if data.indexOfColumn(c) == nil {
                logger.error("Column \(c, privacy: .public) doesn't exist")
                data.printColumnNames()
            }
        }

        self.data = data.selecting(columnNames: [xAxis] + columns)
        self.columns = columns
        maxBound = nil
        minBound = nil
        doubleDouble = true
    }
}

func invalidCodes(encv: DataFrame, config _: Configuration) -> ChartOptions {
    let columns = ["invalid share", "ios invalid share", "ios invalid ratio", "android invalid ratio"]
    return ChartOptions(title: "Invalid code ratios", data: encv,
                        columns: columns, maxBound: 2.0)
}

func tekUploads(encv: DataFrame, config _: Configuration) -> ChartOptions {
    let columns = ["single key uploads", "publish requests without teks"]
    let result = ChartOptions(title: "unusual tek uploads", data: encv,
                              columns: columns, maxBound: 0.5)
    return result
}

func notificationsPerUpload(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns: [String]
    if config.numCategories == 1 {
        columns = ["nt/ku"]

    } else {
        columns = ["nt/ku"] + (1 ... config.numCategories).map { "nt\($0)/ku" }
    }
    return ChartOptions(title: "Notifications per key upload", data: enpa,
                        columns: columns,
                        maxBound: 50)
}

//   let aBHeader = "attn count, <= 50 dB %, <= 55 dB %, <= 60 dB %, <= 65 dB %, <= 70 dB %, <= 75 dB %, <= 80 dB %"
// let dBHeader = "dur count, dur std, > 10min %, > 20min %,> 30min %,> 50min %,> 70min %, > 90min %, > 120min %"

func attenuationsGraph(enpa: DataFrame, config _: Configuration) -> ChartOptions {
    let columns = ["<= 50 dB %", "<= 55 dB %", "<= 60 dB %", "<= 65 dB %", "<= 70 dB %", "<= 75 dB %", "<= 80 dB %"]

    return ChartOptions(title: "Attenuation distribution", data: enpa,
                        columns: columns,
                        maxBound: 1)
}

func beaconsGraph(worksheet: DataFrame?, suffix: String, config _: Configuration) -> ChartOptions? {
    guard let worksheet = worksheet else {
        return nil
    }
    let columns = (0 ... 4).map { "≥ \(beaconCountMin[$0]) beacons % \(suffix)" }

    return ChartOptions.maybe(title: "Beacon counts \(suffix)", data: worksheet,
                              columns: columns,
                              minBound: 1,
                              maxBound: 1)
}

func weightedDurationGraph(enpa: DataFrame, config _: Configuration) -> ChartOptions {
    let columns = ["wd > 10min %", "wd > 20min %", "wd > 30min %", "wd > 50min %", "wd > 70min %", "wd > 90min %", "wd > 120min %"]

    return ChartOptions(title: "Weighted duration distribution", data: enpa,
                        columns: columns,
                        maxBound: 1)
}

func detectedEncounterGraph(enpa: DataFrame, config _: Configuration) -> ChartOptions {
    ChartOptions(title: "Encounter detected in past 14 days", data: enpa,
                 columns: ["detected %"],
                 maxBound: 1)
}

func sumScoreGraph(enpa: DataFrame, config _: Configuration) -> ChartOptions {
    let columns = ["sum > 40min %", "sum > 50min %", "sum > 60min %", "sum > 70min %", "sum > 80min %", "sum > 90min %", "sum > 120min %"]

    return ChartOptions(title: "Sum score distribution", data: enpa,
                        columns: columns,
                        maxBound: 1)
}

func maxScoreGraph(enpa: DataFrame, config _: Configuration) -> ChartOptions {
    let columns = ["max > 7min %", "max > 11min %", "max > 15min %", "max > 19min %", "max > 23min %", "max > 27min %"]

    return ChartOptions(title: "Max score distribution", data: enpa,
                        columns: columns,
                        maxBound: 1)
}

func notificationsPer100K(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns: [String]
    if config.numCategories == 1 {
        columns = ["nt"]

    } else {
        columns = ["nt"] + (1 ... config.numCategories).map { "nt\($0)" }
    }
    return ChartOptions(title: "Notifications per 100K", data: enpa, columns: columns)
}

func notificationsShare(enpa: DataFrame, config: Configuration) -> ChartOptions? {
    if config.numCategories == 1 {
        return nil
    }

    let columns = (1 ... config.numCategories).map { "nt\($0)%" }

    return ChartOptions(title: "Notification share", data: enpa, columns: columns, maxBound: 1.0)
}

func secondaryAttackRate(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns = Array((1 ... config.numCategories).map { ["sar\($0)%", "sar\($0) stdev%"] }.joined())

    return ChartOptions(title: "Secondary attack rate", data: enpa, columns: columns, maxBound: 0.2)
}

func secondaryAttackRateSpread(enpa: DataFrame, config _: Configuration, notification: Int) -> ChartOptions? {
    let sar = "sar\(notification)%"
    let stdev = "sar\(notification)% stdev"
    let sarplus = "+1 stdev"
    let sarminus = "-1 stdev"

    if enpa.isEmpty(column: sar) {
        return nil
    }
    var data = enpa.selecting(columnNames: ["date", sar, stdev])
    guard data.addColumnSumDouble(sar, stdev, giving: sarplus),
          data.addColumnDifferenceDouble(sar, stdev, giving: sarminus)
    else {
        return nil
    }
    // data.printColumnNames()
    return ChartOptions(title: "Secondary attack rate \(notification)", data: data, columns: [sar, sarplus, sarminus])
}

func excessSecondaryAttackRateSpread(enpa: DataFrame, config _: Configuration, notification: Int) -> ChartOptions? {
    let sar = "xsar\(notification)%"
    let stdev = "sar\(notification)% stdev"
    let sarplus = "+1 stdev"
    let sarminus = "-1 stdev"
    if enpa.isEmpty(column: sar) {
        return nil
    }
    var data = enpa.selecting(columnNames: ["date", sar, stdev])
    guard data.addColumnSumDouble(sar, stdev, giving: sarplus),
          data.addColumnDifferenceDouble(sar, stdev, giving: sarminus)
    else {
        return nil
    }
    // data.printColumnNames()
    return ChartOptions(title: "Excess secondary attack rate \(notification)", data: data, columns: [sar, sarplus, sarminus])
}

func dateExposure14(enpa: DataFrame, config _: Configuration, notification: Int) -> ChartOptions {
    let columns = (1 ... 8).map { "nt\(notification)-de\($0)%" }

    return ChartOptions(title: "Delay between exposure and nt\(notification)", data: enpa, columns: columns, maxBound: 1.0)
}

func arrivingPromptly(enpa: DataFrame, config: Configuration) -> ChartOptions? {
    let columns = Array((1 ... config.numCategories).map { ["nt\($0) 0-3 days %", "nt\($0) 0-6 days %"] }.joined())

    return ChartOptions.maybe(title: "Notifications arriving promptly", data: enpa, columns: columns,
                        maxBound: 1.0)
}

func averageDaysUntilNotification(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns = (1 ... config.numCategories).map { "nt\($0) de avg" }

    return ChartOptions(title: "Average days until notification", data: enpa, columns: columns)
}

func daysUntilNotification(dateExposureAnalysis: DataFrame?, config: Configuration) -> ChartOptions? {
    guard let dateExposureAnalysis = dateExposureAnalysis else {
        return nil
    }
    let columns = (1 ... config.numCategories).map { "category \($0)" }

    return ChartOptions(title: "Days until notification", data: dateExposureAnalysis,
                        xAxis: "days since exposure", columns: columns)
}

// est. users
func estimatedUsers(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "Estimated users", data: enpa, columns: ["median est users from regional ENPA %", "est users using US ENPA %"])
}

// est. users
func scaledNotifications(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "Est. scaled notifications per day", data: enpa, columns: ["est scaled notifications/day", "est scaled notifications/day from regional ENPA %"])
}

func showingNotifications(enpa: DataFrame, config: Configuration) -> ChartOptions? {
    let columns = Array((1 ... config.numCategories).map { "nts\($0)%" })

    return ChartOptions.maybe(title: "Users with notifications", data: enpa, columns: columns)
}

func relativeRisk(enpa: DataFrame, config: Configuration) -> ChartOptions? {
    let columns = ["vcr-n"] + Array((1 ... config.numCategories).map { "vcr+n\($0)" })

    return ChartOptions.maybe(title: "Relative risk for notifications", data: enpa, columns: columns, minBound: 1.0, maxBound: 2000)
}

func hadNotificationsWhenPositive(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    let columns = ["vc+n%", "ku+n%"]

    return ChartOptions.maybe(title: "Percentage of positive users who had received exposure notifications", data: enpa, columns: columns, maxBound: 0.5)
}

func deviceAttenuations(worksheet: DataFrame?) -> ChartOptions? {
    guard let worksheet = worksheet else {
        return nil
    }
    let columns = [
        "Android <= 60 dB %",
        "iOS <= 65 dB %",

        "Android <= 70 dB %",
        "iOS <= 75 dB %",

        "Android <= 75 dB %",
        "iOS <= 80 dB %",
    ]

    return ChartOptions.maybe(title: "Comparison of device received attenuations", data: worksheet, columns: columns, maxBound: 1.0)
}

// est. users
func enpaOptIn(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "ENPA opt in", data: enpa, columns: ["regional ENPA %", "US ENPA %"], maxBound: 1.0)
}

// codes claimed/consent
// user report rate
// avg days onset to upload
// sms errors, publish rate, android rate

func claimedConsent(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "claim and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate,user reports claim rate,user reports consent rate".components(separatedBy: ","))
    }
    return ChartOptions(title: "claim and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate".components(separatedBy: ","))
}

func userReportRate(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions? {
    if !hasUserReports {
        return nil
    }
    return ChartOptions(title: "User report %", data: encv, columns: "user reports %,user reports revision rate".components(separatedBy: ","))
}

func tokensClaimed(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "tokens claimed", data: encv, columns: "tokens claimed,confirmed test tokens claimed,user report tokens claimed".components(separatedBy: ","))
    }
    return ChartOptions(title: "tokens claimed", data: encv, columns: "tokens claimed".components(separatedBy: ","))
}

func timeToClaimCodes(encv: DataFrame, hasUserReports _: Bool, config _: Configuration) -> ChartOptions {
    ChartOptions(title: "codes claimed within hour %", data: encv, columns: "codes claimed within hour %".components(separatedBy: ","))
}

func onsetToUpload(encv: DataFrame, hasUserReports _: Bool, config _: Configuration) -> ChartOptions {
    ChartOptions(title: "avg days onset to upload", data: encv, columns: "avg days onset to upload".components(separatedBy: ","))
}

func systemHealth(encv: DataFrame, hasSMS: Bool, config _: Configuration) -> ChartOptions {
    if hasSMS {
        return ChartOptions(title: "System health", data: encv, columns: "publish failure rate,sms error rate,android publish share".components(separatedBy: ","))
    }
    return ChartOptions(title: "System health", data: encv, columns: "publish failure rate,android publish share".components(separatedBy: ","))
}

func publishRequests(encv: DataFrame, config _: Configuration) -> ChartOptions {
    ChartOptions(title: "Publish requests", data: encv, columns: "publish requests,publish requests ios,publish requests android".components(separatedBy: ","))
}

struct CSVFile {
    let data: Data
    let name: String

    init(name: String, csv: Data) {
        data = csv
        self.name = name
    }
}

struct ZipFile {
    let data: Data
    let name: String

    init(name: String, zip: Data) {
        data = zip
        self.name = name
    }
}
