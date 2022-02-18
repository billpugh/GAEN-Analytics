//
//  TabularData.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/6/22.
//

import Foundation
import TabularData

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

    func makeRow(_ row: [Any]) -> [String: Any?] {
        print("appendRow")
        let columns = self.columns
        var myMap: [String: Any?] = [:]
        for (c, v) in zip(columns, row) {
            myMap[c.name] = v
        }
        return myMap
    }

    func average(_ sum: Int, _ days: Int) -> Int {
        (sum + days / 2) / days
    }

    func rollingAvg(days: Int) -> DataFrame {
        var result = DataFrame()
        for c in columns {
            print(c.name)
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

    func rollingSum(days: Int) -> DataFrame {
        var result = DataFrame()
        for c in columns {
            print(c.name)
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
                    let sum = slice.reduce(0, sum)

                    rSum.append(sum)
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
                    let sum = slice.reduce(nil, sum)

                    rSum.append(sum)
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
        for c in columns {
            let name = c.name
            if name.hasPrefix("left.") {
                renameColumn(name, to: String(name.dropFirst("left.".count)))
            } else if name.hasPrefix("right.") {
                renameColumn(name, to: String(name.dropFirst("right.".count)))
            }
        }
    }

    mutating func replaceUnderscoreWithSpace() {
        for c in columns {
            let name = c.name
            renameColumn(name, to: String(name.replacingOccurrences(of: "_", with: " ")))
        }
    }

    mutating func addColumnDifference(_ name1: String, _ name2: String, giving: String) {
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        var result = column1 - column2
        result.name = giving
        // calculated.append(giving)
        append(column: result)
    }

    mutating func copyColumn(_ name1: String, giving: String) {
        var column1 = self[name1, Int.self]
        column1.name = giving

        append(column: column1)
    }

    mutating func addColumnSum(_ name1: String, _ name2: String, giving: String) {
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        var result = column1 + column2
        result.name = giving
        // calculated.append(giving)
        append(column: result)
    }

    mutating func addColumnPercentage(_ name1: String, _ name2: String, giving: String) {
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        let resultData = zip(column1, column2).map { ratio($0, $1) }
        append(column: Column(name: giving, contents: resultData))
    }
}

func makeColumn<T>(_ name: String, _ value: T) -> AnyColumn {
    Column<T>(name: name, contents: [value]).eraseToAnyColumn()
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
