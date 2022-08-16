//
//  durationAnalysis.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 7/24/22.
//

import Foundation
import TabularData

func median(_ array: [Double]) -> Double {
    let sorted = array.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid] + sorted[mid - 1]) / 2
    } else {
        return sorted[mid]
    }
}

func interpolateMinutes(_ m1: DurationMeasurement, _ m2: DurationMeasurement, percentile: Double) -> Double {
    // print("\(m1.percentile) ... \(percentile) ... \(m2.percentile)")
    let d1 = percentile - m1.percentile
    let d12 = m2.percentile - m1.percentile
    let d2 = m2.percentile - percentile
    return round2((d2 * m1.minutes + d1 * m2.minutes) / d12)
}

func interpolatePercentile(_ m1: DurationMeasurement, _ m2: DurationMeasurement, minutes: Double) -> Double {
    // print("\(m1.percentile) ... \(percentile) ... \(m2.percentile)")
    let d1 = minutes - m1.minutes
    let d12 = m2.minutes - m1.minutes
    let d2 = m2.minutes - minutes
    return round4((d2 * m1.percentile + d1 * m2.percentile) / d12)
}

func sorted(_ x: Double?, _ y: Double?) -> Bool {
    if let x = x, let y = y {
        return x < y
    }
    return x != y && x == nil
}

func same(_ x: Double?, _ y: Double?) -> Bool {
    if let x = x, let y = y {
        return abs(x - y) < 0.001
    }
    return x == y
}

struct DurationMeasurement: Codable {
    init(_ minutes: Int?, _ percentile: Double?) {
        self.minutes = Double(minutes!)
        self.percentile = percentile!
    }

    init(_ minutes: Double?, _ percentile: Double?) {
        self.minutes = minutes!
        self.percentile = percentile!
    }

    let minutes: Double
    let percentile: Double
}

func addInterpolation(minutes: Double, _ values: [DurationMeasurement]) -> [DurationMeasurement] {
    if let percentile = interpolate(minutes: minutes, measurements: values) {
        var result = values
        result.append(DurationMeasurement(minutes, percentile))
        return result.sorted(by: { $0.minutes < $1.minutes })
    }
    return values
}

public func computeDurationSummary(_ r: DataFrame.Row, highInfectiousnessWeight: Int) throws -> DataFrame {
    print("highInfectiousnessWeight = \(highInfectiousnessWeight)")
    let hiWeight = Double(highInfectiousnessWeight) / 100.0
    let wdBuckets = [10, 20, 30, 50, 70, 90, 120]
    let sumBuckets = [40, 50, 60, 70, 80, 90, 120]
    let maxBuckets = [7, 11, 15, 19, 23, 27]
    var wdValues = wdBuckets.map { minutes in
        DurationMeasurement(minutes, r["wd > \(minutes)min %", Double.self]!)
    }
    let sumValues = sumBuckets.map { minutes in
        DurationMeasurement(minutes, r["sum > \(minutes)min %", Double.self]!)
    }
    let maxValues = maxBuckets.map { minutes in
        DurationMeasurement(minutes, r["max > \(minutes)min %", Double.self]!)
    }

    wdValues = addInterpolation(minutes: 7.5, wdValues)

    wdValues = addInterpolation(minutes: 15, wdValues)
    wdValues = addInterpolation(minutes: 60, wdValues)

    for dm in wdValues {
        print("\(dm.minutes), \(dm.percentile)")
    }

    let wdPercentiles = wdValues.map(\.percentile)
    let wdMaxPercentile = wdPercentiles.max()!
    let wdMinPercentile = wdPercentiles.min()!
    let sumPercentiles = sumValues.map(\.percentile)
    let sumMaxPercentile = sumPercentiles.max()!
    let sumMinPercentile = sumPercentiles.min()!
    let minPercentile = max(wdMinPercentile, sumMinPercentile)
    let maxPercentile = min(wdMaxPercentile, sumMaxPercentile)

    let percentiles = [Double](stride(from: maxPercentile, through: minPercentile, by: -(maxPercentile - minPercentile) / 20))

    let wdDurations = percentiles.map { interpolate(percentile: $0, measurements: wdValues) }
    let sumDurations = percentiles.map { interpolate(percentile: $0, measurements: sumValues) }
    print(percentiles)
    print(wdDurations)
    print(sumDurations)

    let ratios = zip(sumDurations, wdDurations).map { $0 / $1 }

    let med = median(ratios)

    wdValues = addInterpolation(minutes: 5 / med, wdValues)

    wdValues = addInterpolation(minutes: 7.5 / med, wdValues)
    wdValues = addInterpolation(minutes: 10 / med, wdValues)
    wdValues = addInterpolation(minutes: 15 / med, wdValues)
    wdValues = addInterpolation(minutes: 30 / med, wdValues)
    wdValues = addInterpolation(minutes: 60 / med, wdValues)

    var csvRows: [String] = ["minutes,max %,sum %,scaled wd %,wd %,hip sum %", "0.0,1.0, , 1.0, 1.0, 1.0", "3.0,1.0,,1.0,,"]
    csvRows.append("\(round2(3.0 / med)), , ,, 1.0, ")
    csvRows.append("\(round2(3.0 / med * hiWeight)), , ,, ,1.0")

    for m in wdValues {
        csvRows.append("\(round2(med * m.minutes)),,,\(m.percentile),,")
        csvRows.append("\(m.minutes),,,,\(m.percentile),")
        csvRows.append("\(round2(m.minutes * hiWeight)),,,,,\(m.percentile)")
    }
    for m in sumValues {
        csvRows.append("\(m.minutes),,\(m.percentile),,,")
    }
    for m in maxValues {
        csvRows.append("\(m.minutes),\(m.percentile),,,,")
    }

    let csv = csvRows.joined(separator: "\n")
    print(csv)
    var df = try DataFrame(csvData: csv.data(using: .utf8)!)
    df.sort(on: "minutes")

    var df2 = compactRows(column: "minutes", df.sorted(on: "minutes"))
    print((try? String(data: df2.csvRepresentation(), encoding: .utf8))!)
    fillIn(&df2, "wd %")
    fillIn(&df2, "scaled wd %")
    fillIn(&df2, "sum %")
    fillIn(&df2, "max %")
    fillIn(&df2, "hip sum %")
    if let csv = try? String(data: df2.csvRepresentation(), encoding: .utf8) {
        print("csv")
        print(csv)
    }
    let df3 = DataFrame(df2.filter { desirableRow($0) })
    if let csv = try? String(data: df3.csvRepresentation(), encoding: .utf8) {
        print("csv")
        print(csv)
    }

    return df3
}

func desirableRow(_ row: DataFrame.Row) -> Bool {
    let minutes = round4(row["minutes", Double.self]!)

    if minutes == 0 {
        return false
    }
    if minutes == 3 || minutes == 5 || minutes == 7.5 || minutes == 15 || minutes == 27 {
        return true
    }
    return minutes == 10 * (minutes / 10).rounded()
}

func interpolate(percentile: Double, measurements: [DurationMeasurement]) -> Double {
    var prev = measurements.first!
    for next in measurements[1 ..< measurements.count] {
        // print("  \(prev.percentile) ... \(percentile) ... \(next.percentile)")

        if prev.percentile >= percentile, percentile >= next.percentile {
            return interpolateMinutes(prev, next, percentile: percentile)
        }
        prev = next
    }
    return prev.minutes
}

func interpolate(minutes: Double, measurements: [DurationMeasurement]) -> Double? {
    var prev = measurements.first!
    if prev.minutes >= minutes {
        return interpolatePercentile(DurationMeasurement(0, 1.0), prev, minutes: minutes)
    }
    for next in measurements[1 ..< measurements.count] {
        if prev.minutes < minutes, minutes <= next.minutes {
            // print("minutes  \(round2(prev.minutes)) ... \(round2(minutes)) ... \(round2(next.minutes))")

            let p = interpolatePercentile(prev, next, minutes: minutes)
            // print("      %  \(round4(prev.percentile)) ... \(round4(p)) ... \(round4(next.percentile))")
            return p
        }
        prev = next
    }

    return nil
}

func compactRows(column: String, _ df: DataFrame) -> DataFrame {
    var result = DataFrame(df.prefix(0))

    var prev = df.rows[0]
    // print(prev[column, Double.self])
    for row in df.rows[1 ..< df.rows.count] {
        // print(row[column, Double.self])
        if same(prev[column, Double.self], row[column, Double.self]) {
            // print("combining")
            for c in df.columns {
                if prev[c.name, Double.self] == nil,
                   let rValue = row[c.name, Double.self]
                {
                    prev[c.name] = rValue
                }
            }
        } else {
            result.append(row: prev)
            // print("pushing, result has \(result.rows.count) rows")
            prev = row
        }
    }
    result.append(row: prev)
    return result
}

func fillIn(_ df: inout DataFrame, _ percentileName: String) {
    let minutes = df["minutes", Double.self]
    var percentile = df[percentileName, Double.self]
    var i = 0
    var j = 0
    while i + 1 < percentile.count {
        if percentile[i] == nil || percentile[i + 1] != nil {
            i += 1
            continue
        }
        j = max(j, i + 2)

        while j < percentile.count, percentile[j] == nil {
            j += 1
        }
        if j >= percentile.count {
            break
        }
        print("filling in at \(i) \(j), minutes.count = \(minutes.count), percentile.count = \(percentile.count) ")

        let m1 = DurationMeasurement(minutes[i], percentile[i])
        let m2 = DurationMeasurement(minutes[j], percentile[j])
        let v = interpolatePercentile(m1, m2, minutes: minutes[i + 1]!)
        percentile[i + 1] = v
        // print("filling in at \(i) \(j) with \(round4(v))")

        i = i + 1
    }
    // print(percentile)
    df[percentileName, Double.self] = percentile
}

private func getRow(_ minutes: Double, _ df: DataFrame) -> DataFrame.Row? {
    let c = df["minutes", Double.self]
    guard let baseline = c.firstIndex(of: minutes) else {
        return nil
    }

    let row = df.rows[baseline]

    return row
}

private func get(_ column: String, _ row: DataFrame.Row) -> Double {
    row[column, Double.self]!
}

private func get(_ column: String, alt: String = "", _ row: DataFrame.Row, baseline: DataFrame.Row) -> Double? {
    var b = baseline[column, Double.self]
    if b == nil || b == 0.0 {
        b = baseline[alt, Double.self]
    }

    guard let b = b, b > 0 else {
        return nil
    }

    if let v = row[column, Double.self] {
        return v / b

    } else if !alt.isEmpty, let v = row[alt, Double.self] {
        return v / b
    }

    return nil
}

private func get(_ minutes: Double, _ column: String, _ df: DataFrame) -> Double? {
    guard let row = getRow(minutes, df) else {
        return nil
    }
    return get(column, row)
}

public func format(minutes: Double) -> String {
    if minutes == minutes.rounded() {
        return "\(Int(minutes)) minutes"
    }
    return String(format: "%.1f minutes", minutes)
}

func format(percent: Double) -> String {
    String(format: "%2d%%", Int((percent * 100.0).rounded()))
}

func format(percentChange: Double) -> String {
    if percentChange > 0 {
        return String(format: "%2d%% more", Int((percentChange * 100.0).rounded()))
    } else {
        return String(format: "%2d%% less", Int((-percentChange * 100.0).rounded()))
    }
}

public func summarizeDurations(_ df: DataFrame, baselineDuration: Double) -> [String] {
    guard let baseline = getRow(baselineDuration, df) else {
        return ["No baseline durations found"]
    }

    var results = [
        "Using a perDaySum baseline of \(format(minutes: baselineDuration))",
        "    \(format(percent: get("scaled wd %", baseline))) of all detected encounters result in notifications",
        "    \(format(percent: get("hip sum %", baseline))) of detected encounters with HIP result in notifications",
        "        HIP = people who are highly infectious at time of encounter",
        "",
        "Of the encounters that now result in a notification:",
    ]
    for d in [10.0, 15.0, 30.0, 60.0, 120.0] {
        if d > baselineDuration {
            if let row = getRow(d, df), let v = get("sum %", alt: "scaled wd %", row, baseline: baseline) {
                results.append("    \(format(percent: v)) have a perDaySum of \(format(minutes: d)) or more")
            }
        }
    }
    results.append("")
    for d in [7.5, 10.0, 15.0, 30.0] {
        if d != baselineDuration {
            if let row = getRow(d, df) {
                var header = false
                if let v = get("scaled wd %", row, baseline: baseline) {
                    results.append("with a perDaySum threshold of \(format(minutes: d))")

                    results.append("    \(format(percentChange: v - 1)) notifications would occur")
                    header = true
                }
                if let v = get("hip sum %", row, baseline: baseline) {
                    if !header {
                        results.append("with a perDaySum threshold of \(format(minutes: d))")
                        header = true
                    }
                    results.append("    \(format(percentChange: v - 1)) notifications from HIP would occur")
                }

                if header {
                    results.append("")
                }
            }
        }
    }

    results.removeLast()

    return results
}
