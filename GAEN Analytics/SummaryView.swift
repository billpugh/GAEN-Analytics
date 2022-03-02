//
//  SummaryView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/9/22.
//

import os.log
import SwiftUI
private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "SummaryView")

struct SummaryView: View {
    @ObservedObject var state = SetupState.shared

    @ObservedObject var analysisState = AnalysisState.shared
    var body: some View {
        Form {
            Section(header: TopicView(topic: "ENCV")) {
                Text(analysisState.encvSummary).textSelection(.enabled)
            }
            ENXChartsView(charts: analysisState.encvCharts)
            Section(header: TopicView(topic: "ENPA")) {
                Text(analysisState.enpaSummary).textSelection(.enabled)
            }
            ENXChartsView(charts: analysisState.enpaCharts)
        }.textCase(nil)

            .environmentObject(analysisState)
        #if targetEnvironment(macCatalyst)
            .fileExporter(isPresented: $analysisState.csvExportReady, document: analysisState.csvExport, contentType: .commaSeparatedText) { result in
                switch result {
                case let .success(url):
                    print("Saved to \(url)")
                case let .failure(error):
                    logger.error("Error exporting file \(error.localizedDescription, privacy: .public)")
                }
            }
        #endif
    }
}

struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryView()
    }
}
