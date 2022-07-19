//
//  main.swift
//  encvTool
//
//  Created by Bill Pugh on 2/11/22.
//

import ArgumentParser
import Foundation
import TabularData

struct encvTool: ParsableCommand {
    @Argument(help: "encv composite.csv")
    var compositeFile: String

    @Argument(help: "encv sms-error-stats.csv")
    var smsFile: String?

    mutating func run() throws {
        var readingOptions = CSVReadingOptions()
        readingOptions.addDateParseStrategy(
            Date.ParseStrategy(
                format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
                locale: Locale(identifier: "en_US"),
                timeZone: TimeZone(abbreviation: "GMT")!
            ))
        let composite = try DataFrame(contentsOfCSVFile: URL(fileURLWithPath: compositeFile),
                                      types: ["date": .date],
                                      options: readingOptions)
        let smsErrors: DataFrame?
        if let smsFile = smsFile {
            smsErrors = try DataFrame(contentsOfCSVFile: URL(fileURLWithPath: smsFile),
                                      types: ["date": .date],
                                      options: readingOptions)
        } else {
            smsErrors = nil
        }
        let results = analyzeENCV(config: Configuration(), composite: composite, smsData: smsErrors)
        for s in results.log {
            print(s)
        }
        var writingOptions = CSVWritingOptions()
        writingOptions.dateFormatter = { date in dayFormatter.string(from: date) }
        if let avg = results.average {
            print()
            let data = try avg.csvRepresentation(options: writingOptions)
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        }
    }
}

encvTool.main()
