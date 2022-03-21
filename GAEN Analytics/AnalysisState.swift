//
//  AnalysisState.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation
import os.log
import TabularData
private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "AnalyzeState")

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
    @Published var nextAction: String = "Fetch analytics"
    @Published var inProgress: Bool = false
    var progressSteps: Double = 0.0
    @Published var progress: Double = 0.0
    var progressCount: Double {
        let enpaCount = 7 + additionalMetrics.count
        return Double(enpaCount + 3)
    }

    @Published var available: Bool = false
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
    // persisted
    @Published var encvComposite: DataFrame?
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
        logger.log("exporting \(csvFile.name, privacy: .public)")
        csvExport = csvFile
        csvExportReady = true
    }

    static func exportToURL(name: String, dataframe: DataFrame) -> URL? {
        logger.log("Exporting \(name, privacy: .public) to URL")
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)
            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)

            let n = name.replacingOccurrences(of: "/", with: "%2F")

            let path = temporaryDirectoryURL.appendingPathComponent(n)

            try csv.write(to: path, options: .atomicWrite)
            return path
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func exportToURL(name: String, dataframe: DataFrame.Slice) -> URL? {
        logger.log("Exporting \(name, privacy: .public) to URL")
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)

            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)

            let n = name.replacingOccurrences(of: "/", with: "%2F")

            let path = temporaryDirectoryURL.appendingPathComponent(n)

            try csv.write(to: path, options: .atomicWrite)
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
            let dates = encvComposite["date", Date.self]
            print("wrote composites to \(path), first date \(dateFormatter.string(from: dates.first!!))")

        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
        }
    }

    static func exportToFileDocument(name: String, dataframe: DataFrame) -> CSVFile? {
        logger.log("Exporting \(name, privacy: .public) to File")
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)

            return CSVFile(name: name, csv)

        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func exportToFileDocument(name: String, dataframe: DataFrame.Slice) -> CSVFile? {
        logger.log("Exporting \(name, privacy: .public) to File")
        do {
            let csv = try dataframe.csvRepresentation(options: AnalysisState.writingOptions)

            return CSVFile(name: name, csv)

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
        rawENPA = nil
        iOSENPA = nil
        AndroidENPA = nil
        combinedENPA = nil
        encvComposite = nil
        worksheet = nil
        rollingAvg = nil
        deleteComposite()
        encvComposite = nil
        status = "Fetch analytics"
        nextAction = "Fetch analytics"
    }

    func start(config: Configuration) {
        self.config = config
        inProgress = true
        progress = 0.0
        progressSteps = 0
        available = false

        enpaSummary = ""
        encvSummary = ""
        nextAction = "Fetching analytics"
        enpaCharts = []
        encvCharts = []
    }

    func finish() {
        inProgress = false
        progress = 1.0
        available = true
        availableAt = Date()
        status = "Update analytics"
        nextAction = "Update analytics"
    }

    func gotENCV(composite: DataFrame?) {
        encvComposite = composite
        saveComposite()
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

        enpaSummary.append(joined)
    }

    func log(encv: [String]) {
        if !encvSummary.isEmpty {
            encvSummary.append("\n")
        }
        let joined = encv.joined(separator: "\n")

        encvSummary.append(joined)
    }

    func analyzedENPA(raw: RawMetrics, ios: DataFrame, android: DataFrame, combined: DataFrame, worksheet: DataFrame?) {
        rawENPA = raw
        iOSENPA = ios
        AndroidENPA = android
        combinedENPA = combined
        self.worksheet = worksheet
        encvDate = Date()
        makeENPACharts()
        enpaAvailable = true
    }

    func update(encv: String? = nil, enpa: String? = nil) {
        progressSteps = progressSteps + 1
        progress = min(progressSteps / progressCount, 1.0)

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
                notificationsPerUpload(enpa: enpa, config: config),
                notificationsPer100K(enpa: enpa, config: config),
                notificationsShare(enpa: enpa, config: config),
            ]
                + (1 ... config.numCategories).map { secondaryAttackRateSpread(enpa: enpa, config: config, notification: $0) }
                + [
                    arrivingPromptly(enpa: enpa, config: config),
                    estimatedUsers(enpa: enpa, config: config),
                    enpaOptIn(enpa: enpa, config: config),
                ]
            enpaCharts = maybeCharts.compactMap { $0 }
            let maybeAppendixENPACharts: [ChartOptions?] = [showingNotifications(enpa: enpa, config: config)]
                + ((1 ... config.numCategories).map { excessSecondaryAttackRateSpread(enpa: enpa, config: config, notification: $0) })

            appendixENPACharts = maybeAppendixENPACharts.compactMap { $0 }

        } else {
            enpaCharts = []
            appendixENPACharts = []
        }
    }

    func makeENCVCharts() {
        if let encv = rollingAvg, let config = config {
            if false {
                print("\(encv.columns.count) enpa Columns: \(encv.columns.map(\.name))")
            }
            let hasUserReports = encv.indexOfColumn("user reports claim rate") != nil

            let hasSMSerrors = encv.indexOfColumn("sms error rate") != nil

            encvCharts = [
                claimedConsent(encv: encv, hasUserReports: hasUserReports, config: config),
                userReportRate(encv: encv, hasUserReports: hasUserReports, config: config),
                tokensClaimed(encv: encv, hasUserReports: hasUserReports, config: config),
                systemHealth(encv: encv, hasSMS: hasSMSerrors, config: config),
            ].compactMap { $0 }

            appendixCharts = [
                timeToClaimCodes(encv: encv, hasUserReports: hasUserReports, config: config),
                onsetToUpload(encv: encv, hasUserReports: hasUserReports, config: config),
                publishRequests(encv: encv, config: config),
            ].compactMap { $0 }

        } else {
            encvCharts = []
            appendixCharts = []
        }
    }
}

func computeEstimatedDevices(_ codesClaimed: Int?, _ cv: Double?) -> Int? {
    guard let codesClaimed = codesClaimed, let cv = cv, cv >= 1 else {
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

    let vc = result[enpaColumn, Double.self]
    let estUsers = zip(newEncvColumn, vc).map { computeEstimatedDevices($0.0, $0.1) }
    let estUsersColumnName = "est \(platform)users from \(enpaColumn)"
    logger.log("\(estUsersColumnName) computed")
    let c = Column(name: estUsersColumnName, contents: estUsers)
    result.append(column: c)
    result.addColumnPercentage("\(enpaColumn) count", estUsersColumnName, giving: "\(platform)\(enpaColumn) ENPA %")
    return result
}

actor AnalysisTask {
    func getAndAnalyzeENPA(config: Configuration, encvAverage: DataFrame?, result: AnalysisState) async {
        do {
            var raw = RawMetrics(config)
            let readThese = ["userRisk",
                             "notification",
                             "notificationInteractions",
                             "codeVerified",
                             "keysUploaded",
                             "dateExposure"]
            for m in readThese {
                await result.update(enpa: "fetching ENPA \(m)")
                let errors = raw.addMetric(names: [m])
                if !errors.isEmpty {
                    await result.log(enpa: errors)
                    return
                }
            } // for m
            let additional = await result.additionalMetrics
            for m in additional {
                await result.update(enpa: "fetching ENPA \(m)")
                let errors = raw.addMetric(names: [m])
                if !errors.isEmpty {
                    await result.log(enpa: errors)
                }
            } // for m

            let metrics = raw.metrics
            await result.update(enpa: "Analyzing enpa")
            var iOSDataFrame = try getRollingAverageIOSMetrics(metrics, options: config)
            iOSDataFrame.removeRandomElements()
            var androidDataFrame = try getRollingAverageAndroidMetrics(metrics, options: config)
            androidDataFrame.removeRandomElements()
            var combinedDataFrame = try getRollingAverageKeyMetrics(metrics, options: config)
            combinedDataFrame.removeRandomElements()
            var worksheet: DataFrame
            if let encv = encvAverage {
                combinedDataFrame = computeEstimatedUsers(platform: "", encv: encv, "codes claimed", enpa: combinedDataFrame, "vc")
                combinedDataFrame = computeEstimatedUsers(platform: "", encv: encv, "publish requests", enpa: combinedDataFrame, "ku")
                iOSDataFrame = computeEstimatedUsers(platform: "iOS ", encv: encv, "publish requests ios", enpa: iOSDataFrame, "ku")
                androidDataFrame = computeEstimatedUsers(platform: "Android ", encv: encv, "publish requests android", enpa: androidDataFrame, "ku")
                combinedDataFrame.requireColumns("date", "vc count", "vc", "ku", "nt", "codes issued", "est users from vc", "vc ENPA %")
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

            worksheet.addColumn("vc count", Int.self, newName: "android enpa users", from: androidDataFrame)
            worksheet.addColumn("vc", Double.self, newName: "android vc", from: androidDataFrame)
            worksheet.addColumn("ku", Double.self, newName: "android ku", from: androidDataFrame)
            worksheet.addColumn("nt", Double.self, newName: "android nt", from: androidDataFrame)
            worksheet.addOptionalColumn("publish requests android", Int.self, from: androidDataFrame)
            worksheet.addOptionalColumn("est Android users from ku", Int.self, from: androidDataFrame)
            worksheet.addOptionalColumn("Android ku ENPA %", Double.self, from: androidDataFrame)
            worksheet.addOptionalColumn("publish requests android", Int.self, from: encvAverage)
            worksheet.addOptionalColumn("android publish share", Double.self, from: encvAverage)

            await result.analyzedENPA(raw: raw, ios: iOSDataFrame, android: androidDataFrame, combined: combinedDataFrame, worksheet: worksheet)
            let combined = summarize("combined", combinedDataFrame, categories: config.numCategories)
            let iOS = summarize("iOS", iOSDataFrame, categories: config.numCategories)
            let android = summarize("Android", androidDataFrame, categories: config.numCategories)
            let all = combined + iOS + android
            await result.log(enpa: all)

        } catch {
            print("\(error.localizedDescription)")
            await result.log(enpa: ["\(error.localizedDescription)"])
        }
    }

    func getAndAnalyzeENCV(config: Configuration, result: AnalysisState) async -> ENCVAnalysis {
        if !config.hasENCV {
            return ENCVAnalysis(encv: nil, average: nil, log: ["Skipping ENCV"])
        }
        await result.update(encv: "Fetching enpa composite")
        guard let
            encvAPIKey = config.encvAPIKey, !encvAPIKey.isEmpty,

            let newComposite = getENCVDataFrame("composite.csv", apiKey: encvAPIKey, useTestServers: config.useTestServers)
        else {
            logger.log("Failed to get ENCV composite.csv")
            return ENCVAnalysis(encv: nil, average: nil, log: ["Failed to get ENCV composite.csv"])
        }
        let composite: DataFrame
        if let existingComposite = await result.encvComposite {
            composite = existingComposite.merge(key: "date", Date.self, adding: newComposite)
            for d in composite["date", Date.self] {
                print(dateFormatter.string(from: d!))
            }
        } else {
            composite = newComposite
        }

        logger.log("Got ENCV composite.csv, requesting sms-errors.csv")

        await result.update(encv: "Fetching sms errors")
        let smsData: DataFrame? = getENCVDataFrame("sms-errors.csv", apiKey: config.encvAPIKey!, useTestServers: config.useTestServers)
        await result.update(encv: "Analyzing encv")
        let analysis = analyzeENCV(config: config, composite: composite, smsData: smsData)

        await result.gotENCV(composite: composite)
        await result.gotRollingAvg(rollingAvg: analysis.average)
        await result.log(encv: analysis.log)
        return analysis
    }

    func crash() {
        logger.error("deliberate crash of GAEN analytics")
        let foo: String? = nil
        print("\(foo!.count)")
    }
    func analyze(config: Configuration, result: AnalysisState,
                 analyzeENCV: Bool = true, analyzeENPA: Bool = true) async
    {
        let info = Bundle.main.infoDictionary!

        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let appVersion = info["CFBundleShortVersionString"] as? String ?? "unknown"

        logger.log("Starting analysis, GAEN Analytics version \(appVersion), build \(build)")
        await result.start(config: config)
        let encv: ENCVAnalysis?
        if analyzeENCV, config.hasENCV {
            logger.log("Starting analyzeENCV")
            encv = await getAndAnalyzeENCV(config: config, result: result)
            logger.log("Finished analyzeENCV")
        } else {
            encv = nil
            logger.log("skipping ENCV")
            await result.log(encv: ["Skipping ENCV"])
        }
        if analyzeENPA, config.hasENPA {
            logger.log("Starting analyzeENPA")
            await getAndAnalyzeENPA(config: config, encvAverage: encv?.average, result: result)
            logger.log("Finished analyzeENPA")
        } else {
            await result.log(enpa: ["Skipping ENPA \(analyzeENPA) \(config.hasENPA)"])
        }

        await result.finish()
    }
}

struct ChartOptions: Identifiable {
    let title: String
    let data: DataFrame
    let columns: [String]
    let maxBound: Double?
    var id: String {
        title
    }

    static func maybe(title: String, data: DataFrame, columns: [String], maxBound: Double? = nil) -> ChartOptions? {
        logger.log("Making chart \(title, privacy: .public)")
        for c in columns {
            if data.indexOfColumn(c) == nil {
                logger.log("Column \(c, privacy: .public) doesn't exist")
                return nil
            }
        }
        return ChartOptions(title: title, data: data, columns: columns, maxBound: maxBound)
    }

    init(title: String, data: DataFrame, columns: [String], maxBound: Double? = nil) {
        self.title = title
        // print("\(data.columns.count) data Columns: \(data.columns.map(\.name))")
        logger.log("Making chart \(title, privacy: .public)")
        for c in columns {
            if data.indexOfColumn(c) == nil {
                logger.error("Column \(c, privacy: .public) doesn't exist")
            }
        }

        self.data = data.selecting(columnNames: ["date"] + columns)
        let dates = self.data["date", Date.self]
        print("\(dates.first!!)")
        self.columns = columns
        self.maxBound = maxBound
    }
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

func secondaryAttackRateSpread(enpa: DataFrame, config _: Configuration, notification: Int) -> ChartOptions {
    let sar = "sar\(notification)%"
    let stdev = "sar\(notification) stdev%"
    let sarplus = "+1 stdev"
    let sarminus = "-1 stdev"
    var data = enpa.selecting(columnNames: ["date", sar, stdev])
    data.addColumnSumDouble(sar, stdev, giving: sarplus)
    data.addColumnDifferenceDouble(sar, stdev, giving: sarminus)
    // data.printColumnNames()
    return ChartOptions(title: "Secondary attack rate \(notification)", data: data, columns: [sar, sarplus, sarminus])
}

func excessSecondaryAttackRateSpread(enpa: DataFrame, config _: Configuration, notification: Int) -> ChartOptions {
    let sar = "xsar\(notification)%"
    let stdev = "sar\(notification) stdev%"
    let sarplus = "+1 stdev"
    let sarminus = "-1 stdev"
    var data = enpa.selecting(columnNames: ["date", sar, stdev])
    data.addColumnSumDouble(sar, stdev, giving: sarplus)
    data.addColumnDifferenceDouble(sar, stdev, giving: sarminus)
    // data.printColumnNames()
    return ChartOptions(title: "Excess secondary attack rate \(notification)", data: data, columns: [sar, sarplus, sarminus])
}

func arrivingPromptly(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns = Array((1 ... config.numCategories).map { ["nt\($0) 0-3 days %", "nt\($0) 0-6 days %"] }.joined())

    return ChartOptions(title: "Notifications arriving promptly", data: enpa, columns: columns,
                        maxBound: 1.0)
}

// est. users
func estimatedUsers(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "Estimated users", data: enpa, columns: ["est users from vc"])
}

func showingNotifications(enpa: DataFrame, config: Configuration) -> ChartOptions? {
    let columns = Array((1 ... config.numCategories).map { "nts\($0)%" })

    return ChartOptions.maybe(title: "Users with notifications", data: enpa, columns: columns)
}

// est. users
func enpaOptIn(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "ENPA opt in", data: enpa, columns: ["vc ENPA %"], maxBound: 1.0)
}

// codes claimed/consent
// user report rate
// avg days onset to upload
// sms errors, publish rate, android rate

func claimedConsent(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "claimed and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate,user reports claim rate,user reports consent rate".components(separatedBy: ","))
    }
    return ChartOptions(title: "claimed and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate".components(separatedBy: ","))
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
    // by default our document is empty
    let data: Data
    let name: String

    init(name: String, _ data: Data) {
        self.data = data
        self.name = name
    }
}

struct ZipFile {
    // by default our document is empty
    let data: Data
    let name: String

    init(name: String, _ data: Data) {
        self.data = data
        self.name = name
    }
}
