//
//  SummaryView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/9/22.
//

import SwiftUI

struct SummaryView: View {
    @ObservedObject var state = SetupState.shared

    @ObservedObject var analysisState = AnalysisState.shared
    var body: some View {
        Form {
            Section(header: Text("ENCV").font(.title)) {
                Text(analysisState.encvSummary)
            }
            ENXChartsView(charts: analysisState.encvCharts)
            Section(header: Text("ENPA").font(.title)) {
                Text(analysisState.enpaSummary)
            }
            ENXChartsView(charts: analysisState.enpaCharts)
        }.textCase(nil)

            .environmentObject(analysisState)
            .fileExporter(isPresented: $analysisState.csvExportReady, document: analysisState.csvExport, contentType: .commaSeparatedText) { result in
                switch result {
                case let .success(url):
                    print("Saved to \(url)")
                case let .failure(error):
                    print(error.localizedDescription)
                }
            }
    }
}

struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryView()
    }
}
