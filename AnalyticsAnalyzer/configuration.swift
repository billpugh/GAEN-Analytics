//
//  configuration.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/6/22.
//

import Foundation
public struct Configuration: @unchecked Sendable {
    let daysSinceExposureThreshold: Int
    let numDays: Int
    let numCategories: Int
    let region: String?
    let enpaAPIKey: String?
    let encvAPIKey: String?
    let startDate: Date?
    let configStart: Date?
    let useTestServers: Bool

    var hasENPA: Bool {
        let result = enpaAPIKey != nil && !enpaAPIKey!.isEmpty
        return result
    }

    var hasENCV: Bool {
        let result = encvAPIKey != nil && !encvAPIKey!.isEmpty
        return result
    }

    var prefetchStart: Date? {
        guard let startDate = startDate else {
            return nil
        }
        let prefetchDate = startDate.advanced(by: -Double((numDays - 1) * 24 * 60 * 60))
        return prefetchDate
    }

    init(daysSinceExposureThreshold: Int = 10,
         numDays: Int = 7,
         numCategories: Int = 1,
         region: String? = nil,
         enpaAPIKey: String? = nil,
         encvAPIKey: String? = nil,
         startDate: Date? = nil,
         configStart: Date? = nil,
         useTestServers: Bool = false)
    {
        self.daysSinceExposureThreshold = daysSinceExposureThreshold
        self.numDays = numDays
        self.numCategories = numCategories
        self.region = region
        self.enpaAPIKey = enpaAPIKey
        self.encvAPIKey = encvAPIKey
        self.startDate = startDate
        self.configStart = configStart
        self.useTestServers = useTestServers
    }
}
