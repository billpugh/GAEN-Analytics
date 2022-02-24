//
//  TabularData.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/6/22.
//

import Foundation
import os.log
import TabularData

private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "tabular")
func sum(_ x: Int?, _ y: Int?) -> Int? {
    guard let x = x else {
        return y
    }
    return x + (y ?? 0)
}

func sum(_ x: [Int]?, _ y: [Int]?) -> [Int]? {
    guard let x = x else {
        return y
    }
    guard let y = y else {
        return x
    }
    return zip(x, y).map(+)
}

extension DataFrame {
    func ratio(_ x: Int?, _ y: Int?) -> Double? {
        guard let x = x, let y = y, y > 0 else {
            return nil
        }

        return Double(x) / Double(y)
    }

    func hasColumn(_ name: String) -> Bool {
        indexOfColumn(name) != nil
    }

    func requireColumn(_ name: String, _ type: Any.Type) -> Bool {
        let result = hasColumn(name)
        if !result {
            logger.error("Missing column \(name, privacy: .public)")
            return false
        }
        let c: AnyColumn = self[name]
        if c.wrappedElementType != type {
            logger.error("Column \(name, privacy: .public) has type \(c.wrappedElementType, privacy: .public), expected \(type, privacy: .public)")
            return false
        }
        return true
    }

    func requireColumn(_ name: String) -> Bool {
        let result = hasColumn(name)
        if !result {
            logger.error("Missing column \(name, privacy: .public)")
        }
        return result
    }

    func makeRow(_ row: [Any]) -> [String: Any?] {
        logger.info("appendRow")
        let columns = self.columns
        var myMap: [String: Any?] = [:]
        for (c, v) in zip(columns, row) {
            myMap[c.name] = v
        }
        return myMap
    }

    func average(_ sum: Int, _ days: Int) -> Int {
        guard days > 0 else {
            logger.error("asked for average over \(days, privacy: .public) days average")
            return sum
        }
        return (sum + days / 2) / days
    }

    func rollingAvg(days: Int) -> DataFrame {
        logger.info("Computing \(days, privacy: .public) rolling average")
        var result = DataFrame()
        for c in columns {
            // print(c.name)
            if c.wrappedElementType == Date.self {
                let c = c.assumingType(Date.self)
                result.append(column: Column(c[days ..< c.count]))
            } else if c.wrappedElementType == Int.self {
                let c = c.assumingType(Int.self)
                let range = (days ..< c.count)
                var rSum: [Int?] = []
                for end in range {
                    let slice = c[end - days ..< end]
                    // print(slice)

                    if let sum = slice.reduce(0, sum) {
                        rSum.append(average(sum, days))
                    } else {
                        rSum.append(nil)
                    }
                }
                let r = Column(name: c.name, contents: rSum)
                // print(r.count)
                // print(r)
                result.append(column: r)
            } else if c.wrappedElementType == [Int].self {
                let c = c.assumingType([Int].self)
                let range = (days ..< c.count)
                var rSum: [[Int]?] = []
                for end in range {
                    let slice = c[end - days ..< end]
                    // print(slice)
                    if let sum = slice.reduce(nil, sum) {
                        rSum.append(sum.map { average($0, days) })
                    } else {
                        rSum.append(nil)
                    }
                }
                let r = Column(name: c.name, contents: rSum)
                // print(r.count)
                // print(r)
                result.append(column: r)
            }
            // print(result.rows.count)
            // print(result)
        }
        return result
    }

    mutating func removeJoinNames() {
        logger.info("removing join names")
        var count = 0
        for c in columns {
            let name = c.name
            if name.hasPrefix("left.") {
                let newName = String(name.dropFirst("left.".count))
                    logger.info("renaming \(name, privacy: .public) to \(newName, privacy: .public)")
                    renameColumn(name, to: newName)
                    count += 1
                
            } else if name.hasPrefix("right.") {
                let newName = String(name.dropFirst("right.".count))
                    logger.info("renaming \(name, privacy: .public) to \(newName, privacy: .public)")
                    renameColumn(name, to: newName)
                    count += 1
                
            }
        }
        logger.info("removed \(count) join names")
    }

    func checkUniqueColumnNames() {
        logger.info("Checking for unique column names")
        var seen : Set<String> = []
        for c in columns {
            let name = c.name
            if seen.contains(name) {
                logger.error("DataFrame contains two columns named \(name)")
            } else {
                seen.insert(name)
            }
        }
    }
    
    mutating func replaceUnderscoreWithSpace() {
        logger.info("replacing underscore with spaces in column names")
        for c in columns {
            let name = c.name
            if !name.contains("_") {
                continue
            }
            let newName = name.replacingOccurrences(of: "_", with: " ")
            if hasColumn(newName) {
                logger.error("DataFrame has columns named both \(name, privacy: .public) and \(newName, privacy: .public)")
                continue
            }
            renameColumn(name, to: String(name.replacingOccurrences(of: "_", with: " ")))
        }
        logger.info("completed replacing underscore with spaces in column names")
    }

    private func remove(_ x: Int?) -> Int? {
        if Int.random(in: 0 ... 19) > 0 {
            return x
        }
        if Int.random(in: 0 ... 1) > 0 {
            return 0
        }

        return nil
    }

    private func remove(_ x: Double?) -> Double? {
        if Int.random(in: 0 ... 19) > 0 {
            return x
        }
        if Int.random(in: 0 ... 1) > 0 {
            return 0.0
        }

        return nil
    }

    private func remove(_ x: [Int]?) -> [Int]? {
        if Int.random(in: 0 ... 19) > 0 {
            return x
        }

        return nil
    }

    mutating func removeRandomElements() {
        let introduceNoise = false
        guard introduceNoise else {
            return
        }

        logger.info("removing random elemements")
        for c in columns {
            if c.wrappedElementType == Int.self {
                var c = c.assumingType(Int.self)
                c.transform { remove($0) }
            }
            if c.wrappedElementType == Double.self {
                var c = c.assumingType(Double.self)
                c.transform { remove($0) }
            }
            if c.wrappedElementType == [Int].self {
                var c = c.assumingType([Int].self)
                c.transform { remove($0) }
            }
        }
    }

    mutating func addColumnDifference(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnDifference(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1), requireColumn(name2) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        var result = column1 - column2
        result.name = giving
        // calculated.append(giving)
        append(column: result)
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func copyColumn(_ name1: String, giving: String) {
        logger.info("copyColumn(\(name1, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1) else {
            return
        }
        var column1 = self[name1, Int.self]
        column1.name = giving

        append(column: column1)
    }

    mutating func addColumnSum(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnSum(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1), requireColumn(name2) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        var result = column1 + column2
        result.name = giving
        // calculated.append(giving)
        append(column: result)
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnPercentage(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnPercentage(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard hasColumn(name1), hasColumn(name2) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        let resultData = zip(column1, column2).map { ratio($0, $1) }
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }
}

func makeColumn<T>(_ name: String, _ value: T) -> AnyColumn {
    logger.info("makeColumn(\(name, privacy: .public))")

    return Column<T>(name: name, contents: [value]).eraseToAnyColumn()
}

class TextBuffer {
    var text: [String] = []
    func append(_ s: String) {
        text.append(s)
    }

    var all: String {
        text.joined(separator: "\n")
    }

    func clear() {
        text = []
    }

    func asENPAData() throws -> DataFrame {
        logger.info("converting ENPA TextBuffer to DataFrame")
        var readingOptions = CSVReadingOptions()
        readingOptions.addDateParseStrategy(
            Date.ParseStrategy(
                format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
                locale: Locale(identifier: "en_US"),
                timeZone: TimeZone(abbreviation: "GMT")!
            ))
        return try DataFrame(csvData: all.data(using: .utf8)!,
                             types: ["date": .date,
                                     "days": .integer,
                                     "vc count": .integer,
                                     "kc count": .integer,
                                     "nc count": .integer,
                                     "dec count": .integer],
                             options: readingOptions)
    }
}
