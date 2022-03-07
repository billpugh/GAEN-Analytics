//
//  encvAnalysis.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/6/22.
//

import Foundation
import os.log
import TabularData
private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "encv")

let readingOptions: CSVReadingOptions = {
    var ro = CSVReadingOptions()
    ro.addDateParseStrategy(
        Date.ParseStrategy(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(abbreviation: "GMT")!
        ))
    return ro
}()

public func getENCV(_ stat: String, apiKey: String, useTestServers: Bool) -> Data? {
    // let host = "adminapi.verification.apollo-project.org"
    let host = useTestServers ? "adminapi.verification.apollo-project.org" : "adminapi.encv.org"
    let url = URL(string: "https://\(host)/api/stats/realm/\(stat)")!
    // print(url)
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue("application/json", forHTTPHeaderField: "accept")

    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    logger.log("requesting encv \(stat, privacy: .public)")

    return getData(request)
}

public func getENCVDataFrame(_ stat: String, apiKey: String, useTestServers: Bool) -> DataFrame? {
    if let raw = getENCV(stat, apiKey: apiKey, useTestServers: useTestServers), raw.count > 0 {
        return try! DataFrame(csvData: raw, options: readingOptions)
    }
    logger.log("failed to get encv \(stat, privacy: .public)")
    return nil
}

func getErrorsByDate(smsData: DataFrame) -> ([Date: Int], [Date: Int]) {
    var allErrors: [Date: Int] = [:]
    var error30007: [Date: Int] = [:]
    logger.log("computing sms errors by date")
    let dateIndex = smsData.indexOfColumn("date")!
    let errorCodeIndex = smsData.indexOfColumn("error_code")!
    let quantityIndex = smsData.indexOfColumn("quantity")!
    for r in smsData.rows {
        let date = r[dateIndex] as! Date
        let errorCode = r[errorCodeIndex] as! Int
        let quantity = r[quantityIndex] as! Int
        allErrors[date] = sum(allErrors[date], quantity)
        if errorCode == 30007 {
            error30007[date] = sum(error30007[date], quantity)
        }
    }
    return (allErrors, error30007)
}

func transformDistribution(_ distribution: String) -> [Int] {
    let d = distribution.components(separatedBy: "|")
    return d.map { Int($0) ?? -1 }
}

func weightedSum(_ v: [Int]?) -> Double? {
    guard let v = v else {
        return nil
    }
    var total = 0
    var weightedSum = 0
    for i in 0 ..< v.count {
        total += v[i]
        weightedSum += v[i] * i
    }
    return Double(weightedSum) / Double(total)
}

func weightedSum(_ v: [Int]?, weights: [Int]) -> Double? {
    guard let v = v, v.count == weights.count else {
        return nil
    }
    var total = 0
    var weightedSum = 0
    for i in 0 ..< v.count {
        total += v[i]
        weightedSum += v[i] * weights[i]
    }
    return Double(weightedSum) / Double(total)
}

struct ENCVAnalysis {
    let encv: DataFrame?
    let average: DataFrame?
    let log: [String]
}

func analyzeENCV(composite: DataFrame, smsData: DataFrame?) -> ENCVAnalysis {
    logger.log("analyzing encv")
    guard composite.hasColumn("codes_issued") else {
        return ENCVAnalysis(encv: nil, average: nil, log: ["no ENCV data"])
    }
    var encv = composite
    let user_reports_claimed = encv["user_reports_claimed", Int.self]
    let hasRevisions = encv.indexOfColumn("requests_with_revisions") != nil
    let user_reports_count = user_reports_claimed.max()!

    let hasUserReports = user_reports_count > 10
    if hasUserReports {
        encv.addColumnDifference("codes_issued", "user_reports_issued", giving: "confirmed_test_issued")
        encv.addColumnDifference("codes_claimed", "user_reports_claimed", giving: "confirmed_test_claimed")
        encv.addColumnDifference("tokens_claimed", "user_report_tokens_claimed", giving: "confirmed_test_tokens_claimed")

    } else {
        encv.copyColumn("codes_issued", giving: "confirmed_test_issued")
        encv.copyColumn("codes_claimed", giving: "confirmed_test_claimed")
        encv.copyColumn("tokens_claimed", giving: "confirmed_test_tokens_claimed")
    }

    encv.addColumnSum("publish_requests_android", "publish_requests_ios", giving: "publish_requests")
    if hasUserReports {
        encv.addColumnDifference("tokens_claimed", "publish_requests", giving: "unused_tokens")
    } else {
        encv.addColumnDifference("confirmed_test_tokens_claimed", "publish_requests", giving: "unused_tokens")
    }
    encv.checkUniqueColumnNames()
    if let smsData = smsData {
        let (allErrors, error30007) = getErrorsByDate(smsData: smsData)
        let dates = encv["date", Date.self]

        let errorColumn = dates.map { allErrors[$0!] ?? 0 }

        let error30007Column = dates.map { error30007[$0!] ?? 0 }
        encv.append(column: Column(name: "sms_errors", contents: errorColumn))
        encv.append(column: Column(name: "sms_30007_errors", contents: error30007Column))
    }

    let hasKeyServerStats = encv.hasColumn("publish_requests_android")
    var tmp = encv
    logger.log("transforming distribution")
    tmp.transformColumn("code_claim_age_distribution", transformDistribution)
    if hasKeyServerStats {
        tmp.transformColumn("onset_to_upload_distribution", transformDistribution)
    }
    tmp.checkUniqueColumnNames()
    var rollingAvg = tmp.rollingAvg(days: 7)
    rollingAvg.checkUniqueColumnNames()
    logger.log("computed rolling average")
    if hasKeyServerStats {
        rollingAvg.transformColumn("onset_to_upload_distribution", weightedSum)
        rollingAvg.renameColumn("onset_to_upload_distribution", to: "avg_days_onset_to_upload")
    }
    // Buckets are: 1m, 5m, 15m, 30m, 1h, 2h, 3h, 6h, 12h, 24h, >24h
    rollingAvg.transformColumn("code_claim_age_distribution") { weightedSum($0, weights: [1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0]) }
    rollingAvg.renameColumn("code_claim_age_distribution", to: "codes_claimed_within_hour_%")
    logger.log("computed rolling distribution")
    if hasUserReports {
        rollingAvg.addColumnPercentage("user_reports_claimed", "user_reports_issued", giving: "user_reports_claim_rate")
        rollingAvg.addColumnPercentage("user_report_tokens_claimed", "user_reports_claimed", giving: "user_reports_consent_rate")
    }
    rollingAvg.addColumnPercentage("confirmed_test_claimed", "confirmed_test_issued", giving: "confirmed_test_claim_rate")
    rollingAvg.addColumnPercentage("confirmed_test_tokens_claimed", "confirmed_test_claimed", giving: "confirmed_test_consent_rate")
    if hasUserReports {
        rollingAvg.addColumnPercentage("unused_tokens", "tokens_claimed", giving: "publish_failure_rate")
        rollingAvg.addColumnPercentage("user_report_tokens_claimed", "tokens_claimed", giving: "user_reports_percentage")
        if hasRevisions {
            rollingAvg.addColumnPercentage("requests_with_revisions", "tokens_claimed", giving: "user_reports_revision_rate")
        }
    } else {
        rollingAvg.addColumnPercentage("unused_tokens", "confirmed_test_tokens_claimed", giving: "publish_failure_rate")
    }
    if hasKeyServerStats {
        rollingAvg.addColumnPercentage("publish_requests_android", "publish_requests", giving: "android_publish_share")
        //rollingAvg.addColumnPercentage("publish_requests_ios", "publish_requests_android", giving: "ios_scaling_factor")

        //rollingAvg.addColumnPercentage("codes_invalid_ios", "publish_requests_ios", giving: "ios_invalid_ratio")
        //rollingAvg.addColumnPercentage("codes_invalid_android", "publish_requests_android", giving: "android_invalid_ratio")
    }
    rollingAvg.checkUniqueColumnNames()
    if smsData != nil {
        logger.log("adding sms stats")
        rollingAvg.addColumnPercentage("sms_errors", "codes_issued", giving: "sms_error_rate")
        rollingAvg.addColumnPercentage("sms_30007_errors", "codes_issued", giving: "sms_30007_error_rate")
    }
    logger.log("computing summary")
    // print("\(rollingAvg.columns.count) Columns: \(rollingAvg.columns.map(\.name))")
    rollingAvg.checkUniqueColumnNames()
    rollingAvg.replaceUnderscoreWithSpace()

    var columnNamesInt = ["confirmed test issued"]
    if hasUserReports {
        columnNamesInt.append("user reports issued")
    }
    if hasKeyServerStats {
        columnNamesInt.append("publish requests")
    }
    logger.log("computing summary of int fields")
    let columnsInt = columnNamesInt.filter { rollingAvg.requireColumn($0, Int.self) }.map { rollingAvg[$0, Int.self] }
    logger.log("have summary of int fields")
    let msgInt = columnsInt.map { c -> String in
        let name = c.name
        logger.log("summarizing \(name, privacy: .public)")
        let lastValue = presentValue(name, c.last!)

        if c.count >= 9 {
            let prevValue = presentValue(name, c[c.count - 8])
            return "\(name): \(prevValue) → \(lastValue)"
        } else {
            return "\(name): \(lastValue)"
        }
    }
    var columnNamesDouble = [
        "confirmed test claim rate",
        "confirmed test consent rate",
    ]
    if hasKeyServerStats {
        columnNamesDouble.append(contentsOf: ["publish failure rate",
                                              "android publish share"])
    }

    if hasUserReports {
        columnNamesDouble.append(contentsOf: ["user reports claim rate", "user reports consent rate", "user reports percentage"])
        if hasRevisions {
            columnNamesDouble.append("user reports revision rate")
        }
    }
    if smsData != nil {
        columnNamesDouble.append(contentsOf: ["sms error rate", "sms 30007 error rate"])
    }

    logger.log("computing summary of double fields")
    let columnsDouble = columnNamesDouble.filter { rollingAvg.requireColumn($0, Double.self) }.map { rollingAvg[$0, Double.self] }
    logger.log("have summary of double fields")
    let msgDouble = columnsDouble.map { c -> String in

        let name = c.name
        logger.log("summarizing \(name, privacy: .public)")
        let lastValue = presentValue(name, c.last!)
        if c.count >= 9 {
            let prevValue = presentValue(name, c[c.count - 8])
            return "\(name): \(prevValue) → \(lastValue)"
        } else {
            return "\(name): \(lastValue)"
        }
    }
    var log: [String] = []
    if let firstDate = encv["date", Date.self].first, let dateMsg = dateFormatter.string(for: firstDate) {
        log = ["encv data starts \(dateMsg)"]
    }
    log.append(contentsOf: msgInt)
    log.append(contentsOf: msgDouble)

    logger.log("summary finished")
    return ENCVAnalysis(encv: encv, average: rollingAvg, log: log)
}
