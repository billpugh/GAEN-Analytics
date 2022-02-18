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

struct CSVFile: FileDocument {
    init(configuration: ReadConfiguration) throws {
        name = "unknown.csv"
        data = configuration.file.regularFileContents!
    }

    // tell the system we support only plain text
    static var readableContentTypes = [UTType.commaSeparatedText]

    // by default our document is empty
    var data = Data()
    var name: String

    init(name: String, _ data: Data) {
        self.data = data
        self.name = name
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

var shareURL: URL?
struct ExportView: View {
    @State private var shareTitle: String = ""
    @State private var showingSheet: Bool = false
    let analysisState = AnalysisState.shared

    @State private var csvDocument = CSVFile(name: "none", Data())
    @State private var defaultFilename: String = ""

    @MainActor func exportDataframe(_ name: String, _ dataFrame: DataFrame?) {
        if let dataFrame = dataFrame {
            #if targetEnvironment(macCatalyst)
                if let csv = AnalysisState.exportToFileDocument(name: name, dataframe: dataFrame) {
                    csvDocument = csv
                    showingSheet = true
                }
            #else
                if let url = AnalysisState.exportToURL(name: name, dataframe: dataFrame) {
                    shareURL = url

                    shareTitle = name
                    showingSheet = true
                }
            #endif
        }
    }

    var body: some View {
        Form {
            Section(header: Text("ENPA")) {
                if analysisState.combinedENPA != nil {
                    Button(action: { exportDataframe("\(analysisState.region).csv", analysisState.combinedENPA) }) {
                        Text("combined Data")
                    }
                }

                if analysisState.iOSENPA != nil {
                    Button(action: { exportDataframe("\(analysisState.region)-ios.csv.csv", analysisState.iOSENPA) }) {
                        Text("iOS Data")
                    }
                }

                if analysisState.AndroidENPA != nil {
                    Button(action: { exportDataframe("\(analysisState.region)-android.csv", analysisState.AndroidENPA) }) {
                        Text("Android Data")
                    }
                }
            } // Section

            Section(header: Text("ENCV")) {
                if analysisState.encvComposite != nil {
                    Button(action: { exportDataframe("\(analysisState.region)-composite.csv", analysisState.encvComposite) }) {
                        Text("composite.csv")
                    }
                }
                if analysisState.rollingAvg != nil {
                    Button(action: { exportDataframe("\(analysisState.region)-encv.csv", analysisState.rollingAvg) }) {
                        Text("analyzed data (7 day rolling average)")
                    }
                }

                // Text("System health")
            } // Section
        } // Form

        #if targetEnvironment(macCatalyst)
            .fileExporter(isPresented: $showingSheet, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: csvDocument.name) { result in
                switch result {
                case let .success(url):
                    print("Saved to \(url)")
                case let .failure(error):
                    print(error.localizedDescription)
                }
            }
        #else
                .sheet(isPresented: self.$showingSheet, onDismiss: { print("share sheet dismissed") },
                       content: {
                           ActivityView(activityItems: [
                               CSVItem(url: shareURL,
                                       title: self.shareTitle),
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
