//
//  ZipFunctionality.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 2/24/22.
//

import Foundation

import os.log
import TabularData
import ZIPFoundation

private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "archive")

extension RawMetrics {
    func writeMetrics() -> URL? {
        guard let url = createTempDirectory("rawENPA") else { return nil }

        do {
            for (name, metric) in metrics {
                let file = url.appendingPathComponent("\(name).csv")
                let text = metric.sumsByStart()
                try text.write(toFile: file.path, atomically: false, encoding: .utf8)
            }
        } catch {
            logger.error("Unable to write raw metrics: \(error.localizedDescription)")
            return nil
        }
        let fileManager = FileManager()
        let destination = URL(fileURLWithPath: url.path + ".zip")
        do {
            try fileManager.zipItem(at: url, to: destination)
        } catch {
            logger.error("Creation of ZIP archive failed with error: \(error.localizedDescription)")
        }
        return destination
    }
}
