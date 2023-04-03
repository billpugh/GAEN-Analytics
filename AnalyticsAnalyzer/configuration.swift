//
//  configuration.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/6/22.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "configuration")

let oneDay: TimeInterval = 24 * 60 * 60
let oneFetch = oneDay * 366

public struct FetchInterval {
    let start: Date
    let end: Date
}

public struct Configuration: @unchecked Sendable {
    let daysSinceExposureThreshold: Int
    let numDays: Int
    let numCategories: Int
    let region: String?
    let enpaAPIKey: String?
    let encvAPIKey: String?
    let startDate: Date?
    let endDate: Date?
    let configStart: Date?
    let useTestServers: Bool
    let durationBaselineMinutes: Double
    let highInfectiousnessWeight: Int

    var hasENPA: Bool {
        let result = enpaAPIKey != nil && !enpaAPIKey!.isEmpty
        return result
    }

    var hasENCV: Bool {
        let result = encvAPIKey != nil && !encvAPIKey!.isEmpty
        return result
    }

    func getFetchIntervals() -> [FetchInterval] {
        guard let startDate = startDate else {
            logger.log("no start date specified")

            return []
        }
        var fetchStart = startDate.advanced(by: -Double(numDays - 1) * oneDay)
        var result: [FetchInterval] = []
        let endDate = endDate ?? Date()
        while endDate.timeIntervalSince(fetchStart) > oneFetch {
            let nextFetch = fetchStart.advanced(by: oneFetch)
            result.append(FetchInterval(start: fetchStart, end: nextFetch))
            fetchStart = nextFetch
        }
        result.append(FetchInterval(start: fetchStart, end: endDate))
        return result
    }

    init(daysSinceExposureThreshold: Int = 10,
         numDays: Int = 7,
         numCategories: Int = 1,
         region: String? = nil,
         enpaAPIKey: String? = nil,
         encvAPIKey: String? = nil,
         startDate: Date? = nil,
         endDate: Date? = nil,
         configStart: Date? = nil,
         durationBaselineMinutes: Double = 15.0,
         highInfectiousnessWeight: Int,
         useTestServers: Bool = false)
    {
        //print("highInfectiousnessWeight = \(highInfectiousnessWeight)")
        self.daysSinceExposureThreshold = daysSinceExposureThreshold
        self.numDays = numDays
        self.numCategories = numCategories
        self.region = region
        self.enpaAPIKey = enpaAPIKey
        self.encvAPIKey = encvAPIKey
        self.startDate = startDate
        self.endDate = endDate
        self.configStart = configStart
        self.useTestServers = useTestServers
        self.durationBaselineMinutes = durationBaselineMinutes
        self.highInfectiousnessWeight = highInfectiousnessWeight
    }
}
