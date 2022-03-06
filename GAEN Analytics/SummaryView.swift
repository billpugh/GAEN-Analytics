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
        List {
            Section(header: Text("GAEN Analytics for\u{00a0}\(state.region)"
            ).font(.title)) {
                AnalysisProgressView()
                if analysisState.available {
                    Button(action: { Task(priority: .userInitiated) {
                        await AnalysisTask().analyze(config: state.config, result: analysisState)
                    }
                    }) { Text("Update analytics").font(.headline)
                    }
                }
            }.textCase(.none)

            Section(header: TopicView(topic: "ENCV").padding(.top)) {
                Text(analysisState.encvSummary).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            ENXChartsView(charts: analysisState.encvCharts)
            Section(header: TopicView(topic: "ENPA").padding(.top)) {
                Text(analysisState.enpaSummary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            ENXChartsView(charts: analysisState.enpaCharts)
        }.listStyle(GroupedListStyle())
            .onAppear {
                if !state.setupNeeded && !analysisState.inProgress && !analysisState.available {
                    Task(priority: .userInitiated) {
                        await AnalysisTask().analyze(config: state.config, result: analysisState)
                    }
                }
            }

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
