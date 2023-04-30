//
//  ENXChartView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/14/22.
//

import SwiftUI
import TabularData
import os.log

private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "ENXChartsView")

struct ENXChartsView: View {
    let charts: [ChartOptions]
    @MainActor func chartView(_ c: ChartOptions) -> ENXChartView {
        if c.doubleDouble {
            return ENXChartView(title: c.title, data: c.data, chart: XYLineChart(data: c.data, x: "days since exposure", columns: c.columns, maxBound: c.maxBound))
        }
        if c.title == "Relative risk for notifications" {
            // print("Found \(c.title)")
        }
        return ENXChartView(title: c.title, data: c.data, chart: LineChart(data: c.data, columns: c.columns, minBound: c.minBound, maxBound: c.maxBound))
    }

    var body: some View {
        ForEach(charts) { c in chartView(c) }
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
    let lineChart: any GAENChart
    let data: DataFrame
    @MainActor init(title: String, data: DataFrame, chart: any GAENChart) {
        self.title = title
        self.data = data
        lineChart = chart
        let exportTitle = title + ".csv"

        if let csv = AnalysisState.exportToFileDocument(name: exportTitle, dataframe: data) {
            csvDocument = csv
        } else {
            csvDocument = CSVFile(name: "none", Data())
            print("set empty csvDocument")
        }

        if let url = AnalysisState.exportToURL(name: exportTitle, dataframe: data) {
            csvItem = CSVItem(url: url,
                              title: title)
        } else {
            csvItem = CSVItem(url: nil, title: "tmp.csv")
        }
        //logger.log("initialized \(title, privacy: .public)")
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
                        print("csv document \(csvDocument.name) has \(csvDocument.data.count) bytes")

                        shareURL = AnalysisState.exportToURL(csvFile: csvDocument)
                        shareTitle = csvDocument.name
                        showingShare = true
                    #endif
                }) {
                    Image(systemName: "square.and.arrow.up")
                }.animation(.easeInOut, value: showingShare)
            }.padding(.top).font(.headline) // HStack
        ) {
            if showingPopover {
                Text(markdown(file: title)).transition(.scale).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            // TestView()

            AnyView(lineChart.frame(height: 300))

        }.textCase(nil)
            .sheet(isPresented: self.$showingShare, onDismiss: { print("share sheet dismissed") },
                   content: {
                       ActivityView(activityItems: [
                           CSVItem(url: shareURL,
                                   title: shareTitle),
                       ] as [Any], applicationActivities: nil, isPresented: self.$showingShare)
                   })
    }
}

struct DurationSummaryView: View {
    @EnvironmentObject var analysisState: AnalysisState
    let title: String
    let df: DataFrame
    let summary: String
    @MainActor init(title: String, df: DataFrame, summary: String) {
        self.title = title
        self.df = df
        self.summary = summary
        let exportTitle = title + ".csv"

        if let csv = AnalysisState.exportToFileDocument(name: exportTitle, dataframe: df) {
            csvDocument = csv
        } else {
            csvDocument = CSVFile(name: "none", Data())
            print("set empty csvDocument")
        }

        if let url = AnalysisState.exportToURL(name: exportTitle, dataframe: df) {
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
                        print("csv document \(csvDocument.name) has \(csvDocument.data.count) bytes")

                        shareURL = AnalysisState.exportToURL(csvFile: csvDocument)
                        shareTitle = csvDocument.name
                        showingShare = true
                    #endif
                }) {
                    Image(systemName: "square.and.arrow.up")
                }.animation(.easeInOut, value: showingShare)
            }.padding(.top).font(.headline) // HStack
        ) {
            if showingPopover {
                Text(markdown(file: title)).transition(.scale).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            // TestView()
            Text(summary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
//                .contextMenu {
//                Button(action: {
//                UIPasteboard.general.string = summary
//                }) {
//                Text("Copy")
//                }
//                }

            // lineChart.frame(height: 300)

        }.textCase(nil)
            .sheet(isPresented: self.$showingShare, onDismiss: { print("share sheet dismissed") },
                   content: {
                       ActivityView(activityItems: [
                           CSVItem(url: shareURL,
                                   title: shareTitle),
                       ] as [Any], applicationActivities: nil, isPresented: self.$showingShare)
                   })
    }
}
