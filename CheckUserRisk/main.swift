//
//  main.swift
//  CheckUserRisk
//
//  Created by Bill Pugh on 4/11/21.
//

import ArgumentParser
import Foundation

func median(_ a: [Int]) -> Int {
    if a.count % 2 == 1 {
        return a[a.count / 2]
    }
    return (a[a.count / 2 - 1] + a[a.count / 2]) / 2
}

struct CheckUserRisk: ParsableCommand {
    @Argument(help: "cvs export of ENPA data")
    var csvFile: String

    @Flag(help: "Show detailed information.")
    var detailed = false

    @Flag(help: "Check all metrics.")
    var allMetrics = false

    mutating func run() throws {
        let metrics = loadMetrics(file: csvFile, only: allMetrics ? nil : "com.apple.EN.UserRisk")
        guard let userRisk = metrics["com.apple.EN.UserRisk"] else {
            print("com.apple.EN.UserRisk not found")
            return
        }
        var minToPrint = 0
        for (day, sumBy) in userRisk.sumByDay.sorted(by: { $0.0 < $1.0 }) {
            let count = userRisk.clientsByDay[day]!
            if count < minToPrint {
                print("\(dayFormatter.string(from: day)), n/a")
                continue
            }
            minToPrint = max(minToPrint, count * 7 / 10)
            let likely = sumBy.map { getMostLikelyPopulationCountInt(totalCount: count, sumPart: $0) }
            let reporting = userRisk.likelyReporting(clients: count, likely: likely)
            let allClients = clientsPerDay(metrics, date: day).sorted()
            let maxCount = allClients.max()!
            let close = allClients.filter { $0 >= maxCount * 9 / 10 }

            let median = median(close)

            if detailed {
                print("\(dayFormatter.string(from: day)), \(minToPrint), \(maxCount), \(median), \(count), \(reporting), \(median - reporting), \(reporting * 100 / median)")
            } else {
                print("\(dayFormatter.string(from: day)),  \(reporting * 100 / median)")
            }
        }
    }
}

CheckUserRisk.main()
