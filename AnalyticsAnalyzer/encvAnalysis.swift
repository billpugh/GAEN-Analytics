//
//  encvAnalysis.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/6/22.
//

import Foundation
import TabularData

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

    return getData(request)
}

public func getENCVDataFrame(_ stat: String, apiKey: String, useTestServers: Bool) -> DataFrame? {
    if let raw = getENCV(stat, apiKey: apiKey, useTestServers: useTestServers), raw.count > 0 {
        return try! DataFrame(csvData: raw, options: readingOptions)
    }
    return nil
}

func getErrorsByDate(smsData: DataFrame) -> ([Date: Int], [Date: Int]) {
    var allErrors: [Date: Int] = [:]
    var error30007: [Date: Int] = [:]

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
    guard composite.indexOfColumn("codes_issued") != nil else {
        return ENCVAnalysis(encv: nil, average: nil, log: ["no ENCV data"])
    }
    var encv = composite
    let user_reports_claimed = encv["user_reports_claimed", Int.self]
    let hasRevisions = encv.indexOfColumn("requests_with_revisions") != nil
    let hasUserReports = user_reports_claimed.max()! > 10
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
    if let smsData = smsData {
        let (allErrors, error30007) = getErrorsByDate(smsData: smsData)
        let dates = encv["date", Date.self]

        let errorColumn = dates.map { allErrors[$0!] ?? 0 }

        let error30007Column = dates.map { error30007[$0!] ?? 0 }
        encv.append(column: Column(name: "sms_errors", contents: errorColumn))
        encv.append(column: Column(name: "sms_30007_errors", contents: error30007Column))
    }

    var tmp = encv
    tmp.transformColumn("code_claim_age_distribution", transformDistribution)
    tmp.transformColumn("onset_to_upload_distribution", transformDistribution)

    var rollingAvg = tmp.rollingAvg(days: 7)
    rollingAvg.transformColumn("onset_to_upload_distribution", weightedSum)
    rollingAvg.renameColumn("onset_to_upload_distribution", to: "avg_days_onset_to_upload")
    // Buckets are: 1m, 5m, 15m, 30m, 1h, 2h, 3h, 6h, 12h, 24h, >24h
    rollingAvg.transformColumn("code_claim_age_distribution") { weightedSum($0, weights: [1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0]) }
    rollingAvg.renameColumn("code_claim_age_distribution", to: "codes_claimed_within_hour_percentage")

    if hasUserReports {
        rollingAvg.addColumnPercentage("user_reports_claimed", "user_reports_issued", giving: "user_reports_claim_rate")
        rollingAvg.addColumnPercentage("user_report_tokens_claimed", "user_reports_claimed", giving: "user_reports_consent_rate")
    }
    rollingAvg.addColumnPercentage("confirmed_test_claimed", "confirmed_test_issued", giving: "confirmed_test_claim_rate")
    rollingAvg.addColumnPercentage("confirmed_test_tokens_claimed", "confirmed_test_claimed", giving: "confirmed_test_consent_rate")
    if hasUserReports {
        rollingAvg.addColumnPercentage("unused_tokens", "tokens_claimed", giving: "publish_failure_rate")
        rollingAvg.addColumnPercentage("user_report_tokens_claimed", "tokens_claimed", giving: "user_report_percentage")
        if hasRevisions {
            rollingAvg.addColumnPercentage("requests_with_revisions", "tokens_claimed", giving: "user_reports_revision_rate")
        }
    } else {
        rollingAvg.addColumnPercentage("unused_tokens", "confirmed_test_tokens_claimed", giving: "publish_failure_rate")
    }
    rollingAvg.addColumnPercentage("publish_requests_android", "publish_requests", giving: "android_publish_share")
    rollingAvg.addColumnPercentage("codes_invalid_ios", "publish_requests_ios", giving: "ios_invalid_ratio")
    rollingAvg.addColumnPercentage("codes_invalid_android", "publish_requests_android", giving: "android_invalid_ratio")
    if smsData != nil {
        rollingAvg.addColumnPercentage("sms_errors", "codes_issued", giving: "sms_error_rate")
        rollingAvg.addColumnPercentage("sms_30007_errors", "codes_issued", giving: "sms_30007_error_rate")
    }
    var columnNamesInt = ["confirmed test issued"]
    if hasUserReports {
        columnNamesInt.append("user reports issued")
    }
    columnNamesInt.append("publish requests")

    rollingAvg.replaceUnderscoreWithSpace()
    var columnNames = [
        "publish failure rate",
        "android publish share",
        // "ios invalid ratio",
        // "android invalid ratio",
        "confirmed test claim rate",
        "confirmed test consent rate",
    ]
    if hasUserReports {
        columnNames.append(contentsOf: ["user reports claim rate", "user reports consent rate", "user report percentage"])
        if hasRevisions {
            columnNames.append("user reports revision rate")
        }
    }
    if smsData != nil {
        columnNames.append(contentsOf: ["sms error rate", "sms 30007 error rate"])
    }

    let columnsInt = columnNamesInt.map { rollingAvg[$0, Int.self] }
    let msgInt = columnsInt.map { c -> String in
        let name = c.name.replacingOccurrences(of: "_", with: " ")
        let lastValue = presentValue(name, c.last!, divisor: 7)
        let prevValue = presentValue(name, c[c.count - 8], divisor: 7)
        let m = "\(name): \(prevValue) → \(lastValue)"

        return m
    }
    let columnsDouble = columnNames.map { rollingAvg[$0, Double.self] }
    let msgDouble = columnsDouble.map { c -> String in
        let name = c.name.replacingOccurrences(of: "_", with: " ")
        let lastValue = presentValue(name, c.last!)
        let prevValue = presentValue(name, c[c.count - 8])
        let m = "\(name): \(prevValue) → \(lastValue)"

        return m
    }
    let log = msgInt + msgDouble

    return ENCVAnalysis(encv: encv, average: rollingAvg, log: log)
}
