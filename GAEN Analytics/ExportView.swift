//
//  ExportView.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import LinkPresentation
import SwiftUI
import TabularData
import UniformTypeIdentifiers

extension CSVFile: FileDocument {
    init(configuration: ReadConfiguration) throws {
        name = "unknown.csv"
        data = configuration.file.regularFileContents!
    }

    static var readableContentTypes = [UTType.commaSeparatedText]
    var contentType: UTType {
        UTType.commaSeparatedText
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension ZipFile: FileDocument {
    init(configuration: ReadConfiguration) throws {
        name = "unknown.zip"
        data = configuration.file.regularFileContents!
    }

    // tell the system we support only plain text
    static var readableContentTypes = [UTType.zip]
    var contentType: UTType {
        UTType.zip
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// _allowedItemPayloadClasses
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    @Binding var isPresented: Bool

    func makeUIViewController(context _: UIViewControllerRepresentableContext<ActivityView>) -> UIActivityViewController {
        let result = UIActivityViewController(activityItems: activityItems,
                                              applicationActivities: applicationActivities)
        result.excludedActivityTypes = [UIActivity.ActivityType.addToReadingList,
                                        UIActivity.ActivityType.assignToContact,

                                        UIActivity.ActivityType.markupAsPDF,
                                        UIActivity.ActivityType.openInIBooks,
                                        UIActivity.ActivityType.postToFacebook,
                                        UIActivity.ActivityType.postToFlickr,
                                        UIActivity.ActivityType.postToTencentWeibo,
                                        UIActivity.ActivityType.postToTwitter,
                                        UIActivity.ActivityType.postToVimeo,
                                        UIActivity.ActivityType.postToWeibo,
                                        UIActivity.ActivityType.print,
                                        UIActivity.ActivityType.saveToCameraRoll,
                                        UIActivity.ActivityType(rawValue: "com.apple.reminders.sharingextension"),
                                        UIActivity.ActivityType(rawValue: "com.apple.mobilenotes.SharingExtension")]
        result.completionWithItemsHandler = { (activityType: UIActivity.ActivityType?, completed:
            Bool, _: [Any]?, error: Error?) in
            print("activity: \(String(describing: activityType))")

            if completed {
                print("share completed")
                self.isPresented = false
                return
            } else {
                print("cancel")
            }
            if let shareError = error {
                print("error while sharing: \(shareError.localizedDescription)")
            }
        }
        return result
    }

    func updateUIViewController(_: UIActivityViewController,
                                context _: UIViewControllerRepresentableContext<ActivityView>) {}
}

class CSVItem: NSObject, UIActivityItemSource {
    let url: URL?
    let title: String
    init(url: URL?, title: String) {
        self.url = url
        self.title = title
    }

    func itemsToShare() -> [Any] {
        [title, self]
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
        title
    }

    func activityViewController(_: UIActivityViewController, itemForActivityType _: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_: UIActivityViewController,
                                dataTypeIdentifierForActivityType _: UIActivity.ActivityType?) -> String
    {
        "public.comma-separated-values-text"
    }

    func activityViewController(_: UIActivityViewController,
                                subjectForActivityType _: UIActivity.ActivityType?) -> String
    {
        title
    }

    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        // let iconURL = Bundle.main.url(forResource: "keys_64", withExtension: "png")
        // metadata.iconProvider = NSItemProvider(contentsOf: iconURL)

        metadata.title = title
        return metadata
    }
}

struct ExportItem0: View {
    var title: String
    var fileTitle: String
    var dataFrame: DataFrame?
    let analysisState = AnalysisState.shared

    @Binding var showingSheet: Bool
    var body: some View {
        Text("placeholder \(title)")
    }
}

struct ExportItem: View {
    var title: String
    var fileTitle: String
    var dataFrame: DataFrame?
    let analysisState = AnalysisState.shared

    @Binding var showingSheet: Bool
    @State private var showingPopover = false

    var showingPopoverOption = true

    @MainActor func exportDataframe() {
        let fileName = "\(analysisState.region)-\(fileTitle)-\(dateTimeStamp).csv"
        if let dataFrame = dataFrame {
            #if targetEnvironment(macCatalyst)
                if let csv = AnalysisState.exportToFileDocument(name: fileName, dataframe: dataFrame) {
                    csvDocument = csv
                    //print("showing sheet for \(csv)")
                    showingSheet = true
                }
            #else
                if let url = AnalysisState.exportToURL(name: fileName, dataframe: dataFrame) {
                    shareURL = url

                    shareTitle = fileName
                    //print("showing sheet for \(url)")
                    showingSheet = true
                }
            #endif
        }
    }

    var dateTimeStamp: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmm"
        return dateFormatter.string(from: Date())
    }

    var body: some View {
        if dataFrame != nil {
            VStack(alignment: .leading) {
                HStack {
                    if showingPopoverOption {
                        Button(action: { exportDataframe() }) {
                            Label(title, systemImage: "square.and.arrow.up")
                        }.buttonStyle(BorderlessButtonStyle())

                        Spacer()
                        Button(action: { showingPopover.toggle() }) {
                            Image(systemName: "info.circle")

                        }.buttonStyle(BorderlessButtonStyle())
                    } else {
                        Text(title)
                    }
                }.font(.headline)

                if showingPopover {
                    Text(markdown(file: title)).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled).transition(.scale(scale: 0.0, anchor: UnitPoint(x: 0, y: 0))).font(.body).padding(.horizontal)
                }
            }
        } else {
            Text("error: data frame not available")
        }
    }
}

var shareURL: URL?
var shareTitle: String = ""
private var csvDocument: CSVFile?
struct ExportView: View {
    @State private var showingSheet: Bool = false
    let analysisState = AnalysisState.shared
    let showSections = true

    var body: some View {
        Form {
            if showSections {
                Section(header: Text("ENPA").font(.title).padding(.top)) {
                    ExportItem(title: "Combined ENPA", fileTitle: "ENPA", dataFrame: analysisState.combinedENPA, showingSheet: $showingSheet)

                    ExportItem(title: "iOS ENPA", fileTitle: "iOS", dataFrame: analysisState.iOSENPA, showingSheet: $showingSheet)
                    ExportItem(title: "Android ENPA", fileTitle: "Android", dataFrame: analysisState.AndroidENPA, showingSheet: $showingSheet)
                } // Section
            }
            if showSections {
                Section(header: Text("ENCV").font(.title).padding(.top)) {
                    ExportItem(title: "ENCV composite data", fileTitle: "encv-composite", dataFrame: analysisState.encvComposite, showingSheet: $showingSheet)
                    if let smsErrors = analysisState.smsErrors {
                        ExportItem(title: "SMS errors data", fileTitle: "encv-sms-errors", dataFrame: smsErrors, showingSheet: $showingSheet)
                    }
                    ExportItem(title: "ENCV analysis", fileTitle: "encv-analysis", dataFrame: analysisState.rollingAvg, showingSheet: $showingSheet)

                    // Text("System health")
                } // Section
                if analysisState.worksheet != nil {
                    Section(header: Text("Worksheet").font(.title).textCase(.none).padding(.top)) {
                        ExportItem(title: "combined analysis", fileTitle: "worksheet", dataFrame: analysisState.worksheet, showingSheet: $showingSheet)
                    }
                }
            } else {
                ExportItem(title: "Combined ENPA", fileTitle: "ENPA", dataFrame: analysisState.combinedENPA, showingSheet: $showingSheet)
            }
        } // Form

        #if targetEnvironment(macCatalyst)
        .fileExporter(isPresented: $showingSheet, document: csvDocument, contentType: UTType.commaSeparatedText, defaultFilename: csvDocument?.name ?? "") { result in
            switch result {
            case let .success(url):
                print("Saved to \(url)")
            case let .failure(error):
                print(error.localizedDescription)
            }
            csvDocument = nil
        }

        #else
                .sheet(isPresented: self.$showingSheet, onDismiss: { print("share sheet dismissed") },
                       content: {
                           ActivityView(activityItems: [
                               CSVItem(url: shareURL,
                                       title: shareTitle),
                           ] as [Any], applicationActivities: nil, isPresented: self.$showingSheet)
                       })
        #endif
                       .navigationBarTitle("Export analysis")
    }
}

struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExportView()
        }
    }
}
