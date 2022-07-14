//
//  main.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 1/28/21.
//

import Foundation
import TabularData

print("Hello world")

let url = URL(fileURLWithPath: "/Users/pugh/Downloads/tmp.csv")
let csv = try! Data(contentsOf: url)

let df = try! DataFrame(csvData: csv, options: readingOptions)
print(df)

let average = df.rollingAvg(days: 7)
print(average)
