//
//  ENXChartView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/14/22.
//

import SwiftUI
import TabularData

// NT/KU
// NT
// # of users
// arriving promptly
// Seconary attack rate
// codes claimed/consent
// user report rate
// avg days onset to upload
// sms errors, publish rate, android rate

struct ChartOptions: Identifiable {
    let days = 60
    let title: String
    let data: DataFrame.Slice
    let columns: [String]
    let maxBound: Double?
    var id: String {
        title
    }

    static func maybe(title: String, data: DataFrame, columns: [String], maxBound: Double? = nil) -> ChartOptions? {
        for c in columns {
            if data.indexOfColumn(c) == nil {
                return nil
            }
        }
        return ChartOptions(title: title, data: data, columns: columns, maxBound: maxBound)
    }

    init(title: String, data: DataFrame, columns: [String], maxBound: Double? = nil) {
        self.title = title
        // print("\(data.columns.count) data Columns: \(data.columns.map(\.name))")
        let rows = max(7, data.rows.count - 6)
        self.data = data.suffix(rows).selecting(columnNames: ["date"] + columns)
        self.columns = columns
        self.maxBound = maxBound
    }
}

func notificationsPerUpload(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns: [String]
    if config.numCategories == 1 {
        columns = ["nt/ku"]

    } else {
        columns = ["nt/ku"] + (1 ... config.numCategories).map { "nt\($0)/ku" }
    }
    return ChartOptions(title: "Notifications per key upload", data: enpa,
                        columns: columns,
                        maxBound: 50)
}

func notificationsPer100K(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns: [String]
    if config.numCategories == 1 {
        columns = ["nt"]

    } else {
        columns = ["nt"] + (1 ... config.numCategories).map { "nt\($0)" }
    }
    return ChartOptions(title: "Notifications per 100K", data: enpa, columns: columns)
}

func arrivingPromptly(enpa: DataFrame, config: Configuration) -> ChartOptions {
    let columns = Array((1 ... config.numCategories).map { ["nt\($0) 0-3 days %", "nt\($0) 0-6 days %"] }.joined())

    return ChartOptions(title: "Notifications arriving promptly", data: enpa, columns: columns,
                        maxBound: 1.0)
}

// est. users
func estimatedUsers(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "Estimated users", data: enpa, columns: ["est users"])
}

// est. users
func enpaOptIn(enpa: DataFrame, config _: Configuration) -> ChartOptions? {
    ChartOptions.maybe(title: "ENPA opt in", data: enpa, columns: ["ENPA %"], maxBound: 1.0)
}

// codes claimed/consent
// user report rate
// avg days onset to upload
// sms errors, publish rate, android rate

func claimedConsent(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "claimed and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate,user report claim rate,user report consent rate".components(separatedBy: ","))
    }
    return ChartOptions(title: "claimed and consent rates", data: encv, columns: "confirmed test claim rate,confirmed test consent rate".components(separatedBy: ","))
}

func userReportRate(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions? {
    if !hasUserReports {
        return nil
    }
    return ChartOptions(title: "User report %", data: encv, columns: "user report percentage,user reports revision rate".components(separatedBy: ","))
}

func tokensClaimed(encv: DataFrame, hasUserReports: Bool, config _: Configuration) -> ChartOptions {
    if hasUserReports {
        return ChartOptions(title: "tokensClaimed", data: encv, columns: "tokens claimed,confirmed test tokens claimed,user report tokens claimed".components(separatedBy: ","))
    }
    return ChartOptions(title: "tokens claimed", data: encv, columns: "tokens claimed".components(separatedBy: ","))
}

func systemHealth(encv: DataFrame, hasSMS: Bool, config _: Configuration) -> ChartOptions {
    if hasSMS {
        return ChartOptions(title: "System health", data: encv, columns: "publish failure rate,sms error rate,android publish share".components(separatedBy: ","))
    }
    return ChartOptions(title: "System health", data: encv, columns: "publish failure rate,android publish share".components(separatedBy: ","))
}

func publishRequests(encv: DataFrame, config _: Configuration) -> ChartOptions {
    ChartOptions(title: "Publish requests", data: encv, columns: "publish requests,publish requests ios,publish requests android".components(separatedBy: ","))
}

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

class ImageSaver: NSObject {
    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveComplete), nil)
    }

    @objc func saveComplete(_: UIImage, didFinishSavingWithError error: Error?, contextInfo _: UnsafeRawPointer) {
        if let error = error {
            print("got \(error) while saving image")
        } else {
            print("image saved")
        }
    }
}

let imageSaver = ImageSaver()

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
