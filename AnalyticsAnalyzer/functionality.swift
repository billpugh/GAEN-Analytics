//
//  functionality.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/2/21.
//

import Foundation
import os.log
import TabularData

public let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    df.timeZone = TimeZone(identifier: "UTC")!
    return df
}()

let defaultStart = dateFormatter.date(from: "2021-12-01")!

// import ZIPFoundation
private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "functionality")

let beaconCountLimits = [3, 7, 15, 30, 50, 80, 120, 250, 999]
let beaconCountEstimates = [2.0, 5.0, 10.0, 20.0, 35.0, 60.0, 91.0, 130.0, 251.0]

public func clientsPerDay(_ metrics: [String: Metric], date: Date) -> [Int] {
    metrics.values.compactMap { $0.clientsByDay[date] }
}

public func clientsPerStart(_ metrics: [String: Metric], date: Date) -> [Int] {
    metrics.values.map { $0.clientsByStart[date] ?? 0 }
}

class NotificationShown {
    let daysShown: Int
    let classifications: Int
    var today = 0
    var counts: [[Double]]
    init(_ options: Configuration) {
        daysShown = options.daysSinceExposureThreshold
        classifications = options.numCategories
        counts = Array(repeating: Array(repeating: 0.0, count: daysShown), count: classifications)
    }

    func increment(classification: Int, age: Int, _ v: Double) {
        let daysRemaining = daysShown - age
        if daysRemaining <= 0 {
            return
        }
        // age = 0, daysShown = 10, daysRemaining = 10, add to days+9

        counts[classification][(today + daysRemaining - 1) % daysShown] += v
    }

    func increment(classification: Int, age: ClosedRange<Int>, _ v: Double) {
        let perBin = v / Double(age.count)
        for i in age {
            increment(classification: classification, age: i, perBin)
        }
    }

    func add(likely: [Double], clients: Int) {
        let per100KAdj = 100_000 / Double(clients)
        let per100K = likely.map { $0 * per100KAdj }
        for c in 0 ..< classifications {
            let offset = c * 4
            increment(classification: c, age: 0 ... 3, per100K[offset + 0])
            increment(classification: c, age: 4 ... 6, per100K[offset + 1])
            increment(classification: c, age: 7 ... 10, per100K[offset + 2])
            increment(classification: c, age: 11 ... 13, per100K[offset + 3])
        }
    }

    func advance() {
        today = (today + 1) % daysShown
        for c in 0 ..< classifications {
            counts[c][today] = 0
        }
    }

    func percentage() -> String {
        (sum.map { "\($0 / 100_000.0)" }).joined(separator: ",")
    }

    var sum: [Double] {
        counts.map { $0.reduce(0,+) }
    }
}

struct FixedLengthAccumulator {
    let width: Int
    var valuesAdded: Int = 1
    var next: Int = 0
    var raw: [[Int]]
    var values: [[Double]]
    var counts: [Int]
    var variances: [Double]
    var updated: Bool = false
    init(_ length: Int, width: Int) {
        self.width = width
        values = Array(repeating: Array(repeating: 0.0, count: width), count: length)
        raw = Array(repeating: Array(repeating: 0, count: width), count: length)
        counts = Array(repeating: 0, count: length)
        variances = Array(repeating: 0.0, count: length)
    }

    init(_ length: Int, _ metric: Metric) {
        width = metric.buckets
        values = Array(repeating: Array(repeating: 0.0, count: width), count: length)
        raw = Array(repeating: Array(repeating: 0, count: width), count: length)
        counts = Array(repeating: 0, count: length)
        variances = Array(repeating: 0, count: length)
    }

    @discardableResult mutating func addLikely(_ metric: Metric, day: Date, scale: Double = 1.0) -> [Double]? {
        guard
            let (count, sum, likely, variance) = metric.getLikely(day: day, scale: scale)
        else {
            return nil
        }
        for i in 0 ..< width {
            raw[next][i] += sum[i]
        }
        add(likely, count, variance)
        return likely
    }

    mutating func add(_ v: [Double], _ count: Int, _ variance: Double) {
        for i in 0 ..< width {
            values[next][i] += v[i]
        }
        counts[next] += count
        variances[next] += variance
        updated = true
    }

    mutating func advance() {
        if !updated {
            return
        }
        next = (next + 1) % values.count
        raw[next] = Array(repeating: 0, count: width)
        values[next] = Array(repeating: 0.0, count: width)
        counts[next] = 0
        variances[next] = 0.0
        valuesAdded += 1
        updated = false
    }

    func sum(_ i: Int) -> Double {
        var total = 0.0
        for v in values {
            total += v[i]
        }
        return total
    }

    func rawSum(_ i: Int) -> Int {
        var total = 0
        for v in raw {
            total += v[i]
        }
        return total
    }

    var sums: [Double] {
        var result: [Double] = []
        for i in 0 ..< width {
            result += [sum(i)]
        }
        return result
    }

    var rawSums: [Int] {
        var result: [Int] = []
        for i in 0 ..< width {
            result += [rawSum(i)]
        }
        return result
    }

    var count: Int {
        counts.reduce(0, +)
    }

    var variance: Double {
        variances.reduce(0, +)
    }

    var countPerDay: Int {
        count / rollupSizeInt
    }

    var std: Double {
        sqrt(variance)
    }

    func std(items: Int) -> Double {
        sqrt(Double(items)) * std
    }

    func stdPerDay(items: Int = 1) -> Double {
        std(items: items) / rollupSize
    }

    func per100K(_ v: Double) -> Double {
        v / Double(count) * 100_000
    }

    var stats: String {
        "\(countPerDay),\(per100K(std))"
    }

    var rollupSize: Double {
        Double(rollupSizeInt)
    }

    var rollupSizeInt: Int {
        min(valuesAdded, values.count)
    }

    var full: Bool {
        valuesAdded >= values.count
    }

    func per100KEmpty(range: ClosedRange<Int>) -> String {
        String(repeating: ",", count: range.count)
    }

    func per100K(range: ClosedRange<Int>) -> String {
        let total = per100K(sums[range].reduce(0.0,+))
        return "\(per100K(std)),\(total)," + per100KNoSTD(range: range)
    }

    func per100KNoTotal(range: ClosedRange<Int>, scale: Double = 1.0) -> String {
        // let show = sums[range].map { "\(per100K($0))"}
        "\(per100K(std * scale))," + per100KNoSTD(range: range, scale: scale)
    }

    func cumulativeDistribution(range: ClosedRange<Int>) -> String {
        let values = sums[range]
        let total = values.reduce(0.0,+)
        if total < 25 * stdPerDay() || total < 30 {
            return String(repeating: ",", count: range.count - 2)
        }
        var sum = 0.0
        let prefixSum = values[range.lowerBound ..< range.upperBound].map { (sum += $0 / total, sum).1 }
        return prefixSum.map { "\($0)" }.joined(separator: ",")
    }

    func cumulativeDistribution(categories: Int) -> String {
        [Int](0 ..< categories).map { cumulativeDistribution(range: $0 * 4 ... $0 * 4 + 3) }.joined(separator: ",")
    }

    func per100KNoSTD(range: ClosedRange<Int>, scale: Double = 1.0) -> String {
        sums[range].map { "\(per100K($0 * scale))" }.joined(separator: ",")
    }

    func per100KValues(range: ClosedRange<Int>) -> [Double] {
        sums[range].map { per100K($0) }
    }

    func per100K(range1: ClosedRange<Int>, range2: ClosedRange<Int>) -> String {
        let show1 = sums[range1].map { "\(per100K($0))" }.joined(separator: ",")
        let show2 = sums[range2].map { "\(per100K($0))" }.joined(separator: ",")
        let show3 = zip(sums[range1], sums[range2]).map { "\($0 / ($0 + $1))" }.joined(separator: ",")
        return "\(per100K(std)), \(show1), \(show2), \(show3)"
    }

    func perDay(range: ClosedRange<Int>) -> String {
        let show = sums[range].map { "\($0 / rollupSize)" }
        return show.joined(separator: ",")
    }
}

struct DelayedNotificationCounts {
    let daysDelay: Int
    var delayedValues: [[Double]] = []
    mutating func update(_ newValues: [Double]) -> [Double]? {
        delayedValues.append(newValues)
        if delayedValues.count > daysDelay {
            return delayedValues.removeFirst()
        }
        return nil
    }
}

let computeConfigWeights = false
struct Accumulators {
    let numDays: Int
    let numCategories: Int
    let daysSinceExposureThreshold: Int
    let printFunction: (String) -> Void
    let options: Configuration
    init(options: Configuration, _ m: MetricSet, printFunction: ((String) -> Void)? = nil) {
        self.options = options
        numDays = options.numDays
        numCategories = options.numCategories
        daysSinceExposureThreshold = options.daysSinceExposureThreshold

        if let printFunction = printFunction {
            self.printFunction = printFunction
        } else {
            self.printFunction = { print($0) }
        }
        //        let codeVerified: Metric
        //        let keysUploaded: Metric
        //        let userNotification: Metric
        //        let dateExposure: Metric?
        //        let userRisk: Metric?
        //        let interactions: Metric
        verifiedCount = FixedLengthAccumulator(numDays, m.codeVerified)
        uploadedCount = FixedLengthAccumulator(numDays, m.keysUploaded)
        notifiedCount = FixedLengthAccumulator(numDays, m.userNotification)
        interactionCount = FixedLengthAccumulator(numDays, m.interactions)
        dateExposureCount = FixedLengthAccumulator(numDays, m.dateExposure)
        notificationsShown = NotificationShown(options)
        excessSecondaryAttack = FixedLengthAccumulator(numDays, width: numCategories)
        durationBuckets = FixedLengthAccumulator(numDays, width: 26)
        attenuationBuckets = FixedLengthAccumulator(numDays, width: 11 + standardAttenuationConfigs.count)
        secondaryAttack14D = FixedLengthAccumulator(1, m.secondaryAttack14D)
        verified14DCount = FixedLengthAccumulator(1, m.codeVerified14D)
        uploaded14Count = FixedLengthAccumulator(1, m.keysUploaded14D)
    }

    var verifiedCount: FixedLengthAccumulator
    var uploadedCount: FixedLengthAccumulator
    var notifiedCount: FixedLengthAccumulator
    var interactionCount: FixedLengthAccumulator
    var dateExposureCount: FixedLengthAccumulator
    var notificationsShown: NotificationShown
    var durationBuckets: FixedLengthAccumulator
    var attenuationBuckets: FixedLengthAccumulator

    var secondaryAttack14D: FixedLengthAccumulator
    var verified14DCount: FixedLengthAccumulator
    var uploaded14Count: FixedLengthAccumulator

    var excessSecondaryAttack: FixedLengthAccumulator
    var delayedNotifications = DelayedNotificationCounts(daysDelay: 7)

    func secondaryAttacks(codesVerified: Double, verifiedWithNotification: Double, percentShowingNotification: Double) -> Double {
        // true secondary attacks = (s-c*e)/(1-e).
        (verifiedWithNotification - codesVerified * percentShowingNotification) / (1 - percentShowingNotification)
    }

    mutating func update(_ d: Date, _ m: MetricSet, _ scale: Double = 1.0) {
        if let vcLikely = verifiedCount.addLikely(m.codeVerified, day: d, scale: scale) {
            let cvc = m.codeVerified.clientsByDay[d]!
            let cvVariance = m.codeVerified.getVariance(totalCount: cvc)

            uploadedCount.addLikely(m.keysUploaded, day: d, scale: scale)
            notifiedCount.addLikely(m.userNotification, day: d, scale: scale)
            let allVerifiedCodes = vcLikely[1 ... (1 + numCategories)].reduce(0,+)

            let dateE = m.dateExposure
            if let likelyDE = dateExposureCount.addLikely(dateE, day: d, scale: scale),
               let dec = dateE.clientsByDay[d]
            {
                notificationsShown.add(likely: likelyDE, clients: dec)
                let percentWithNotifications = notificationsShown.sum.map { $0 / 100_000.0 }
                // true secondary attacks = (s-c*e)/(1-e).
                let verifiedWithNotification = vcLikely[2 ... (1 + numCategories)]
                let excessSecondaryAttacks = zip(verifiedWithNotification, percentWithNotifications).map { secondaryAttacks(codesVerified: allVerifiedCodes, verifiedWithNotification: $0, percentShowingNotification: $1) }

                excessSecondaryAttack.add(excessSecondaryAttacks, cvc, cvVariance)
            } // if let de
            else {
                let notificationsReceived = notifiedCount.per100KValues(range: 1 ... numCategories)
                let percentWithNotifications = notificationsReceived.map { Double(daysSinceExposureThreshold / 2) * $0 / 100_000 }
                let backgroundNotifications = percentWithNotifications.map { $0 * allVerifiedCodes }
                let excessSecondaryAttacks = zip(vcLikely[2 ... (1 + numCategories)], backgroundNotifications).map { $0 - $1 }
                excessSecondaryAttack.add(excessSecondaryAttacks, cvc, cvVariance)
            }

            interactionCount.addLikely(m.interactions, day: d, scale: scale)

            if let (count, _, likely, variance) = m.userRiskParameters.getLikely(day: d, scale: scale) {
                // 1344 buckets
                let summary = attenuationSummary(likely: likely)
                attenuationBuckets.add(summary, count, variance * 168.0)
            }
            if let (count, _, likely, variance) = m.userRisk?.getLikely(day: d, scale: scale) {
                // 512 buckets
                let summary = userRiskSummary(likely: likely)
                durationBuckets.add(summary, count, variance * 64.0)
            }

            secondaryAttack14D.addLikely(m.secondaryAttack14D, day: d, scale: 1.0 / 14.0)

            verified14DCount.addLikely(m.codeVerified14D, day: d, scale: 1.0 / 14.0)
            uploaded14Count.addLikely(m.keysUploaded14D, day: d, scale: 1.0 / 14.0)
        }
    }

    func sarRatio(_ pair: (Double, Double)) -> String {
        if pair.1 == 0 {
            return ""
        }
        let ratio = pair.0 / pair.1
        if ratio < 0 || ratio >= 0.2 {
            return ""
        }
        return "\(f4: round4(ratio))"
    }

    mutating func printMe(date: Date, scale: Double) {
        guard verifiedCount.updated else {
            return
        }
        let stats = "\(Int(verifiedCount.rollupSize)),\(f4: scale),\(verifiedCount.countPerDay),\(uploadedCount.countPerDay), \(notifiedCount.countPerDay)"

        let cvPrint = verifiedCount.per100K(range: 1 ... 1 + numCategories)
        let saValues: [Double] = verifiedCount.per100KValues(range: 2 ... numCategories + 1)
        let cvSTD = verifiedCount.per100K(verifiedCount.std)
        let kuPrint = uploadedCount.per100K(range: 1 ... 1 + numCategories)
        let unPrint = notifiedCount.per100K(range: 1 ... numCategories)
        let ku = uploadedCount.per100KValues(range: 1 ... 1 + numCategories).reduce(0,+)
        let unValues: [Double] = notifiedCount.per100KValues(range: 1 ... numCategories)
        let un = unValues.reduce(0,+)
        let unPercentage = unValues.map { "\($0 / un)" }.joined(separator: ",")
        let ntPerKy = "\(un / ku)," + notifiedCount.per100KValues(range: 1 ... numCategories).map { "\($0 / ku)" }.joined(separator: ",")
        let icPrint = interactionCount.per100K(range1: 1 ... numCategories, range2: 5 ... 4 + numCategories)
        let saPrint = excessSecondaryAttack.per100KNoSTD(range: 0 ... numCategories - 1)
        let xsa: [Double] = excessSecondaryAttack.per100KValues(range: 0 ... numCategories - 1)
        let sarPrint: String
        let sarStdPrint: String
        let xsarPrint: String

        sarPrint = zip(saValues, unValues).map {
            if let ar = sar($0, $1, std: cvSTD) {
                return "\(ar)"
            }
            return ""
        }.joined(separator: ",")
        sarStdPrint = zip(saValues, unValues).map {
            if let ar = sar(cvSTD, $1, std: 0) {
                return "\(ar)"
            }
            return ""
        }.joined(separator: ",")
        xsarPrint = zip(xsa, unValues).map({
            if let ar = sar($0, $1, std: cvSTD) {
                return "\(ar)"
            }
            return ""
        }
        ).joined(separator: ",")

        let dePrint: String
        let nsPrint: String

        if dateExposureCount.updated {
            dePrint = "\(dateExposureCount.countPerDay),\(dateExposureCount.per100KNoTotal(range: 0 ... 4 * numCategories - 1)),\(dateExposureCount.cumulativeDistribution(categories: numCategories))"

            nsPrint = notificationsShown.percentage()

        } else {
            dePrint = String(repeating: ",", count: 1 + 7 * numCategories)
            nsPrint = String(repeating: ",", count: numCategories - 1)
        }
        let sa14Print: String

        if secondaryAttack14D.updated {
            // numCategories = 2
            // x, x, x,   x, x,   x, x
            sa14Print = "\(secondaryAttack14D.countPerDay),\(secondaryAttack14D.per100K(secondaryAttack14D.std) / 14.0)," + secondaryAttack14D.per100KNoSTD(range: 0 ... numCategories - 1) + "," + secondaryAttack14D.per100KNoSTD(range: 8 ... 8 + numCategories - 1)
        } else {
            sa14Print = String(repeating: ",", count: 1 + 2 * numCategories)
        }
        let vc14Print: String
        if verified14DCount.updated {
            let values = verified14DCount.per100KValues(range: 0 ... 5)
            vc14Print = "\(verified14DCount.countPerDay),\(verified14DCount.per100K(verified14DCount.std) / 14.0),\(values[1]),\(values[3])"
        } else {
            vc14Print = ",,,"
        }
        let ku14Print: String
        if uploaded14Count.updated {
            let values = uploaded14Count.per100KValues(range: 0 ... 5)
            ku14Print = "\(uploaded14Count.countPerDay),\(uploaded14Count.per100K(verified14DCount.std) / 14.0),\(values[1]),\(values[3])"
        } else {
            ku14Print = ",,,"
        }

        let aBPrint: String
        if attenuationBuckets.updated {
            let total = attenuationBuckets.sums[0 ..< 8].reduce(0.0,+)
            var sum = 0.0
            let prefixPercentage = attenuationBuckets.sums[0 ..< 7].map { (sum += $0, sum / total).1 }

            let v = prefixPercentage.map { "\(round4($0))" }.joined(separator: ",")
            let highInfectious = attenuationBuckets.sums[10] / total
            let infectious = (attenuationBuckets.sums[9] + attenuationBuckets.sums[10]) / total
            let nnv2 = attenuationBuckets.sums[11]
            let cwPrint = computeConfigWeights ? attenuationBuckets.sums[12 ..< 11 + standardAttenuationConfigs.count].map { ",\(round4($0 / nnv2))" }.joined() : ""
            // attn count,<= 50 dB %,<= 55 dB %,<= 60 dB %,<= 65 dB %,<= 70 dB %,<= 75 dB %,<= 80 dB %,high infect %,infect %,narrow net v1,wide net
            aBPrint = "\(attenuationBuckets.countPerDay),\(v),\(round4(highInfectious)),\(round4(infectious))\(cwPrint)"

        } else {
            // aBPrint = ",, ,,, ,,, ,,," / 11
            aBPrint = String(repeating: ",", count: 9 + (computeConfigWeights ? standardAttenuationConfigs.count - 1 : 0))
        }
        let dBPrint: String
        if durationBuckets.updated {
            let detected = durationBuckets.sums[0]
            let noninfectious = durationBuckets.sums[25]
            let infectious = detected - noninfectious
            let wd = durationBuckets.sums[1 ..< 8].map { "\(round4($0 / detected))" }.joined(separator: ",")
            let max = durationBuckets.sums[9 ..< 16].map { "\(round4($0 / infectious))" }.joined(separator: ",")
            let sum = durationBuckets.sums[17 ..< 25].map { "\(round4($0 / infectious))" }.joined(separator: ",")
            let std = round4(durationBuckets.std / detected)
            let detectedPercentage = round4(detected / Double(durationBuckets.count))
            let noninfectiousPercentage = round4(noninfectious / Double(durationBuckets.count))
            dBPrint = "\(durationBuckets.countPerDay),\(std),\(detectedPercentage),\(noninfectiousPercentage), \(wd), \(max), \(sum)"
        } else {
            dBPrint = ",,,, ,,,,,,,  ,,,,,,,  ,,,,,,,"
        }
        printFunction("\(dayFormatter.string(from: date)),\(stats),\(cvPrint),\(saPrint),\(sarPrint),\(sarStdPrint),\(xsarPrint),\(kuPrint),\(unPrint),\(unPercentage),\(ntPerKy),\(nsPrint),\(icPrint),\(dePrint),\(sa14Print),\(vc14Print),\(ku14Print),\(aBPrint),\(dBPrint)")

        verifiedCount.advance()
        uploadedCount.advance()
        notifiedCount.advance()
        interactionCount.advance()
        dateExposureCount.advance()
        notificationsShown.advance()
        excessSecondaryAttack.advance()
        verified14DCount.advance()
        uploaded14Count.advance()
        secondaryAttack14D.advance()
        attenuationBuckets.advance()
        durationBuckets.advance()
    }

    func printHeader() {
        let range = 1 ... numCategories
        let vcHeader = "vc std,vc,vc-n," + range.map { "vc+n\($0)," }.joined(separator: "") + range.map { "xsa\($0)" }.joined(separator: ",")
        let kuHeader = "ku std,ku,ku-n," + range.map { "ku+n\($0)" }.joined(separator: ",")
        let ntHeader = "nt std,nt," + range.map { "nt\($0)," }.joined() + range.map { "nt\($0)%," }.joined() + "nt/ku," + range.map { "nt\($0)/ku," }.joined()
        let esHeader = range.map { "nts\($0)%," }.joined()
        let sarHeader = range.map { "sar\($0)%," }.joined() + range.map { "sar\($0)% stdev," }.joined() + range.map { "xsar\($0)%" }.joined(separator: ",")

        let inHeader = "in std," + range.map { "in+\($0)," }.joined() + range.map { "in-\($0)," }.joined() + range.map { "in\($0)%," }.joined()
        let deHeader = "dec count,de std," + range.map { "nt\($0) days 0-3,nt\($0) days 4-6,nt\($0) days 7-10,nt\($0) days 11+" }.joined(separator: ",") + ","
            + range.map { "nt\($0) 0-3 days %,nt\($0) 0-6 days %,nt\($0) 0-10 days %" }.joined(separator: ",")
        let sa14Header = "sa14 count,sa14 std," + (0 ... numCategories - 1).map { "sa14 ct\(1 + $0)," }.joined() + (0 ... numCategories - 1).map { "sa14 sr\(1 + $0)" }.joined(separator: ",")
        let cv14Header = "vc14 count,vc14 std,vc ct,vc sr"
        let ku14Header = "ku14 count,ku14 std,ku ct,ku sr"
        let cwHeader = computeConfigWeights ?
            standardAttenuationConfigs[1 ..< standardAttenuationConfigs.count].map { ",\($0.name) %" }.joined() : ""

        let aBHeader = "attn count,<= 50 dB %,<= 55 dB %,<= 60 dB %,<= 65 dB %,<= 70 dB %,<= 75 dB %,<= 80 dB %,high infect %,infect %\(cwHeader)"
        let dBHeader = "dur count,dur std %,detected %,noninfectious %,wd > 10min %,wd > 20min %,wd > 30min %,wd > 50min %,wd > 70min %,wd > 90min %,wd > 120min %,max > 3min %,max > 7min %,max > 11min %,max > 15min %,max > 19min %,max > 23min %,max > 27min %,sum > 40min %,sum > 50min %,sum > 60min %,sum > 70min %,sum > 80min %,sum > 90min %,sum > 120min %,long/far %"

        printFunction("date,days,scale,vc count,ku count,nt count,\(vcHeader),\(sarHeader),\(kuHeader),\(ntHeader)\(esHeader)\(inHeader)\(deHeader),\(sa14Header),\(cv14Header),\(ku14Header),\(aBHeader), \(dBHeader)")
    }
}

func printRollingAverageKeyMetrics(_ m: MetricSet, options: Configuration, printFunction: ((String) -> Void)? = nil) {
    var accum = Accumulators(options: options, m, printFunction: printFunction)
    accum.printHeader()

    for d in m.codeVerified.clientsByDay.keys.sorted() {
        let scale = iOSScale(day: d, userRisk: m.userRisk)
        accum.update(d, m, scale)
        accum.printMe(date: d, scale: scale)
    }
}

struct MetricSet {
    let codeVerified: Metric
    let keysUploaded: Metric
    let userNotification: Metric
    let dateExposure: Metric
    let userRisk: Metric?
    let userRiskParameters: Metric
    let interactions: Metric

    let secondaryAttack14D: Metric
    let codeVerified14D: Metric
    let keysUploaded14D: Metric

    init(forIOS metrics: [String: Metric]) {
        codeVerified = getMetric(metrics, "com.apple.EN.CodeVerified")
        keysUploaded = getMetric(metrics, "com.apple.EN.KeysUploaded")
        userNotification = getMetric(metrics, "com.apple.EN.UserNotification")
        dateExposure = getMetric(metrics, "com.apple.EN.DateExposure")
        userRisk = getMetric(metrics, "com.apple.EN.UserRisk")
        userRiskParameters = getMetric(metrics, "com.apple.EN.UserRiskParameters")
        interactions = getMetric(metrics, "com.apple.EN.UserNotificationInteraction")

        secondaryAttack14D = getMetric(metrics, "com.apple.EN.SecondaryAttackV2D14")
        codeVerified14D = getMetric(metrics, "com.apple.EN.CodeVerifiedWithReportTypeV2D14")
        keysUploaded14D = getMetric(metrics, "com.apple.EN.KeysUploadedWithReportTypeV2D14")
    }

    init(forAndroid metrics: [String: Metric]) {
        codeVerified = getMetric(metrics, "CodeVerified")
        keysUploaded = getMetric(metrics, "KeysUploaded")
        userNotification = getMetric(metrics, "PeriodicExposureNotification")
        dateExposure = getMetric(metrics, "DateExposure")
        userRiskParameters = getMetric(metrics, "histogramMetric")
        interactions = getMetric(metrics, "PeriodicExposureNotificationInteraction")

        secondaryAttack14D = getMetric(metrics, "SecondaryAttack14d")
        codeVerified14D = getMetric(metrics, "CodeVerifiedWithReportType14d")
        keysUploaded14D = getMetric(metrics, "KeysUploadedWithReportType14d")

        userRisk = nil
    }
}

func printRollingAverageKeyMetrics(iOS: MetricSet, android: MetricSet, options: Configuration, printFunction: ((String) -> Void)? = nil) {
    logger.log("printRollingAverageKeyMetrics combined")
    var accum = Accumulators(options: options, iOS, printFunction: printFunction)
    accum.printHeader()

    for d in iOS.codeVerified.clientsByDay.keys.sorted() {
        let scale = iOSScale(day: d, userRisk: iOS.userRisk)
        accum.update(d, iOS, scale)
        accum.update(d, android)
        accum.printMe(date: d, scale: scale)
    }
}

func getOptionalMetric(_ metrics: [String: Metric], _ name: String) -> Metric? {
    metrics[name]
}

func getMetric(_ metrics: [String: Metric], _ name: String) -> Metric {
    if let metric = metrics[name] {
        return metric
    }
    logger.log("Did not find metric \(name, privacy: .public)")
    print("Did not find metric \(name)")
    print("Metrics found include:")
    for name in metrics.keys.sorted() {
        print("  \(name)")
    }
    exit(1)
}

func getRollingAverageKeyMetrics(_ metrics: [String: Metric], options: Configuration) throws -> DataFrame {
    let buffer = TextBuffer()

    printRollingAverageKeyMetrics(metrics,
                                  options: options, printFunction: { buffer.append($0) })
    return try buffer.asENPAData(startDate: options.startDate)
}

func printRollingAverageKeyMetrics(_ metrics: [String: Metric], options: Configuration, printFunction: ((String) -> Void)? = nil) {
    let iOS = MetricSet(forIOS: metrics)
    let android = MetricSet(forAndroid: metrics)

    printRollingAverageKeyMetrics(iOS: iOS, android: android,
                                  options: options, printFunction: printFunction)
}

func getRollingAverageIOSMetrics(_ metrics: [String: Metric], options: Configuration) throws -> DataFrame {
    let buffer = TextBuffer()
    printRollingAverageKeyIOSMetrics(metrics, options: options, printFunction: { buffer.append($0) })
    return try buffer.asENPAData(startDate: options.startDate)
}

func printRollingAverageKeyIOSMetrics(_ metrics: [String: Metric], options: Configuration, printFunction: ((String) -> Void)? = nil) {
    let iOS = MetricSet(forIOS: metrics)

    printRollingAverageKeyMetrics(iOS, options: options, printFunction: printFunction)
}

func printRollingAverageKeyMetricsAndroid(_ metrics: [String: Metric], options: Configuration, printFunction: ((String) -> Void)? = nil) {
    let android = MetricSet(forAndroid: metrics)
    printRollingAverageKeyMetrics(android,
                                  options: options, printFunction: printFunction)
}

func getRollingAverageAndroidMetrics(_ metrics: [String: Metric], options: Configuration) throws -> DataFrame {
    let buffer = TextBuffer()
    printRollingAverageKeyMetricsAndroid(metrics, options: options, printFunction: { buffer.append($0) })
    return try buffer.asENPAData(startDate: options.startDate)
}

// private func beaconEstimate(_ beaconCounts: [Int], _ clients: Int) -> Int {
//    var result = Array(repeating: 0, count: 9)
//    var total: Double = 0.0
//    for i in 0 ..< beaconCounts.count {
//        let j = i % 9
//        result[j] += beaconCounts[i]
//    }
//
//    for i in 0 ..< result.count {
//        let mostLikely = getMostLikelyPopulationCount(totalCount: Double(clients), sumPart: Double(result[i]))
//        total += mostLikely * Double(beaconCountEstimates[i])
//    }
//    return Int(total)
// }

let androidStartTime = dateParser.date(from: "2021-11-20 00:00:00")!

let iOSStartTime = dateParser.date(from: "2021-02-24 00:00:00")!

// "id": "sum-apple-com.apple.EN.UserNotification-us-ev-a31dc1d420e6fd3488f7a867a9268d5e31458108b6de0dcfeaa0fa7b5d96317b-202112160000-202112160800",
//  "sum": [
//    64487,
//    44,
//    20,
//    22,
//    22
//  ],
//  "aggregation_start_time": "2021-12-16T00:00:00.000Z",
//  "aggregation_end_time": "2021-12-16T08:00:00.000Z",
//  "generic_id": "notification",
//  "aggregation_id": "com.apple.EN.UserNotification",
//  "state_code": "ev",
//  "country_code": "us",
//  "data_provider": "apple",
//  "provider_version": "a31dc1d420e6fd3488f7a867a9268d5e31458108b6de0dcfeaa0fa7b5d96317b",
//  "epsilon": 8,
//  "hamming_weight": null,
//  "total_individual_clients": 64534

func maximumCategory(id _: String, fullId: String, start: Date, notificationStart: [Date], excludedHashes _: [Set<String>]) -> Int {
    let hash = fullId.components(separatedBy: "-")[5]
    for c in 1 ... 4 {
        if c < notificationStart.count {
            return c - 1
        }
        if start < notificationStart[c] {
            return c - 1
        }
    }
    return 4
}

struct RawMetrics {
    var metrics: [String: Metric] = [:]
    var excludedHashes: Set<String> = []
    var configuration: Configuration

    let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func createTempDirectory(_ component: String) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmm"
        let now = dateFormatter.string(from: Date())
        guard let region = configuration.region else { return nil }
        guard let tempDirURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(region)-\(component)-\(now)") else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }

        return tempDirURL
    }

    public mutating func addMetric(names: [String]) -> [String] {
        var errors: [String] = []
        for n in names {
            let json = getStat(metric: n, configuration: configuration)
            if let error = json["error"] as? String {
                logger.log("got error fetching ENPA: \(error, privacy: .public)")
                errors.append(error)
                continue
            }
            if let rawData = json["rawData"] as? [NSDictionary] {
                for m in rawData {
                    let provider = m["data_provider"] as? String ?? "?"
                    let clients = m["total_individual_clients"] as! Int
                    let maybeEpsilon = Double(truncating: m["epsilon"] as! NSNumber)
                    if provider == "google", maybeEpsilon != 8 {
                        continue
                    }
                    let epsilon = maybeEpsilon == 10 ? 10.2 : maybeEpsilon
                    let id = m["aggregation_id"] as! String
                    let fullId = m["id"] as! String
                    let genericId = n

                    let aggregationStartTime = m["aggregation_start_time"] as! String
                    let startTime = isoDateFormatter.date(from: aggregationStartTime)!
                    // print(dateParser.string(from: startTime))
                    let aggregationEndTime: String = m["aggregation_end_time"] as! String
                    let endTime = isoDateFormatter.date(from: aggregationEndTime)!
                    let sum = m["sum"] as! [Int]
                    addMetric(fullId: fullId, id: id, genericId: genericId, provider: provider, epsilon: epsilon, startTime: startTime, endTime: endTime, clients: clients, sum: sum)
                }
            } else {
                logger.log("raw data missing for \(n)")
                errors.append("raw data missing for \(n)")
            }
        }
        return errors
    }

    public mutating func addMetric(fullId: String, id: String, genericId: String, provider: String, epsilon: Double, startTime: Date, endTime _: Date, clients: Int, sum: [Int]) {
        if let startDate = configuration.startDate, startTime < startDate {
            return
        }

        if startTime < androidStartTime, !id.hasPrefix("com.apple") {
            return
        } else if startTime < iOSStartTime, id.hasPrefix("com.apple") {
            return
        }

        if id.hasPrefix("com.apple.EN"), let configStart = configuration.configStart {
            let hash = fullId.components(separatedBy: "-")[5]

            if startTime < configStart {
                if clients > 20 {
                    excludedHashes.insert(hash)
                }
                return
            } else if excludedHashes.contains(hash) {
                return
            }
        }

        if let prev = metrics[id] {
            prev.update(sum: sum, clients: clients, start: startTime)
        } else {
            metrics[id] = Metric(id: id, genericId: genericId, provider: provider, epsilon: epsilon, sum: sum, clients: clients, start: startTime)
        }
    }
}

func sum(_ x: [Int]?, _ y: [Int]) -> [Int] {
    guard let xx = x else {
        return y
    }
    return zip(xx, y).map { a, b in a + b }
}

func sum(_ x: [Double]?, _ y: [Double]) -> [Double] {
    guard let xx = x else {
        return y
    }
    return zip(xx, y).map { a, b in a + b }
}

// public func getMostLikelyPopulationCount(totalCount: Double, sumPart: Double) -> Double {
//    let mostLikelyPopulation = (sumPart - totalCount * p) / (1 - 2 * p)
//    // print("contributing population is \(mostLikelyPopulation) +/-  \(standardDeviation)")
//    return mostLikelyPopulation
// }

let dateParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = TimeZone(identifier: "UTC")!
    return formatter
}()

let calendar = Calendar.current

func dateAbstraction(_ date: Date) -> Date {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    // print("\(components)")
    // components.day = 1 + 3*(components.day!/3)
    // print("\(components)")
    let result = calendar.date(from: components)!
    // print("\(result)")
    return result
}

func sumChunks(_ a: [Int], chunkSize: Int) -> [Int] {
    var result: [Int] = []
    for i in stride(from: 0, to: a.count - 1, by: chunkSize) {
        result.append(a[i ..< i + chunkSize].reduce(0,+))
    }
    return result
}

let events = ["CodeVerified": [1, 2],
              "KeysUploaded": [1, 2],
              "PeriodicExposureNotificationInteraction": [1, 2],
              "com.apple.EN.CodeVerified": [1, 2],
              "com.apple.EN.KeysUploaded": [1, 2],
              "com.apple.EN.UserNotificationInteraction": [1, 5]]

public func userRiskSummary(likely: [Double]) -> [Double] {
    assert(likely.count == 512)
    var result = Array(repeating: 0.0, count: 26)
    for i in 1 ... 511 {
        let weightBucket = i / 64
        let sumBucket = i % 8
        let maxBucket = (i / 8) % 8
        if maxBucket < 2, sumBucket > 1 {
            // far & long
            result[24] += likely[i]
        }
        if maxBucket == 0 {
            if weightBucket > 0 {
                // non-infectious
                result[25] += likely[i]
            }
            continue
        }
        for j in 0 ... weightBucket {
            result[j] += likely[i]
        }
        for j in 8 ... (8 + maxBucket) {
            result[j] += likely[i]
        }
        for j in 16 ... (16 + sumBucket) {
            result[j] += likely[i]
        }
    }

    if false { print("likely: \(likely)")
        print("result: \(result)")
    }
    return result
}

let infectiousnessWeights = [100, 30, 0]

let standardAttenuationConfigs = [
    attenuationConfig("narrow net v1", thresholds: [55, 63, 75], weights: [175, 100, 33]),
    attenuationConfig("narrow net v2", thresholds: [55, 67, 80], weights: [150, 100, 40]),
    attenuationConfig("wide net", thresholds: [55, 70, 80], weights: [200, 100, 25]),
]

struct attenuationConfig {
    static func config(named: String) -> attenuationConfig {
        for c in standardAttenuationConfigs {
            if c.name == named {
                return c
            }
        }
        logger.error("No standard config named \(named)")

        return standardAttenuationConfigs[0]
    }

    let name: String
    let thresholds: [Int]
    let weights: [Int]
    init(_ name: String, thresholds: [Int], weights: [Int]) {
        self.name = name
        self.thresholds = thresholds
        self.weights = weights
    }

    func attenuationWeight(db: Int) -> Double {
        for i in 0 ..< thresholds.count {
            if db <= thresholds[i] {
                return Double(weights[i]) / 100.0
            }
        }
        return 0.0
    }

    func attenuationWeight(low: Int, high: Int) -> Double {
        let values = (low ... high).map { attenuationWeight(db: $0) }
        let sum = values.reduce(0,+)
        return sum / Double(values.count)
    }
}

public func attenuationSummary(likely: [Double]) -> [Double] {
    assert(likely.count == 1344)
    var result = Array(repeating: 0.0, count: 11 + standardAttenuationConfigs.count)
    for i in 0 ..< likely.count {
        let c = RiskParametersComponents(i)
        let duration = likely[i] * durationWeights[c.durationIndex]
        result[c.attenuationIndex] += duration
        result[8 + c.infectiousnessIndex] += duration
        let attenuationTop = c.attenuationIndex * 5 + 50
        if c.infectiousnessIndex > 0 {
            for i in 0 ..< standardAttenuationConfigs.count {
                let attenuationWeight = standardAttenuationConfigs[i].attenuationWeight(low: attenuationTop - 4, high: attenuationTop)
                let infectiousnessWeight = infectiousnessWeights[2 - c.infectiousnessIndex]
                result[11 + i] += duration * attenuationWeight * Double(infectiousnessWeight) / 100.0
            }
        }
    }
    return result
}

public class Metric: @unchecked Sendable {
    let epsilon: Double
    var p: Double {
        1 / (1 + exp(epsilon))
    }

    var pTimesOneMinusP: Double {
        p * (1 - p)
    }

    var sqrtPTimesOneMinusP: Double {
        exp(epsilon / 2) / (1 + exp(epsilon))
    }

    func getStandardDeviation(totalCount: Int) -> Double {
        sqrt(Double(totalCount)) * sqrtPTimesOneMinusP
    }

    func getVariance(totalCount: Int) -> Double {
        Double(totalCount) * pTimesOneMinusP
    }

    public func getMostLikelyPopulationCount(totalCount: Double, sumPart: Double) -> Double {
        let mostLikelyPopulation = (sumPart - totalCount * p) / (1 - 2 * p)
        return mostLikelyPopulation
    }

    public func getMostLikelyPopulationCountInt(totalCount: Int, sumPart: Int) -> Int {
        Int(getMostLikelyPopulationCount(totalCount: Double(totalCount), sumPart: Double(sumPart)).rounded())
    }

    public func getLikely(day: Date, scale: Double = 1.0) -> (clients: Int, sum: [Int], likely: [Double], variance: Double)? {
        guard
            let sum = sumByDay[day],
            let count = clientsByDay[day]
        else {
            return nil
        }
        let likely = getMostLikelyPopulationCount(totalCount: count, sumPart: sum, scale: scale)
        let variance = getVariance(totalCount: count)
        return (clients: count, sum: sum, likely: likely, variance: variance)
    }

    public func getMostLikelyPopulationCount(totalCount: Int, sumPart: [Int], scale: Double = 1.0) -> [Double] {
        (0 ..< sumPart.count).map { scale * getMostLikelyPopulationCount(totalCount: Double(totalCount), sumPart: Double(sumPart[$0])) }
    }

    var buckets: Int {
        sums.count
    }

    init(id: String, _ first: Metric, _ second: Metric) {
        assert(first.provider == second.provider)
        assert(first.genericId == second.genericId)
        assert(first.sums.count == second.sums.count)

        assert(first.epsilon == second.epsilon)
        epsilon = first.epsilon
        aggregation_id = id
        provider = first.provider
        genericId = first.genericId
        sums = zip(first.sums, second.sums).map { x, y in x + y }
        clients = first.clients + second.clients
        lastClientCount = first.lastClientCount + second.lastClientCount
        clientsByDay = first.clientsByDay
        clientsByDay.merge(second.clientsByDay, uniquingKeysWith: +)
        clientsByStart = first.clientsByStart
        clientsByStart.merge(second.clientsByStart, uniquingKeysWith: +)
    }

    init(id: String, genericId: String, provider: String, epsilon: Double, sum: [Int], clients: Int, start: Date) {
        let startDay = dateAbstraction(start)
        aggregation_id = id
        sums = sum
        self.genericId = genericId
        self.provider = provider
        self.epsilon = epsilon
        self.clients = clients
        lastClientCount = clients
        clientsByDay[startDay] = clients
        clientsByStart[start] = clients
        sumByStart[start] = sum
        sumByDay[startDay] = sum
    }

    func update(sum: [Int], clients: Int, start: Date) {
        let startDay = dateAbstraction(start)

        self.clients += clients
        assert(sums.count == sum.count)
        for i in 0 ..< sum.count {
            sums[i] += sum[i]
        }
        lastClientCount = clients
        clientsByDay[startDay, default: 0] += clients
        clientsByStart[start, default: 0] += clients

        if sumByStart[start] != nil {
            for i in 0 ..< sum.count {
                sumByStart[start]! [i] += sum[i]
            }
        } else {
            sumByStart[start] = sum
        }

        if sumByDay[startDay] != nil {
            for i in 0 ..< sum.count {
                sumByDay[startDay]! [i] += sum[i]
            }
        } else {
            sumByDay[startDay] = sum
        }
    }

    func swap(_ i: Int, _ j: Int) {
        let tmp = sums[i]
        sums[i] = sums[j]
        sums[j] = tmp
    }

    var likelyPopulation: [Double] {
        sums.map { getMostLikelyPopulationCount(totalCount: Double(clients), sumPart: Double($0)) }
    }

    var likelyPopulationEvents: Int? {
        guard let events = events[aggregation_id] else {
            return nil
        }
        let eventsRaw = events.map { sums[$0] }.reduce(0,+)
        return Int(getMostLikelyPopulationCount(totalCount: Double(clients * events.count), sumPart: Double(eventsRaw)))
    }

    public func likelyReporting(clients: Int, likely: [Int]) -> Int {
        switch aggregation_id {
        case "com.apple.EN.UserRisk":
            return likely.reduce(0,+)
        // return getMostLikelyPopulationCountInt(totalCount: clients, sumPart: sum) / likely.count
        case "com.apple.EN.BeaconCount":
            let firstGroup = likely[0 ... 8].reduce(0,+)
            let secondGroup = likely[9 ... 17].reduce(0,+)
            return clients - max(0, firstGroup - secondGroup)
        default:
            return clients
        }
    }

    var likelyPercentage: [Double] {
        likelyPercentage(clients, sums)
    }

    func likelyPercentage(_ clients: Int, _ sum: [Int]) -> [Double] {
        let clientCount = Double(clients)
        return sum.map { round4(max(0.0, getMostLikelyPopulationCount(totalCount: clientCount, sumPart: Double($0))) * 100.0 / clientCount) }
    }

    var standardDeviation: Double {
        getStandardDeviation(totalCount: clients)
    }

    func numOutside(sigma: Double) -> Int {
        let stdev = standardDeviation
        return sums.filter { getMostLikelyPopulationCount(totalCount: Double(clients), sumPart: Double($0)) >= sigma * stdev }.count
    }

    func printMetric() {
        print("\(aggregation_id),  clients: \(clients), stDev: \(round1(standardDeviation)), buckets: \(likelyPopulation.count), likely count for 0: \(-Int(getMostLikelyPopulationCount(totalCount: Double(clients), sumPart: 0.0)))")
        print("            raw counts: \(sums.prefix(10))")
        print("            raw counts sum: \(sums.reduce(0,+))")
        print("  mostLikelyPopulation: \(likelyPopulation.prefix(10))")
        print("         mostLikelySum: \(likelyPopulation.reduce(0,+))")
        if let e = likelyPopulationEvents {
            print("      mostLikelyEvents: \(e)")
        }
        print("           mostLikely%: \(likelyPercentage.prefix(10))")
        // printClientsByDay(after: Date(timeIntervalSinceNow: -24*60*60*10))
    }

    func printClientsByDay() {
        for (day, count) in clientsByDay.sorted(by: { $0.0 < $1.0 }) {
            print("\(dayFormatter.string(from: day)) \(nf6(count))")
        }
    }

    func printClientsByDay(after: Date) {
        for (day, count) in clientsByDay.filter({ $0.0 > after }).sorted(by: { $0.0 < $1.0 }) {
            print("\(dayFormatter.string(from: day)) \(nf6(count))")
        }
    }

    func printClientsByDay(against: Metric) {
        for (day, count) in clientsByDay.sorted(by: { $0.0 < $1.0 }) {
            if let other = against.clientsByDay[day] {
                print("\(dayFormatter.string(from: day)) \(nf6(count)) \(nf6(other)) \(nf6(count - other))")
            } else {
                print("\(dayFormatter.string(from: day)) \(nf6(count))")
            }
        }
    }

    func sumsByDay() -> String {
        let buf = TextBuffer()
        let bucketString = (0 ..< buckets).map { "\($0)" }.joined(separator: ",")
        let rawString = (0 ..< buckets).map { "r\($0)" }.joined(separator: ",")

        buf.append("date,devices,epsilon,stdev,\(bucketString),\(rawString)")
        for (day, sumBy) in sumByDay.sorted(by: { $0.0 < $1.0 }) {
            let count = clientsByDay[day]!
            let likelyValues = sumBy.map { getMostLikelyPopulationCount(totalCount: Double(count), sumPart: Double($0)) }
            let likely = likelyValues.map { "\(round2($0))" }
                .joined(separator: ",")

            let sums = sumBy.map { "\($0)" }
                .joined(separator: ",")
            let stdev = round2(getStandardDeviation(totalCount: count))
            buf.append("\(dayFormatter.string(from: day)),\(nf6(count)),\(epsilon),\(stdev),\(likely),\(sums)")
        }
        return buf.all
    }

    func printSumsByDay() {
        print("\(aggregation_id): ")
        for (day, sumBy) in sumByDay.sorted(by: { $0.0 < $1.0 }) {
            let count = clientsByDay[day]!
            let likely = "\(sumBy.map { round1(getMostLikelyPopulationCount(totalCount: Double(count), sumPart: Double($0))) })".dropFirst().dropLast()
            let raw = "\(sumBy)".dropFirst().dropLast()

            let stdev = round2(getStandardDeviation(totalCount: count))
            print("\(dayFormatter.string(from: day)), \(nf6(count)), \(epsilon), \(stdev),  \(likely),  \(raw)")
            // print("\(dayFormatter.string(from: day)) \(nf6( count)) \(likelyPercentage(count, sumBy))")
        }
        print()
    }

    func printSumsByStart() {
        for (start, sumBy) in sumByStart.sorted(by: { $0.0 < $1.0 }) {
            let count = clientsByStart[start]!
            let likely = "\(sumBy.map { round1(getMostLikelyPopulationCount(totalCount: Double(count), sumPart: Double($0))) })".dropFirst().dropLast()
            let raw = "\(sumBy)".dropFirst().dropLast()
            let stdev = round2(getStandardDeviation(totalCount: count))
            print("\(dayTimeFormatter.string(from: start)), \(nf6(count)),  \(stdev),  \(likely),  \(raw)")
            // print("\(dayFormatter.string(from: day)) \(nf6( count)) \(likelyPercentage(count, sumBy))")
        }
    }

    func printRawSumsByDay() {
        for (day, sumBy) in sumByDay.sorted(by: { $0.0 < $1.0 }) {
            let count = clientsByDay[day]!
            let likely = sumBy.map { getMostLikelyPopulationCount(totalCount: Double(count), sumPart: Double($0)) }

            print("\(dayFormatter.string(from: day)), \(nf6(count)),  \(sumBy), \(likely)")
        }
    }

    func printDailyRollingAverageClients(starts: [Date], scaleMetric: Metric) {
        var numStarts = 0.0
        var likely = Array(repeating: 0.0, count: buckets)
        var totalClients = 0
        for d in starts {
            guard let sumsForStart = sumByStart[d], let count = clientsByStart[d] else {
                continue
            }
            let scaleFactor = iOSScale(start: d, userRisk: scaleMetric)

            let likelyForStart = sumsForStart.map { scaleFactor * getMostLikelyPopulationCount(totalCount: Double(count), sumPart: Double($0)) }
            likely = sum(likely, likelyForStart)
            numStarts += 1.0
            totalClients += count
        }
        let scaleForDailyAverage = 3.0 / numStarts

        let dailyRollingAverage = likely.map { $0 * scaleForDailyAverage }

        print("\(dayFormatter.string(from: starts.last!)) clients: \(Double(totalClients) * scaleForDailyAverage), std: \(getStandardDeviation(totalCount: totalClients)), avg \(dailyRollingAverage)")
    }

    func printClientsAndMissingByDay() {
        for (day, sumBy) in sumByDay.sorted(by: { $0.0 < $1.0 }) {
            let count = clientsByDay[day]!
            let likely = sumBy.map { getMostLikelyPopulationCountInt(totalCount: count, sumPart: $0) }
            let reporting = likelyReporting(clients: count, likely: likely)
            print("\(dayFormatter.string(from: day)), \(nf6(count)),  \(nf6(reporting)), \(nf3(100 * reporting / count)), \(aggregation_id), \(sumBy.prefix(10)), \(likely.prefix(10)),")
            if false, aggregation_id == "com.apple.EN.BeaconCount" {
                let chunks = sumChunks(likely, chunkSize: 9)
                print("   \(100 * chunks[0] / count), \(100 * chunks[1] / count), \(chunks)")
            }
        }
    }

    func printSumsByDay(against: Metric) {
        for (day, sumBy) in sumByDay.sorted(by: { $0.0 < $1.0 }) {
            let count = clientsByDay[day]!
            if let other = against.sumByDay[day], let otherCount = against.clientsByDay[day] {
                let likely = sumBy.map { getMostLikelyPopulationCountInt(totalCount: count, sumPart: $0) }
                let likelyOther = other.map { getMostLikelyPopulationCountInt(totalCount: otherCount, sumPart: $0) }
                print("\(dayFormatter.string(from: day)) \(nf6(count)) vs \(nf6(otherCount)):  \(likely) vs \(likelyOther)")
            }
        }
    }

    func printClientsByStart() {
        for (day, count) in clientsByStart.sorted(by: { $0.0 < $1.0 }) {
            print("\(dayTimeFormatter.string(from: day)), \(count), \(aggregation_id)")
        }
    }

    func printClientsByStart(after: Date) {
        for (day, count) in clientsByStart.filter({ $0.0 > after }).sorted(by: { $0.0 < $1.0 }) {
            print("\(dayTimeFormatter.string(from: day)) \(count)")
        }
    }

    public let aggregation_id: String
    public let genericId: String
    public let provider: String
    public var sums: [Int]
    public var sumByDay: [Date: [Int]] = [:]
    public var sumByStart: [Date: [Int]] = [:]

    public var clientsByDay: [Date: Int] = [:]
    public var clientsByStart: [Date: Int] = [:]
    public var clients: Int
    var lastClientCount: Int
    public func clientsFor(start: Date) -> Int {
        if let clients = clientsByStart[start] {
            return clients
        }
        return 0
    }

    public func clientsFor(_ date: Date) -> Int {
        if let clients = clientsByDay[date] {
            return clients
        }
        return 0
    }
}

func iOSScale(start: Date, userRisk: Metric) -> Double {
    guard let sum = userRisk.sumByStart[start], let clients = userRisk.clientsByStart[start] else {
        return 1.0
    }
    let c = Double(clients)
    let likely = sum.map { userRisk.getMostLikelyPopulationCount(totalCount: c, sumPart: Double($0)) }
    let successful = likely.reduce(0,+)
    return c / successful
}

func iOSScale(day: Date, userRisk: Metric?) -> Double {
    guard let userRisk = userRisk, let sum = userRisk.sumByDay[day], let clients = userRisk.clientsByDay[day] else {
        return 1.0
    }
    let c = Double(clients)
    let likely = sum.map { userRisk.getMostLikelyPopulationCount(totalCount: c, sumPart: Double($0)) }
    let successful = likely.reduce(0,+)
    return c / successful
}

struct UserRiskAttribute {
    let shortName: String
    let name: String
    let shift: Int
    let buckets: [Int]
    func bucket(_ index: Int) -> Int { (index >> shift) & 7 }
    func likely(sums: [Int], clients: Int) -> [Int] {
        var result = Array(repeating: 0, count: 8)
        var counts = Array(repeating: 0, count: 8)
        for i in 0 ..< sums.count {
            if sums[i] == 0 {
                continue
            }
            result[i] += sums[i]
            counts[i] += clients
        }
        // return  getMostLikelyPopulationCount( totalCount: counts, sumPart: result )
        exit(1)
        return []
    }
}

let weightedDurationAttribute = UserRiskAttribute(shortName: "wd", name: "weightedDuration", shift: 6, buckets: [10, 20, 30, 50, 70, 90, 120, 999])
let maxScoreAttribute = UserRiskAttribute(shortName: "max", name: "maxScore", shift: 3, buckets: [3, 7, 11, 15, 19, 23, 27, 999])
let sumScoreAttribute = UserRiskAttribute(shortName: "sum", name: "sumScore", shift: 0, buckets: [40, 50, 60, 70, 80, 90, 120, 999])
let userRiskAttributes = [weightedDurationAttribute, maxScoreAttribute, sumScoreAttribute]

func describeAttributes(_ index: Int) {
    for a in userRiskAttributes {
        let bucket = a.bucket(index)

        if bucket == 0 {
            print("  0 <= \(a.name) <= \(a.buckets[bucket])")
        } else {
            print("  \(a.buckets[bucket - 1] + 1) <= \(a.name) <= \(a.buckets[bucket])")
        }
    }
}

func bound(_ name: String, _ limits: [Int], _ index: Int) {
    if index == 0 {
        print("  0 <= \(name) <= \(limits[index])")
    } else {
        print("  \(limits[index - 1]) < \(name) <= \(limits[index])")
    }
}

func bounds(_ values: [Int], interesting: Int, _ attribute: UserRiskAttribute) {
    print("\(attribute.name):")
    if values[0] >= interesting || true {
        print(" 0 <= \(max(0, values[0])) <= \(attribute.buckets[0])")
    }
    for i in 1 ..< values.count {
        if values[i] >= interesting || true {
            print(" \(attribute.buckets[i - 1] + 1) <=\(max(0, values[i])) <= \(attribute.buckets[i])")
        }
    }
    let total: Int = values.reduce(0,+)
    print("  total: \(total)")
}

func bounds(_ values: [Int], buckets: [Int], interesting: Int, clients: Int) {
    if values[0] >= interesting || true {
        print(" 0 <= \(max(0, values[0])) <= \(buckets[0])")
    }
    for i in 1 ..< values.count {
        if values[i] >= interesting || true {
            print(" \(buckets[i - 1] + 1) <= \(max(0, values[i])) <= \(buckets[i])")
        }
    }
    let total: Int = values.reduce(0,+)

    print("  total: \(total), \(Double(total) * 100.0 / Double(clients))%")
}

func zeroIfBelow(limit: Double, _ values: [Double]) -> [Double] {
    values.map { $0 < limit ? 0 : $0 }
}

let dayBuckets = [2, 4, 6, 8, 10, 12, 99]

let attenuationBuckets = [50, 55, 60, 65, 70, 75, 80, 255]
let durationBuckets = [5, 10, 15, 23, 30, 60, 120, 255]
let durationWeights = [3.0, 8.0, 12.0, 19.0, 26.0, 45.0, 80.0, 160.0]

struct RiskParametersComponents {
    let infectiousnessIndex: Int
    let dayIndex: Int
    let attenuationIndex: Int
    let durationIndex: Int
    init(_ i: Int) {
        let topPart = i >> 6
        infectiousnessIndex = topPart % 3
        dayIndex = topPart / 3
        attenuationIndex = (i >> 3) & 0x07
        durationIndex = i & 0x07
    }
}

protocol UserRiskParametersFilter {
    func match(_ c: RiskParametersComponents) -> Bool
}

struct CloseBriefContact: UserRiskParametersFilter {
    func match(_ c: RiskParametersComponents) -> Bool {
        if c.infectiousnessIndex == 0 {
            return false
        }
        if c.durationIndex > 0 {
            return false
        }
        if c.attenuationIndex > 2 {
            return false
        }
        return true
    }
}

func analyzeContactsByDay(_ riskParameters: Metric, _ filter: UserRiskParametersFilter) {
    print("CloseBriefContactsByDay: \(riskParameters.aggregation_id)")
    for (day, sumBy) in riskParameters.sumByDay.sorted(by: { $0.0 < $1.0 }) {
        let count = riskParameters.clientsByDay[day]!
        let likely = sumBy.map { riskParameters.getMostLikelyPopulationCount(totalCount: Double(count), sumPart: Double($0)) }
        var total = 0.0
        for i in 0 ..< likely.count {
            let c = RiskParametersComponents(i)
            if filter.match(c) {
                total += likely[i]
            }
        }
        let per100K = total / Double(count) * 100_000
        print("\(dayFormatter.string(from: day)), \(nf6(count)),    \(round1(total)),  \(round1(per100K))")
    }
    print()
}

func analyzeRiskParameters2(_ riskParameters: Metric) {
    print("\nRisk parameters: \(riskParameters.aggregation_id), \(riskParameters.clients) clients")
    let parameterSums = riskParameters.likelyPopulation
    var attenuationTotals = Array(repeating: 0.0, count: attenuationBuckets.count)

    for i in 0 ..< parameterSums.count {
        let c = RiskParametersComponents(i)
        attenuationTotals[c.attenuationIndex] += durationWeights[c.durationIndex] * parameterSums[i]
    }
}

func analyzeRiskParameters(_ riskParameters: Metric) {
    print("\nRisk parameters: \(riskParameters.aggregation_id), \(riskParameters.clients) clients")
    let parameterSums = riskParameters.likelyPopulation
    var comboParameters = Array(repeating: Array(repeating: 0.0, count: 8), count: 8)
    var meaningfulAttenuation = Array(repeating: Array(repeating: 0.0, count: durationBuckets.count), count: 3)
    var meaninglessAttenuation = Array(repeating: 0.0, count: 3)

    var day = Array(repeating: Array(repeating: 0.0, count: 7), count: 3)
    var infectiousness = Array(repeating: 0.0, count: 3)
    for i in 0 ..< parameterSums.count {
        let c = RiskParametersComponents(i)
        if c.infectiousnessIndex == 0 {
            continue
        }
        if riskParameters.aggregation_id == "histogramMetric", c.infectiousnessIndex == 0 {
            continue
        }
        if c.attenuationIndex == 7 {
            meaninglessAttenuation[c.infectiousnessIndex] += parameterSums[i]
        } else {
            meaningfulAttenuation[c.infectiousnessIndex][c.durationIndex] += parameterSums[i]
        }

        infectiousness[c.infectiousnessIndex] += parameterSums[i]
        day[c.infectiousnessIndex][c.dayIndex] += parameterSums[i]
        comboParameters[c.attenuationIndex][c.durationIndex] += parameterSums[i]
    }

    let infectiousLevelNames = ["none", "standard", "high"]
    let averageValue = parameterSums.reduce(0.0, +) / Double(parameterSums.count)
    print("\nriskParameters, element wise standard deviation = \(round1(riskParameters.standardDeviation))")

    for infectiousness in 0 ... 2 {
        if infectiousness == 0 { // riskParameters.aggregation_id == "histogramMetric",  {
            continue
        }
        print(infectiousLevelNames[infectiousness])
        print("meaningless attenuation: \(meaninglessAttenuation[infectiousness])")
        print("meaningfull attenuation: \(meaningfulAttenuation[infectiousness])")
        for dayIndex in 0 ..< dayBuckets.count {
            let startIndex = (dayIndex * 3 + infectiousness) * 8 * 8
            let values = parameterSums[startIndex ..< startIndex + 8 * 8]
            print("  day <= \(dayBuckets[dayIndex]): total = \(values.reduce(0,+)) \(values.map { $0 < 18 ? 0 : $0 })")
        }
    }
    // print("  \(parameterSums)")
    print("Average value: \(averageValue)")

    for dayIndex in 0 ... 2 {
        print("days (\(infectiousLevelNames[dayIndex]): \(day[dayIndex]), standard deviation =  \(round1(sqrt(8 * 8) * riskParameters.standardDeviation))")
    }
    print("infectiousness: \(infectiousness), standard deviation =  \(round1(sqrt(7 * 8 * 8) * riskParameters.standardDeviation))")

    print("attenuation x duration, standard deviation =  \(round1(sqrt(7) * riskParameters.standardDeviation))")
    print("       duration buckets: \(durationBuckets)")

    for x in 0 ..< comboParameters.count {
        print("attn <= \(attenuationBuckets[x]): total: \(comboParameters[x].reduce(0,+)), \(comboParameters[x])")
    }
}

let nFormatter6: NumberFormatter = {
    let nf = NumberFormatter()
    nf.formatWidth = 6
    return nf
}()

func nf6(_ x: Int) -> String {
    nFormatter6.string(for: x)!
}

let nf3: NumberFormatter = {
    let nf = NumberFormatter()
    nf.formatWidth = 3
    return nf
}()

func nf3(_ x: Int) -> String {
    nf3.string(for: x)!
}

let nf4: NumberFormatter = {
    let nf = NumberFormatter()
    nf.formatWidth = 4
    return nf
}()

extension String.StringInterpolation {
    mutating func appendInterpolation(f1: Double) {
        appendLiteral(round1(f1).description)
    }

    mutating func appendInterpolation(f2: Double) {
        appendLiteral(round2(f2).description)
    }

    mutating func appendInterpolation(f4: Double) {
        appendLiteral(round4(f4).description)
    }

    mutating func appendInterpolation(_ value: Int, _ formatter: NumberFormatter) {
        if let result = formatter.string(from: value as NSNumber) {
            appendLiteral(result)
        }
    }
}

let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")!
    return formatter
}()

let dayTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")!
    return formatter
}()

func round1(_ x: Double) -> Double {
    (x * 10).rounded() / 10.0
}

func round2(_ x: Double) -> Double {
    (x * 100).rounded() / 100.0
}

func percentage(_ x: Int, _ y: Int) -> Double {
    round4(Double(x) / Double(y))
}

func percentage(_ x: Double, _ y: Double) -> Double? {
    if y <= 0 {
        return nil
    }
    return x / y
}

func sar(_ sa: Double, _ nt: Double, std _: Double) -> Double? {
    if nt <= 10 {
        return nil
    }

    return sa / nt
}

func round4(_ x: Double) -> Double {
    (x * 10000).rounded() / 10000.0
}

func dotProduct(_ x: [Double], _ y: [Double]) -> Double {
    zip(x, y).map { a, b in a * b }.reduce(0,+)
}

func presentValue(_ name: String, _ x: Double?) -> String {
    if let x = x {
        if name.hasSuffix("rate") || name.hasSuffix("share") || name.contains("%") {
            return "\(Int((x * 100).rounded()))%"
        } else if x < 10, x > -10 {
            return "\((x * 100).rounded() / 100.0)"
        } else if x < 100, x > -100 {
            return "\((x * 10).rounded() / 10.0)"
        } else {
            return "\(Int(x.rounded()))"
        }

    } else {
        return "_"
    }
}

func presentValue(_: String, _ x: Int?) -> String {
    if let x = x {
        return "\(x)"
    } else {
        return "_"
    }
}

func showTrend(_ c: Column<Double>) -> String {
    let name = c.name
    let lastValue = presentValue(name, c.last!)
    let per100K = !name.contains("%") && !name.contains("/")
    let suffix = per100K ? " per 100K" : ""
    if c.count < 8 {
        return "  \(name): \(lastValue) \(suffix)"
    }
    let prevValue = presentValue(name, c[c.count - 8])
    return "  \(name): \(prevValue) → \(lastValue) \(suffix)"
}

func summarize(_ heading: String, _ enpa: DataFrame, categories: Int) -> [String] {
    let ntPerKu = enpa["nt/ku", Double.self]
    var ntNames = ["nt"]
    if categories > 1 {
        ntNames.append(contentsOf: (1 ... categories - 1).map { "nt\($0)%" })
    }
    let nt = ntNames.map { enpa[$0, Double.self] }
    let ntTrends = nt.map { showTrend($0) }
    if heading != "combined" {
        return [heading] + ntTrends
    }
    let output = [heading, showTrend(ntPerKu)] + ntTrends
    if enpa.hasColumn("est users from vc"), enpa.requireColumn("est users from vc", Int.self), enpa.requireColumn("vc ENPA %", Double.self) {
        let users = enpa["est users from vc", Int.self]
        let adoption = enpa["vc ENPA %", Double.self]
        if let lastUsers = users.last, let lastAdoption = adoption.last,
           let unwrappedLastUsers = lastUsers, let unwrappedLastAdoption = lastAdoption
        {
            return ["est users: \(unwrappedLastUsers)",
                    "ENPA opt-in:  \(Int((unwrappedLastAdoption * 100).rounded()))%", ""] + output
        }
    }

    return output
}
