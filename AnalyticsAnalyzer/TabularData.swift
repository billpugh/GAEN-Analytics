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

    func ratio(excluding x: Int?, _ y: Int?) -> Double? {
        guard let x = x, let y = y, y > 0 else {
            return nil
        }
        return Double(y - x) / Double(y)
    }

    func share(_ x: Int?, _ y: Int?) -> Double? {
        guard let x = x, let y = y, y > 0 else {
            return nil
        }
        return Double(x) / Double(x + y)
    }

    func ratio(_ x: Double?, _ y: Double?) -> Double? {
        guard let x = x, let y = y, y > 0.1 else {
            return nil
        }
        return x / y
    }

    func hasColumn(_ name: String) -> Bool {
        indexOfColumn(name) != nil
    }

    func requireColumns(_ names: String...) {
        var hasAll = true
        for n in names {
            if !requireColumn(n) {
                hasAll = false
            }
        }
        if !hasAll {
            logger.log("\(columns.count) Columns: \(columns.map(\.name))")
        }
    }

    func emptyPrefix(_ name: String) -> Int {
        let c: AnyColumn = self[name]
        for (i, v) in c.enumerated() {
            if v != nil {
                return i
            }
        }
        return c.count
    }

    func emptySuffix(_ name: String) -> Int {
        let c: AnyColumn = self[name]
        for (i, v) in c.enumerated().reversed() {
            if v != nil {
                return c.count - i - 1
            }
        }
        return c.count
    }

    func emptyPrefix(_ names: [String]) -> Int {
        names.map { emptyPrefix($0) }.min()!
    }

    func emptySuffix(_ names: [String]) -> Int {
        names.map { emptySuffix($0) }.min()!
    }

    @discardableResult func requireColumn(_ name: String, _ type: Any.Type) -> Bool {
        guard requireColumn(name) else {
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

    func makeMap(_ row: [Any]) -> [String: Any?] {
        logger.info("appendRow")
        let columns = columns
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
                let d = Column(c[days - 1 ..< c.count])
                // print("\(d.count) dates")
                // print(d)

                result.append(column: d)
            } else if c.wrappedElementType == Int.self {
                let c = c.assumingType(Int.self)
                let range = (days - 1 ..< c.count)
                var rSum: [Int?] = []
                for end in range {
                    let slice = c[end - days + 1 ... end]
                    // print("slice \(end-days+1)... \(end) has \(slice.count) elements")
                    // print(slice)

                    if let sum = slice.reduce(0, sum) {
                        rSum.append(average(sum, days))
                    } else {
                        rSum.append(nil)
                    }
                }
                let r = Column(name: c.name, contents: rSum)
                // print("\(r.count) ints")
                // print(r)
                result.append(column: r)
            } else if c.wrappedElementType == [Int].self {
                let c = c.assumingType([Int].self)
                let range = (days - 1 ..< c.count)
                var rSum: [[Int]?] = []
                for end in range {
                    let slice = c[end - days + 1 ... end]
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

    func checkUniqueColumnNames() {
        logger.info("Checking for unique column names")
        var seen: Set<String> = []
        for c in columns {
            let name = c.name
            if seen.contains(name) {
                logger.error("DataFrame contains two columns named \(name)")
            } else {
                seen.insert(name)
            }
        }
    }

    func makeMap<T1: Hashable, T2>(key: String, _ type1: T1.Type, value: String, _ type2: T2.Type) -> [T1: T2] {
        let keys = self[key, type1]
        let values = self[value, type2]
        var map: [T1: T2] = [:]
        for (k, v) in zip(keys, values) {
            if let k = k, let v = v {
                map[k] = v
            }
        }
        return map
    }

    func printColumnNames() {
        print("\(columns.count) Columns: \(columns.map(\.name))")
    }

    @discardableResult mutating func addColumn<T1>(_ column: String, _ type1: T1.Type, newName: String? = nil,
                                                   from: DataFrame) -> Column<T1>
    {
        addColumn(column, type1, newName: newName, from: from, join: "date", Date.self)
    }

    mutating func addOptionalColumn<T1>(_ column: String, _ type1: T1.Type, newName: String? = nil,
                                        from: DataFrame?)
    {
        guard let from = from, from.hasColumn(column) else {
            printColumnNames()
            return
        }
        addColumn(column, type1, newName: newName, from: from, join: "date", Date.self)
    }

    @discardableResult mutating func addColumn<T1, T2: Hashable>(_ column: String, _ type1: T1.Type, newName: String? = nil,
                                                                 from: DataFrame, join: String, _ type2: T2.Type) -> Column<T1>
    {
        let newName = newName ?? column
        removeIfPresent(newName)

        guard requireColumn(join, type2), from.requireColumn(column, type1),
              from.requireColumn(join, type2)
        else {
            logger.error("invalid request to join column \(column, privacy: .public) joining on \(join, privacy: .public)")
            let newColumn = Column<T1>(name: newName, capacity: 0)
            append(column: newColumn)
            return newColumn
        }

        let map = from.makeMap(key: join, type2, value: column, type1)

        let joinColumn = self[join, type2]

        let newColumnValues = joinColumn.map { $0 == nil ? nil : map[$0!] }
        let newColumn = Column(name: newName, contents: newColumnValues)
        append(column: newColumn)
        return newColumn
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
        guard requireColumn(name1, Int.self), requireColumn(name2, Int.self) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        var result = column1 - column2
        result.name = giving
        removeIfPresent(giving)
        // calculated.append(giving)
        append(column: result)
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnDifferenceDouble(_ name1: String, _ name2: String, giving: String) -> Bool {
        logger.info("addColumnDifference(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Double.self), requireColumn(name2, Double.self) else {
            return false
        }
        let column1 = self[name1, Double.self]
        let column2 = self[name2, Double.self]
        var result = column1 - column2
        result.name = giving
        removeIfPresent(giving)
        // calculated.append(giving)
        append(column: result)
        logger.info("added column \(giving, privacy: .public)")
        return true
    }

    mutating func removeIfPresent(_ name: String) {
        if hasColumn(name) {
            removeColumn(name)
        }
    }

    mutating func copyColumn(_ name1: String, giving: String) {
        logger.info("copyColumn(\(name1, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1) else {
            return
        }
        removeIfPresent(giving)
        var column1 = self[name1, Int.self]
        column1.name = giving

        append(column: column1)
    }

    mutating func copyColumnIntArray(_ name1: String, giving: String) {
        logger.info("copyColumn(\(name1, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1) else {
            return
        }
        removeIfPresent(giving)
        var column1 = self[name1, [Int].self]
        column1.name = giving

        append(column: column1)
    }

    mutating func addColumnSum(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnSum(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Int.self), requireColumn(name2, Int.self) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        var result = column1 + column2
        removeIfPresent(giving)
        result.name = giving
        // calculated.append(giving)
        append(column: result)
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnSumDouble(_ name1: String, _ name2: String, giving: String) -> Bool {
        logger.info("addColumnSum(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Double.self), requireColumn(name2, Double.self) else {
            return false
        }
        let column1 = self[name1, Double.self]
        let column2 = self[name2, Double.self]
        var result = column1 + column2
        removeIfPresent(giving)
        result.name = giving
        // calculated.append(giving)
        append(column: result)
        logger.info("added column \(giving, privacy: .public)")
        return true
    }

    mutating func addColumnComputation(_ name1: String, _ name2: String, giving: String, _ function: (Double?, Int?) -> Double?) {
        logger.info("addColumComputation(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Double.self), requireColumn(name2, Int.self) else {
            return
        }
        let column1 = self[name1, Double.self]
        let column2 = self[name2, Int.self]
        let resultData = zip(column1, column2).map { function($0, $1) }
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addRollingMedianInt(_ name1: String, giving: String, days: Int) {
        logger.info("addRollingMedianInt(\(name1, privacy: .public),  giving \(giving, privacy: .public))")
        guard requireColumn(name1, Int.self) else {
            return
        }
        let column1: [Int?] = self[name1, Int.self]
        let resultData = rollingMedian(column1, length: days)
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addRollingMedianDouble(_ name1: String, giving: String, days: Int) {
        logger.info("addRollingMedianDouble(\(name1, privacy: .public),  giving \(giving, privacy: .public))")
        guard requireColumn(name1, Double.self) else {
            return
        }
        let column1: [Double?] = self[name1, Double.self]
        let resultData = rollingMedian(column1, length: days)
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addRollingSumInt(_ name1: String, giving: String) {
        logger.info("addRollingMedianInt(\(name1, privacy: .public),  giving \(giving, privacy: .public))")
        guard requireColumn(name1, Int.self) else {
            return
        }
        let column1: [Int?] = self[name1, Int.self]
        let resultData = rollingSum(column1)
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addRollingSumDouble(_ name1: String, giving: String) {
        logger.info("addRollingMedianInt(\(name1, privacy: .public),  giving \(giving, privacy: .public))")
        guard requireColumn(name1, Double.self) else {
            return
        }
        let column1: [Double?] = self[name1, Double.self]
        let resultData = rollingSum(column1)
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnPercentage(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnShare(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Int.self), requireColumn(name2, Int.self) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        let resultData = zip(column1, column2).map { ratio($0, $1) }
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnPercentage(excluding name1: String, _ name2: String, giving: String) {
        logger.info("addColumnShare(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Int.self), requireColumn(name2, Int.self) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        let resultData = zip(column1, column2).map { ratio(excluding: $0, $1) }
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnShare(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnPercentage(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Int.self), requireColumn(name2, Int.self) else {
            return
        }
        let column1 = self[name1, Int.self]
        let column2 = self[name2, Int.self]
        let resultData = zip(column1, column2).map { share($0, $1) }
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    mutating func addColumnShareZX(_ name1: String, _ name2: String, giving: String) {
        logger.info("addColumnPercentage(\(name1, privacy: .public), \(name2, privacy: .public), giving \(giving, privacy: .public))")
        guard requireColumn(name1, Double.self), requireColumn(name2, Double.self) else {
            return
        }
        let column1 = self[name1, Double.self]
        let column2 = self[name2, Double.self]
        let resultData = zip(column1, column2).map { ratio($0, $1) }
        append(column: Column(name: giving, contents: resultData))
        logger.info("added column \(giving, privacy: .public)")
    }

    func merge<T: Hashable>(key: String, _ type: T.Type, adding: DataFrame) -> DataFrame {
        let newKeys = adding[key, type]
        var newKeyValues: Set<T> = []
        for k in newKeys {
            if let k = k {
                newKeyValues.insert(k)
            }
        }
        let reused = filter(on: key, type) { $0 != nil && !newKeyValues.contains($0!) }
        var result = DataFrame(reused)
        result.append(adding)
        logger.log("Reused \(reused.rows.count) of \(rows.count), added \(adding.rows.count)")
        return result
    }
}

func makeColumn<T>(_ name: String, _ value: T) -> AnyColumn {
    logger.info("makeColumn(\(name, privacy: .public))")

    return Column<T>(name: name, contents: [value]).eraseToAnyColumn()
}

func rollingSum(_ a: [Int?]) -> [Int] {
    var total = 0
    return a.map { total += ($0 ?? 0); return total }
}

func rollingSum(_ a: [Double?]) -> [Double] {
    var total = 0.0
    return a.map { total += ($0 ?? 0); return total }
}

func median<T>(_ a: ArraySlice<T>) -> T? where T: Numeric, T: Comparable {
    if a.isEmpty {
        return nil
    }
    let sorted = a.sorted()
    let count = sorted.count
    // 0 - nil
    // 1 - 0
    // 2 - 0, 1
    // 3 - 1
    // 4 - 1,2
    if count % 2 == 0 {
        // Even number of items - return the mean of two middle values
        let leftIndex = count / 2 - 1
        let leftValue = sorted[leftIndex]
        return leftValue
    } else {
        // Odd number of items - take the middle item.
        return sorted[count / 2]
    }
}

func median<T>(_ a: [T?], ending: Int, count: Int) -> T? where T: Numeric, T: Comparable {
    let values = a[0 ... ending].compactMap { $0 }.suffix(count)

    let result = median(values)
    return result
}

func rollingMedian<T>(_ a: [T?], length: Int) -> [T?] where T: Numeric, T: Comparable {
    (0 ..< a.count).map { median(a, ending: $0, count: length) }
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

    func asENPAData(startDate: Date? = nil) throws -> DataFrame {
        logger.info("converting ENPA TextBuffer to DataFrame")
        if false {
            for s in text.prefix(10) {
                print(s)
            }
        }
        var readingOptions = CSVReadingOptions()
        readingOptions.addDateParseStrategy(
            Date.ParseStrategy(
                format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
                locale: Locale(identifier: "en_US"),
                timeZone: TimeZone(abbreviation: "GMT")!
            ))
        do {
            let result = try DataFrame(csvData: all.data(using: .utf8)!,
                                       types: ["date": .date,
                                               "days": .integer,
                                               "vc count": .integer,
                                               "kc count": .integer,
                                               "nc count": .integer,
                                               "dec count": .integer],
                                       options: readingOptions)
            if let startDate = startDate {
                let df = DateFormatter()
                df.dateStyle = .full
                df.timeStyle = .full
                df.timeZone = TimeZone(identifier: "UTC")!
                print("filtering rows to \(df.string(from: startDate))")
                let filtered = DataFrame(result.filter { date($0) >= startDate })
                let dates = filtered["date", Date.self]
                print("first date: \(df.string(from: dates.first!!))")
                return filtered
            }
            return result
        } catch {
            print("Error: \(error.localizedDescription)")
            print(all)
            throw error
        }
    }
}
