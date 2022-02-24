//
//  AnalysisState.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation
import os.log
@_predatesConcurrency import TabularData
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
    @Published var inProgress: Bool = false
    @Published var available: Bool = false
    @Published var rawENPA: RawMetrics?
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

    static func exportToURL(name: String, dataframe: DataFrameProtocol) -> URL? {
        logger.log("Exporting \(name, privacy: .public) to URL")
        do {
            let writingOptions = CSVWritingOptions(dateFormat: "yyyy-MM-dd")

            let csv = try dataframe.csvRepresentation(options: writingOptions)

            let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
            let n = name.replacingOccurrences(of: "/", with: "%2F")

            guard let path = documents?.appendingPathComponent(n) else {
                logger.error("Could not get path")
                return nil
            }

            try csv.write(to: path, options: .atomicWrite)
            return path
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func exportToFileDocument(name: String, dataframe: DataFrameProtocol) -> CSVFile? {
        logger.log("Exporting \(name, privacy: .public) to File")
        do {
            let writingOptions = CSVWritingOptions(dateFormat: "yyyy-MM-dd")
            let csv = try dataframe.csvRepresentation(options: writingOptions)
            let string = String(data: csv, encoding: .utf8)

            return CSVFile(name: name, csv)

        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
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

        enpaSummary.append(joined)
    }

    func log(encv: [String]) {
        if !encvSummary.isEmpty {
            encvSummary.append("\n")
        }
        let joined = encv.joined(separator: "\n")

        encvSummary.append(joined)
    }

    func analyzedENPA(raw: RawMetrics, ios: DataFrame, android: DataFrame, combined: DataFrame) {
        rawENPA = raw
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
            logger.log("encv: \(encv, privacy: .public)")
        }
        if let enpa = enpa {
            status = enpa
            encvDate = Date()
            logger.log("enpa: \(enpa, privacy: .public)")
        }
    }

    func makeENPACharts() {
        if let enpa = combinedENPA, let config = config {
            print("enpa columns: ")
            print("\(enpa.columns.count) enpa Columns: \(enpa.columns.map(\.name))")
            let maybeCharts = [
                notificationsPerUpload(enpa: enpa, config: config),
                notificationsPer100K(enpa: enpa, config: config),
                arrivingPromptly(enpa: enpa, config: config),
                estimatedUsers(enpa: enpa, config: config),
                enpaOptIn(enpa: enpa, config: config),
            ]
            enpaCharts = Array(maybeCharts.filter { $0 != nil }) as! [ChartOptions]

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
            let maybeCharts: [ChartOptions?] = [
                claimedConsent(encv: encv, hasUserReports: hasUserReports, config: config),
                userReportRate(encv: encv, hasUserReports: hasUserReports, config: config),
                tokensClaimed(encv: encv, hasUserReports: hasUserReports, config: config),
                // publishRequests(encv: encv, config: config),
                systemHealth(encv: encv, hasSMS: hasSMSerrors, config: config),
            ]

            encvCharts = Array(maybeCharts.filter { $0 != nil }) as! [ChartOptions]

            if hasUserReports {}
        } else {
            encvCharts = []
        }
    }
}

func computeEstimatedDevices(_ codesClaimed: Int?, _ cv: Double?) -> Int? {
    guard let codesClaimed = codesClaimed, let cv = cv, cv >= 1 else {
        return nil
    }
    return Int((Double(codesClaimed * 100_000) / cv).rounded())
}

func computeEstimatedUsers(encv: DataFrame, _ encvColumn: String, enpa: DataFrame, _ enpaColumn: String) -> DataFrame {
    logger.log("Computing est. users from \(encvColumn, privacy: .public) and \(enpaColumn, privacy: .public)")
    let codes_claimed = encv.selecting(columnNames: ["date", encvColumn])
    var joined = enpa.joined(codes_claimed, on: "date", kind: .left)
    joined.removeJoinNames()
    logger.log("join computed; columns renamed")

    let codesClaimed = joined[encvColumn, Int.self]
    let vc = joined[enpaColumn, Double.self]
    let result = zip(codesClaimed, vc).map { computeEstimatedDevices($0.0, $0.1) }
    logger.log("est. users computed")
    let c = Column(name: "est users", contents: result)
    joined.append(column: c)
    joined.addColumnPercentage("\(enpaColumn) count", "est users", giving: "ENPA %")
    return joined
}

actor AnalysisTask {
    func getRawENPA(config: Configuration, names: [String], result _: AnalysisState) async {
        var raw = RawMetrics(config)
        let errors = raw.addMetric(names: names)
    }
    func getAndAnalyzeENPA(config: Configuration, encvAverage: DataFrame?, result: AnalysisState) async {
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
                let errors = raw.addMetric(names: [m])
                if !errors.isEmpty {
                    await result.log(enpa: errors)
                    return
                }
            } // for m
            let additional = await result.additionalMetrics
            for m in additional {
                await result.update(enpa: "fetching \(m)")
                let errors = raw.addMetric(names: [m])
                if !errors.isEmpty {
                    await result.log(enpa: errors)
                }
            } // for m

            let metrics = raw.metrics

            var iOSDataFrame = try getRollingAverageIOSMetrics(metrics, options: config)
            iOSDataFrame.removeRandomElements()
            var androidDataFrame = try getRollingAverageAndroidMetrics(metrics, options: config)
            androidDataFrame.removeRandomElements()
            var combinedDataFrame = try getRollingAverageKeyMetrics(metrics, options: config)
            combinedDataFrame.removeRandomElements()
            if let encv = encvAverage {
                combinedDataFrame = computeEstimatedUsers(encv: encv, "codes claimed", enpa: combinedDataFrame, "vc")
                // iOSDataFrame = computeEstimatedUsers(encv: encv, "publish requests ios", enpa: iOSDataFrame, "ku")
                // androidDataFrame = computeEstimatedUsers(encv: encv, "publish requests android", enpa: androidDataFrame, "ku")
            }
            await result.analyzedENPA(raw: raw, ios: iOSDataFrame, android: androidDataFrame, combined: combinedDataFrame)
            let combined = summarize("combined", combinedDataFrame, categories: config.numCategories)
            let iOS = summarize("iOS", iOSDataFrame, categories: config.numCategories)
            let android = summarize("Android", androidDataFrame, categories: config.numCategories)
            let all = combined + iOS + android
            await result.log(enpa: all)

        } catch {
            await result.log(enpa: ["\(error)"])
        }
    }

    func getAndAnalyzeENCV(config: Configuration, result: AnalysisState) async -> ENCVAnalysis {
        if !config.hasENCV {
            return ENCVAnalysis(encv: nil, average: nil, log: ["Skipping ENCV"])
        }
        guard let
            encvAPIKey = config.encvAPIKey, !encvAPIKey.isEmpty,

            var composite = getENCVDataFrame("composite.csv", apiKey: encvAPIKey, useTestServers: config.useTestServers)
        else {
            logger.log("Failed to get ENCV composite.csv")
            return ENCVAnalysis(encv: nil, average: nil, log: ["Failed to get ENCV composite.csv"])
        }
        logger.log("Got ENCV composite.csv, requesting sms-errors.csv")
        let smsData: DataFrame? = getENCVDataFrame("sms-errors.csv", apiKey: config.encvAPIKey!, useTestServers: config.useTestServers)
        composite.removeRandomElements()
        let analysis = analyzeENCV(composite: composite, smsData: smsData)
        await result.gotENCV(composite: analysis.encv)
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
            await result.log(enpa: ["Skipping ENPA"])
        }

        await result.finish()
    }
}

struct ChartOptions: Identifiable {
    let days = 60
    let title: String
    let data: DataFrame.Slice
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
        let rows = max(7, data.rows.count - 6)
        self.data = data.suffix(rows).selecting(columnNames: ["date"] + columns)
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

func arrivingPromptly(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns = Array((1 ... config.numCategories).map { ["nt\($0) 0-3 days %", "nt\($0) 0-6 days %"] }.joined())

    return ChartOptions(title: "Notifications arriving promptly", data: enpa, columns: columns,
                        maxBound: 1.0)
}

// est. users
func estimatedUsers(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "Estimated users", data: enpa, columns: ["est users"])
}

// est. users
func enpaOptIn(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "ENPA opt in", data: enpa, columns: ["ENPA %"], maxBound: 1.0)
}

// codes claimed/consent
// user report rate
// avg days onset to upload
// sms errors, publish rate, android rate

func claimedConsent(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "claimed and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate,user report claim rate,user report consent rate".components(separatedBy: ","))
    }
    return ChartOptions(title: "claimed and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate".components(separatedBy: ","))
}

func userReportRate(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions? {
    if !hasUserReports {
        return nil
    }
    return ChartOptions(title: "User report %", data: encv, columns: "user report percentage,user reports revision rate".components(separatedBy: ","))
}

func tokensClaimed(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "tokensClaimed", data: encv, columns: "tokens claimed,confirmed test tokens claimed,user report tokens claimed".components(separatedBy: ","))
    }
    return ChartOptions(title: "tokens claimed", data: encv, columns: "tokens claimed".components(separatedBy: ","))
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
