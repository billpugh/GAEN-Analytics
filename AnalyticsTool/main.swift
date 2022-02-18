//
//  main.swift
//  AnalyticsTool
//
//  Created by Bill Pugh on 5/5/21.
//

import ArgumentParser
import CSV
import Foundation
import TabularData

public func loadMetrics(file: String, configuration: Configuration, only: [String] = []) -> [String: Metric] {
    let stream = InputStream(fileAtPath: file)!
    let csv = try! CSVReader(stream: stream, hasHeaderRow: true)

    var rawMetrics = RawMetrics(configuration)
    while let row = csv.next() {
        let fullId = row[0]
        let id = row[4]
        if !only.isEmpty, !only.contains(id) {
            continue
        }

        let clients = Int(row[11])!
        let startTime = dateParser.date(from: row[2])!
        let endTime = dateParser.date(from: row[3])!
        let sum = row[1].dropFirst().dropLast().components(separatedBy: ", ").map { Int($0)! }

        rawMetrics.addMetric(fullId: fullId, id: id, epsilon: 8.0, startTime: startTime, endTime: endTime, clients: clients, sum: sum)
    }
    return rawMetrics.metrics
}

struct AnalyticsTool: ParsableCommand {
    @Option(name: .shortAndLong, help: "The number of days over which to compute rolling average")
    var days: Int = 7

    @Option(name: .shortAndLong, help: "Number of exposure categories")
    var categories: Int = 1

    @Option(name: .customLong("daysSinceExposureThreshold"))
    var daysSinceExposureThreshold: Int = 14

    @Flag(name: .customLong("iOS"), help: "Print just iOS data")
    var iOS: Bool = false

    @Flag(name: .customLong("Android"), help: "Print just Android data")
    var Android: Bool = false

    @Argument(help: "cvs export of raw ENPA data")
    var csvFile: String?

    @Option(help: "Can be provided along with an ENPA API key to directly download ENPA data rather than using a csv of raw ENPA data")
    var region: String?

    @Option(name: .customLong("apiKey"), help: "ENPA API key")
    var apiKey: String?

    @Option(name: .long, help: "Date to start analysis on (e.g., 2021-11-01)")
    var start: String?

    @Option(name: .customLong("cStart"), help: "Only use configs started after this date")
    var cStart: String?

    mutating func run() throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let regionName = region ?? csvFile!

        let startDate: Date?
        if let start = start {
            startDate = dateFormatter.date(from: start)
        } else {
            startDate = nil
        }
        var configStart: Date?
        if let cStart = cStart {
            configStart = dateFormatter.date(from: cStart)
        }
        let options = Configuration(daysSinceExposureThreshold: daysSinceExposureThreshold, numDays: days, numCategories: categories,
                                    region: region, enpaAPIKey: apiKey, startDate: startDate, configStart: configStart)

        let metrics: [String: Metric]
        if let region = region, let apiKey = apiKey {
            var raw = RawMetrics(options)
            let readThese = ["userRisk",
                             "notification",
                             "notificationInteractions",
                             "codeVerified",
                             "keysUploaded",
                             "dateExposure"]
            raw.addMetric(names: readThese)
            metrics = raw.metrics

        } else {
            metrics = loadMetrics(file: csvFile ?? "/dev/stdin", configuration: options, only: [])
        }
        // getMetric(metrics,"com.apple.EN.CodeVerified").printSumsByDay()
        if false {
            print("com.apple.EN.CodeVerified")
            getMetric(metrics, "com.apple.EN.CodeVerified").printSumsByStart()
            print("com.apple.EN.KeysUploaded")
            getMetric(metrics, "com.apple.EN.KeysUploaded").printSumsByStart()
            print("com.apple.EN.UserNotification")
            getMetric(metrics, "com.apple.EN.UserNotification").printSumsByStart()
            getMetric(metrics, "com.apple.EN.UserNotification").printSumsByDay()
            getMetric(metrics, "PeriodicExposureNotification").printSumsByDay()
            getMetric(metrics, "com.apple.EN.UserNotificationInteraction").printSumsByDay()
            getMetric(metrics, "PeriodicExposureNotificationInteraction").printSumsByDay()

            print("com.apple.EN.CodeVerified day")
            getMetric(metrics, "com.apple.EN.CodeVerified").printSumsByDay()
            print("com.apple.EN.CodeVerified day")
            getMetric(metrics, "com.apple.EN.CodeVerified").printSumsByDay()
            print("com.apple.EN.UserNotificationInteraction day")
            getMetric(metrics, "com.apple.EN.UserNotificationInteraction").printSumsByDay()
        }

        // let buffer = TextBuffer()
        let writingOptions = CSVWritingOptions(dateFormat: "yyyy-MM-dd")

        let useDataFrame = false
        if iOS {
            if false {
                let iOSDataFrame = try getRollingAverageIOSMetrics(metrics, options: options)

                // print("\(iOSDataFrame.columns.count) Columns: \(iOSDataFrame.columns.map(\.name))")
                // print(iOSDataFrame)

                let csv = try String(decoding: iOSDataFrame.csvRepresentation(options: writingOptions), as: UTF8.self)
                print(csv)

            } else {
                printRollingAverageKeyIOSMetrics(metrics, options: options)
            }
            print("iOS Rolling \(days)-day averages for \(regionName), daysSinceExposureThreshold: \(daysSinceExposureThreshold) ")
        } else if Android {
            if useDataFrame {
                let androidDataFrame = try getRollingAverageAndroidMetrics(metrics, options: options)

                let csv = try String(decoding: androidDataFrame.csvRepresentation(options: writingOptions), as: UTF8.self)
                print(csv)
            } else {
                printRollingAverageKeyMetricsAndroid(metrics, options: options)
            }
            print("Android Rolling \(days)-day averages for \(regionName), daysSinceExposureThreshold: \(daysSinceExposureThreshold) ")

        } else {
            if useDataFrame {
                let combinedDataFrame = try getRollingAverageKeyMetrics(metrics, options: options)
                let csv = try String(decoding: combinedDataFrame.csvRepresentation(options: writingOptions), as: UTF8.self)
                print(csv)
            } else {
                printRollingAverageKeyMetrics(metrics, options: options)
            }
            print("Combined Rolling \(days)-day averages for \(regionName), daysSinceExposureThreshold: \(daysSinceExposureThreshold) ")
        }
        if false {
            print("\nmissing tranches")
            let codeVerified = metrics["CodeVerified"]!
            let allKeys = metrics.keys.sorted()
            let allMetrics = allKeys.map { metrics[$0]! }
            for m in allMetrics {
                for d in codeVerified.clientsByStart.keys.sorted() {
                    if m.clientsFor(start: d) < 5 {
                        print("\(dayTimeFormatter.string(from: d)), \(m.clientsFor(start: d)), \(m.aggregation_id)")
                    }
                }
            }
        }
    }
}

AnalyticsTool.main()
