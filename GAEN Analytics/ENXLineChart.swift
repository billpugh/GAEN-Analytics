//
//  ENXLineChart.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/14/22.
//

import Foundation

import Charts
import os.log
import SwiftUI
import TabularData
private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "Charts")

func twoDigitsPrecisionCeiling(_ v: Double) -> Double {
    var value = v
    var multiplier = 1.0
    while value < 10 {
        value = value * 10
        multiplier /= 10
    }
    while value > 100 {
        value /= 10
        multiplier *= 10
    }
    return value.rounded(.up) * multiplier
}

func oneDigitsPrecisionCeiling(_ v: Double) -> Double {
    var value = v
    var multiplier = 1.0
    while value > 10 {
        value /= 10
        multiplier *= 10
    }
    return value.rounded(.up) * multiplier
}

let threeDigitsPrecision: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.usesSignificantDigits = true
    nf.maximumSignificantDigits = 3
    return nf
}()

class MyValueFormatter: NSObject, ValueFormatter {
    func stringForValue(_: Double, entry _: ChartDataEntry, dataSetIndex _: Int, viewPortHandler _: ViewPortHandler?) -> String {
        ""
    }
}

class RoundedAxisValueFormatter: NSObject, AxisValueFormatter {
    public func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        "\(threeDigitsPrecision.string(from: value as NSNumber)!)"
    }
}

class IntAxisValueFormatter: NSObject, AxisValueFormatter {
    public func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        "\(Int(value.rounded()))"
    }
}

class PercentAxisValueFormatter: NSObject, AxisValueFormatter {
    public func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        let percent = value * 100
        if percent >= 10 {
            return "\(Int((value * 100).rounded()))%"
        }
        return String(format: "%.1f%%", percent)
    }
}

class DateAxisFormatter: NSObject, AxisValueFormatter {
    let formatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!
        let dateFormatString = DateFormatter.dateFormat(fromTemplate: "M/d", options: 0, locale: Locale.current)!
        dateFormatter.dateFormat = dateFormatString
        return dateFormatter
    }()

    public func stringForValue(_ value: Double, axis _: AxisBase?) -> String {
        // print(value)
        let date = Date(timeIntervalSince1970: value)
        return formatter.string(from: date)
    }
}

func day(date: Date) -> Int {
    Int(date.timeIntervalSince1970) / 86400
}

let darkYellow = UIColor(red: 0.9, green: 0.9, blue: 0, alpha: 1)

protocol GAENChart: UIViewRepresentable where UIViewType == LineChartView {}

struct LineChart: GAENChart {
    // NOTE: No Coordinator or delegate functions in this example
    let lineChart = LineChartView()
    init(data: DataFrame, columns: [String], minBound: Double? = nil, maxBound: Double? = nil) {
        let emptyPrefix = data.emptyPrefix(columns)
        // print("rows: \(data.rows.count), empty prefix: \(emptyPrefix)")

        let pruned = data.suffix(data.rows.count - emptyPrefix)
        let emptySuffix = data.emptySuffix(columns)
        // print("rows: \(pruned.rows.count), empty suffix: \(emptySuffix)")
        self.data = pruned.prefix(max(0, pruned.rows.count - emptySuffix))
        self.columns = columns

        let allColors: [UIColor] = [.blue, .red, .green, darkYellow, .purple, .cyan, .magenta, .orange]
        // let allColors: [UIColor] = [.systemBlue, .systemRed, .systemGreen, .systemYellow, .systemPurple, .systemCyan, .systemIndigo, .systemOrange]

        var c: [String: UIColor] = [:]
        for (i, name) in columns.enumerated() {
            c[name] = allColors[i]
        }
        colors = c

        self.maxBound = maxBound
        self.minBound = minBound

        lastDay = Double(day(date: data["date", Date.self].last!!))
    }

    var data: DataFrame.Slice
    var lastDay: Double

    let maxBound: Double?
    let minBound: Double?
    let columns: [String]
    let colors: [String: UIColor]

    func makeUIView(context _: Context) -> LineChartView {
        lineChart
    }

    func updateUIView(_ uiView: LineChartView, context _: Context) {
        let yMax = setChartData(uiView)
        configureChart(uiView)
        formatXAxis(xAxis: uiView.xAxis)
        formatLeftAxis(leftAxis: uiView.leftAxis, yMax: yMax)

        if columns.count == 1 {
            uiView.legend.enabled = false
        } else {
            formatLegend(legend: uiView.legend)
        }

        uiView.notifyDataSetChanged()
    }

    func makeDataEntry(_ date: Date?, _ y: Double?) -> ChartDataEntry? {
        guard let date = date else {
            return nil
        }
        guard let y = y else {
            return ChartDataEntry(x: date.timeIntervalSince1970, y: 0)
        }

        return ChartDataEntry(x: date.timeIntervalSince1970, y: y)
    }

    func makeDataEntryBlanks(_ date: Date?, _ y: Double?) -> ChartDataEntry? {
        guard let date = date else {
            return nil
        }
        guard let y = y else {
            return ChartDataEntry(x: date.timeIntervalSince1970, y: -100.0)
        }

        return ChartDataEntry(x: date.timeIntervalSince1970, y: y)
    }

    func makeDataEntry(_ date: Date?, _ s: String?) -> ChartDataEntry? {
        guard let date = date else {
            return nil
        }
        guard let s = s, s.count > 0, let y = Double(s) else {
            return ChartDataEntry(x: date.timeIntervalSince1970, y: 0)
        }

        return ChartDataEntry(x: date.timeIntervalSince1970, y: y)
    }

    func makeDataEntry(_ date: Date?, _ y: Int?) -> ChartDataEntry? {
        guard let date = date else {
            return nil
        }
        guard let y = y else {
            return ChartDataEntry(x: date.timeIntervalSince1970, y: 0)
        }

        return ChartDataEntry(x: date.timeIntervalSince1970, y: Double(y))
    }

    func makeDateSet(column: String) -> LineChartDataSet? {
        let days = data["date", Date.self]
        let chartData: [ChartDataEntry]
        let cc = data[column]
        if cc.wrappedElementType == Double.self {
            let c = data[column, Double.self]
            if column.starts(with: "vcr") {
                chartData = zip(days, c).compactMap { makeDataEntryBlanks($0, $1) }
            } else {
                chartData = zip(days, c).compactMap { makeDataEntry($0, $1) }
            }
        } else if cc.wrappedElementType == Int.self {
            let c = data[column, Int.self]
            chartData = zip(days, c).compactMap { makeDataEntry($0, $1) }
        } else if cc.wrappedElementType == String.self {
            print("Column \(column) has type String")
            let c = data[column, String.self]
            chartData = zip(days, c).compactMap { makeDataEntry($0, $1) }

        } else {
            logger.error("Column \(column) has unexpected type \(cc.wrappedElementType)")
            chartData = []
        }
        if chartData.isEmpty {
            return nil
        }

        let dataSet = LineChartDataSet(entries: chartData)
        if dataSet.yMax == 0 {
            return nil
        }

        formatDataSet(dataSet: dataSet, label: column, color: colors[column]!)

        return dataSet
    }

    func isSar(_ label: String) -> Bool {
        if label.hasPrefix("sar"), label.count == 5 {
            return true
        }
        if label.hasPrefix("xsar"), label.count == 6 {
            return true
        }
        return false
    }

    func setChartData(_ lineChart: LineChartView) -> Double {
        let dataSets = columns.compactMap { makeDateSet(column: $0) }

        let yMaxAll = dataSets.map(\.yMax).reduce(-Double.infinity, max)

        let yMax: Double
        let firstLabel = columns[0]
        if dataSets.count == 3, isSar(firstLabel) {
            let yMaxSar = dataSets[0].yMax
            let yMaxSarMinus = dataSets[2].yMax
            yMax = oneDigitsPrecisionCeiling(max(0.06, min(0.2, yMaxSar, 1.5 * yMaxSarMinus)) * 100.0) / 100.0
        } else {
            yMax = twoDigitsPrecisionCeiling(yMaxAll)
        }
        let lineChartData = LineChartData(dataSets: dataSets)
        lineChart.data = lineChartData

        return yMax
    }

    func formatDataSet(dataSet: LineChartDataSet, label: String, color: UIColor) {
        dataSet.label = "\(label)  "
        dataSet.colors = [color]
        dataSet.valueColors = [color]

        dataSet.circleColors = [color]
        if label.starts(with: "vcr") {
            dataSet.drawCirclesEnabled = true
            dataSet.circleRadius = 3
            dataSet.lineWidth = 0
        } else if label.hasPrefix("sar"), label.count == 5, false {
            dataSet.drawCirclesEnabled = true
            dataSet.circleRadius = 4
            dataSet.lineWidth = 0
        } else if label.hasSuffix("stdev") {
            dataSet.lineWidth = 2
            dataSet.drawCirclesEnabled = false
        } else {
            dataSet.lineWidth = 4
            dataSet.drawCirclesEnabled = false
        }
        // dataSet.circleRadius = 0
        dataSet.circleHoleRadius = 0
        dataSet.mode = .linear
        // dataSet.lineDashLengths = [4]
        dataSet.drawValuesEnabled = false
        dataSet.drawIconsEnabled = false

        dataSet.valueFormatter = MyValueFormatter()
        dataSet.valueFont = UIFont.systemFont(ofSize: 24)
    }

    func configureChart(_ lineChart: LineChartView) {
        lineChart.noDataText = "No Data"
        lineChart.drawGridBackgroundEnabled = true
        lineChart.gridBackgroundColor = UIColor.tertiarySystemFill
        lineChart.drawBordersEnabled = true
        lineChart.rightAxis.enabled = false
        lineChart.dragEnabled = false
        lineChart.drawMarkers = false
        lineChart.highlightPerTapEnabled = false
        lineChart.highlightPerDragEnabled = false
        lineChart.setScaleEnabled(false)
    }

    func formatXAxis(xAxis: XAxis) {
        xAxis.labelPosition = .bottom

        xAxis.valueFormatter = DateAxisFormatter()
        xAxis.labelTextColor = .darkGray
        xAxis.labelFont = UIFont.boldSystemFont(ofSize: 12)
        xAxis.granularity = 7
        // xAxis.entries = [-21,-14,-7,0]
        // Setting the max and min make sure that the markers are visible at the edges
        // xAxis.axisMaximum = 12
        // let weeks = 9
        // xAxis.axisMinimum = Double(-7*weeks)
        xAxis.setLabelCount(5, force: true)
    }

    func formatLeftAxis(leftAxis: YAxis, yMax: Double) {
        leftAxis.labelTextColor = .darkGray
        leftAxis.axisMinimum = 0

        if let maxBound = maxBound {
            leftAxis.axisMaximum = min(maxBound, yMax)
        } else {
            leftAxis.axisMaximum = yMax
        }

        leftAxis.labelFont = UIFont.boldSystemFont(ofSize: 12)

        if leftAxis.axisMaximum <= 1.5 {
            leftAxis.valueFormatter = PercentAxisValueFormatter()
        } else {
            leftAxis.valueFormatter = RoundedAxisValueFormatter()
        }
    }

    func formatLegend(legend: Legend) {
        legend.textColor = UIColor.black
        legend.font = UIFont.boldSystemFont(ofSize: 14)
        legend.horizontalAlignment = .center
        legend.verticalAlignment = .top
        legend.drawInside = false
        legend.yOffset = 24.0
    }
}

struct XYLineChart: GAENChart {
    // NOTE: No Coordinator or delegate functions in this example
    let lineChart = LineChartView()
    init(data: DataFrame, x: String, columns: [String], minBound: Double? = nil, maxBound: Double? = nil) {
        xName = x
        self.data = data
        self.columns = columns

        let allColors: [UIColor] = [.blue, .red, .green, darkYellow, .purple, .cyan, .magenta, .orange]
        // let allColors: [UIColor] = [.systemBlue, .systemRed, .systemGreen, .systemYellow, .systemPurple, .systemCyan, .systemIndigo, .systemOrange]

        var c: [String: UIColor] = [:]
        for (i, name) in columns.enumerated() {
            c[name] = allColors[i]
        }
        colors = c

        self.maxBound = maxBound
        self.minBound = minBound
    }

    var data: DataFrame

    let maxBound: Double?
    let minBound: Double?
    let columns: [String]
    let colors: [String: UIColor]
    let xName: String

    func makeUIView(context _: Context) -> LineChartView {
        lineChart
    }

    func updateUIView(_ uiView: LineChartView, context _: Context) {
        let yMax = setChartData(uiView)
        configureChart(uiView)
        formatXAxis(xAxis: uiView.xAxis)
        formatLeftAxis(leftAxis: uiView.leftAxis, yMax: yMax)

        if columns.count == 1 {
            uiView.legend.enabled = false
        } else {
            formatLegend(legend: uiView.legend)
        }

        uiView.notifyDataSetChanged()
    }

    func makeDataEntry(_ x: Double?, _ y: Double?) -> ChartDataEntry? {
        guard let x = x else {
            return nil
        }
        guard let y = y else {
            return ChartDataEntry(x: x, y: -100)
        }

        return ChartDataEntry(x: x, y: y)
    }

    func makeDateSet(column: String) -> LineChartDataSet? {
        let days = data[xName, Double.self]
        let chartData: [ChartDataEntry]
        let cc = data[column]
        if cc.wrappedElementType == Double.self {
            let c = data[column, Double.self]
            chartData = zip(days, c).compactMap { makeDataEntry($0, $1) }
            // print("got \(chartData.count) entries for \(column)")
        } else {
            logger.error("Column \(column) has unexpected type \(cc.wrappedElementType)")
            chartData = []
        }
        if chartData.isEmpty {
            // print("no data")
            return nil
        }

        let dataSet = LineChartDataSet(entries: chartData)
        if dataSet.yMax == 0 {
            // print("yMax is nil")
            return nil
        }

        formatDataSet(dataSet: dataSet, label: column, color: colors[column]!)
        // print("Got dataset for \(column), x is \(dataSet.xMin)...\(dataSet.xMax), y is \(dataSet.yMin)...\(dataSet.yMax)")
        return dataSet
    }

    func setChartData(_ lineChart: LineChartView) -> Double {
        let dataSets = columns.compactMap { makeDateSet(column: $0) }

        let yMaxAll = dataSets.map(\.yMax).reduce(-Double.infinity, max)

        let yMax = twoDigitsPrecisionCeiling(yMaxAll)

        let lineChartData = LineChartData(dataSets: dataSets)
        lineChart.data = lineChartData

        return yMax
    }

    func formatDataSet(dataSet: LineChartDataSet, label: String, color: UIColor) {
        dataSet.label = "\(label)  "
        dataSet.colors = [color]
        dataSet.valueColors = [color]

        dataSet.circleColors = [color]

        dataSet.lineWidth = 4
        dataSet.drawCirclesEnabled = false

        // dataSet.circleRadius = 0
        dataSet.circleHoleRadius = 0
        dataSet.mode = .linear
        // dataSet.lineDashLengths = [4]
        dataSet.drawValuesEnabled = false
        dataSet.drawIconsEnabled = false

        dataSet.valueFormatter = MyValueFormatter()
        dataSet.valueFont = UIFont.systemFont(ofSize: 24)
    }

    func configureChart(_ lineChart: LineChartView) {
        lineChart.noDataText = "No Data"
        lineChart.drawGridBackgroundEnabled = true
        lineChart.gridBackgroundColor = UIColor.tertiarySystemFill
        lineChart.drawBordersEnabled = true
        lineChart.rightAxis.enabled = false
        lineChart.dragEnabled = false
        lineChart.drawMarkers = false
        lineChart.highlightPerTapEnabled = false
        lineChart.highlightPerDragEnabled = false
        lineChart.setScaleEnabled(false)
    }

    func formatXAxis(xAxis: XAxis) {
        xAxis.labelPosition = .bottom

        xAxis.valueFormatter = IntAxisValueFormatter()
        xAxis.labelTextColor = .darkGray
        xAxis.labelFont = UIFont.boldSystemFont(ofSize: 12)
        // xAxis.granularity = 7
        // xAxis.entries = [-21,-14,-7,0]
        // Setting the max and min make sure that the markers are visible at the edges
        // xAxis.axisMaximum = 12
        // let weeks = 9
        // xAxis.axisMinimum = Double(-7*weeks)
        // xAxis.setLabelCount(5, force: true)
    }

    func formatLeftAxis(leftAxis: YAxis, yMax: Double) {
        leftAxis.labelTextColor = .darkGray
        leftAxis.axisMinimum = 0
        if let maxBound = maxBound {
            leftAxis.axisMaximum = min(maxBound, yMax)
        } else {
            leftAxis.axisMaximum = yMax
        }

        leftAxis.labelFont = UIFont.boldSystemFont(ofSize: 12)

        if leftAxis.axisMaximum <= 1.5 {
            leftAxis.valueFormatter = PercentAxisValueFormatter()
        } else {
            leftAxis.valueFormatter = RoundedAxisValueFormatter()
        }
    }

    func formatLegend(legend: Legend) {
        legend.textColor = UIColor.black
        legend.font = UIFont.boldSystemFont(ofSize: 14)
        legend.horizontalAlignment = .center
        legend.verticalAlignment = .top
        legend.drawInside = false
        legend.yOffset = 24.0
    }
}
