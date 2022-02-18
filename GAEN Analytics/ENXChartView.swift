//
//  ENXChartView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/14/22.
//

import SwiftUI
import TabularData

struct ENXChartsView: View {
    let charts: [ChartOptions]
    var body: some View {
        ForEach(charts) { c in
            ENXChartView(title: c.title, lineChart: LineChart(data: c.data, columns: c.columns, maxBound: c.maxBound))
        }
    }
}

extension View {
    func snapshot() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view

        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: targetSize)

        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

struct ENXChartView: View {
    @EnvironmentObject var analysisState: AnalysisState
    let title: String
    let lineChart: LineChart
    @MainActor init(title: String, lineChart: LineChart) {
        self.title = title
        self.lineChart = lineChart
        let exportTitle = title + ".csv"

        if let csv = AnalysisState.exportToFileDocument(name: exportTitle, dataframe: lineChart.data) {
            csvDocument = csv
        } else {
            csvDocument = CSVFile(name: "none", Data())
            print("set empty csvDocument")
        }

        if let url = AnalysisState.exportToURL(name: exportTitle, dataframe: lineChart.data) {
            csvItem = CSVItem(url: url,
                              title: title)
        } else {
            csvItem = CSVItem(url: nil, title: "tmp.csv")
        }
    }

    @State var showingShare: Bool = false

    let csvDocument: CSVFile

    let csvItem: CSVItem

    @State private var showingPopover = false
    @State private var showingExport = false
//
    var body: some View {
        Section(header:
            HStack {
                Text(title)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut) {
                        showingPopover.toggle()
                    }
                }) { Image(systemName: "info.circle") }
                    .padding(.horizontal)

                Button(action: {
                    #if targetEnvironment(macCatalyst)
                        analysisState.export(csvFile: csvDocument)
                    #else
                        // print("csv document \(csvDocument.name) has \(csvDocument.data.count) bytes")

                        showingShare = true
                    #endif
                }) {
                    Image(systemName: "square.and.arrow.up")
                }.animation(.easeInOut, value: showingShare)
            }.font(.headline) // HStack
        ) {
            if showingPopover {
                Text(markdown(file: title)).transition(.scale)
            }
            // TestView()

            lineChart.frame(height: 300)

        }.textCase(nil)
    }
}

//
// struct ENXChartView_Previews: PreviewProvider {
//    static var previews: some View {
//        ENXChartView(title: "Title")
//    }
// }
