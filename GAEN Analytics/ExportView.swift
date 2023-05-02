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

class ZipItem: NSObject, UIActivityItemSource {
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
        "public.zip-archive"
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
    let action: () -> Void
    // @Binding var showingSheet: Bool
    @State private var showingPopover = false

    var showingPopoverOption = true

    @MainActor func exportDataframe() {
        // print("analysisState.region = \(analysisState.region)")
        let fileName = "\(analysisState.region)-\(fileTitle)-\(dateTimeStamp).csv"
        if let dataFrame = dataFrame {
            #if targetEnvironment(macCatalyst)
                if let csv = AnalysisState.exportToFileDocument(name: fileName, dataframe: dataFrame) {
                    csvDocument = csv
                    // print("showing sheet for \(csv)")
                    action()
                    // showingSheet = true
                }
            #else
                if let url = AnalysisState.exportToURL(name: fileName, dataframe: dataFrame) {
                    csvItem = CSVItem(url: url, title: fileName)
                    print("showing sheet for \(url)")
                    action()
                    // showingSheet = true
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
        VStack(alignment: .leading) {
            HStack {
                if showingPopoverOption {
                    if dataFrame != nil {
                        Button(action: { exportDataframe() }) {
                            Label(title, systemImage: "square.and.arrow.up")
                        }.buttonStyle(BorderlessButtonStyle())
                    } else {
                        Text("\(title) not available")
                    }
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
    }
}

var csvDocument: CSVFile?
var zipDocument: ZipFile?

var csvItem: CSVItem = .init(url: nil, title: "")
var zipItem: ZipItem = .init(url: nil, title: "")

struct ExportView: View {
    @State private var showingCVSSheet: Bool = false
    @State private var showingZipSheet: Bool = false
    @ObservedObject var analysisState = AnalysisState.shared

    func exportRawENPA() {
        guard let raw = analysisState.rawENPA, let url = raw.writeMetrics() else { return }
        let name = url.lastPathComponent
        #if targetEnvironment(macCatalyst)
            do {
                let data = try Data(contentsOf: url)
                print("creating ZipDocument")
                zipDocument = ZipFile(name: name, zip: data)
                showingZipSheet = true
            } catch {
                print("Error getting raw ENPA archive: \(error.localizedDescription)")
            }

        #else
            zipItem = ZipItem(url: url, title: name)

            showingZipSheet = true

        #endif
    }

    func exportArchiveENPA() {
        guard let raw = analysisState.rawENPA, let url = raw.archiveENPA() else { return }
        let name = url.lastPathComponent
        #if targetEnvironment(macCatalyst)
            do {
                let data = try Data(contentsOf: url)
                zipDocument = ZipFile(name: name, zip: data)
                showingZipSheet = true
            } catch {
                print("Error getting raw ENPA archive: \(error.localizedDescription)")
            }

        #else
            zipItem = ZipItem(url: url, title: name)

            showingZipSheet = true

        #endif
    }

    var body: some View {
        Form {
            Section(header: Text("Analysis").font(.title).padding(.top)) {
                Text("ENPA").font(.title).padding(.top)
                ExportItem(title: "Combined ENPA", fileTitle: "ENPA", dataFrame: analysisState.combinedENPA, action: {
                    showingCVSSheet = true
                })

                ExportItem(title: "iOS ENPA", fileTitle: "iOS", dataFrame: analysisState.iOSENPA, action: {
                    showingCVSSheet = true
                })
                ExportItem(title: "Android ENPA", fileTitle: "Android", dataFrame: analysisState.AndroidENPA, action: {
                    showingCVSSheet = true
                })

                Text("ENCV").font(.title).padding(.top)
                ExportItem(title: "ENCV composite data", fileTitle: "encv-composite", dataFrame: analysisState.encvComposite, action: {
                    showingCVSSheet = true
                })
                if let smsErrors = analysisState.smsErrors {
                    ExportItem(title: "SMS errors data", fileTitle: "encv-sms-errors", dataFrame: smsErrors, action: {
                        showingCVSSheet = true
                    })
                }
                ExportItem(title: "ENCV analysis", fileTitle: "encv-analysis", dataFrame: analysisState.rollingAvg, action: {
                    showingCVSSheet = true
                })

                // Text("System health")

                if analysisState.worksheet != nil {
                    Text("Worksheet").font(.title).padding(.top)
                    ExportItem(title: "combined analysis", fileTitle: "worksheet", dataFrame: analysisState.worksheet, action: {
                        showingCVSSheet = true
                    }).padding(.bottom)
                }
            }
            #if targetEnvironment(macCatalyst)
            .fileExporter(isPresented: $showingCVSSheet, document: csvDocument, contentType:
                UTType.commaSeparatedText, defaultFilename: csvDocument?.name ?? "") { result in
                    switch result {
                    case let .success(url):
                        print("Saved to \(url)")
                    case let .failure(error):
                        print(error.localizedDescription)
                    }
                    csvDocument = nil
            }

            #else
                    .sheet(isPresented: self.$showingCVSSheet, onDismiss: { print("share sheet dismissed") },
                           content: {
                               ActivityView(activityItems: [
                                   csvItem,
                               ] as [Any], applicationActivities: nil, isPresented: self.$showingCVSSheet)
                           })
            #endif

            Section(header:
                Text("Raw ENPA data").font(.title).textCase(.none).padding(.top)) {
                    Button(action: { Task(priority: .userInitiated) { exportRawENPA() }}) {
                        Label("Raw ENPA csv data", systemImage: "square.and.arrow.up")
                    }.padding(.top).font(.headline).disabled(!analysisState.available || analysisState.rawENPA == nil)
                    Text(markdown(file: "Export raw ENPA csv data"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled).transition(.scale).font(.body).padding(.horizontal)

                    Button(action: { Task(priority: .userInitiated) { exportArchiveENPA() }}) {
                        Label("Raw ENPA json archive", systemImage: "square.and.arrow.up")
                    }.padding(.top).font(.headline).disabled(!analysisState.available || analysisState.rawENPA == nil)

                    Text(markdown(file: "Export raw ENPA json archive"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled).transition(.scale).font(.body).padding(.horizontal)
                }
            #if targetEnvironment(macCatalyst)
                .fileExporter(isPresented: $showingZipSheet, document: zipDocument, contentType: UTType.zip,
                              defaultFilename: zipDocument?.name ?? "archive.zip") { result in
                    print(zipDocument!.contentType)
                    switch result {
                    case let .success(url):
                        print("Saved to \(url)")
                    case let .failure(error):
                        print(error.localizedDescription)
                    }
                    csvDocument = nil
                }

            #else
                    .sheet(isPresented: self.$showingZipSheet, onDismiss: { print("share sheet dismissed") },
                           content: {
                               ActivityView(activityItems: [
                                   zipItem,
                               ] as [Any], applicationActivities: nil, isPresented: self.$showingZipSheet)
                           })
            #endif
        } // Form

        .navigationBarTitle("Export analysis and data")
    }
}

struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExportView()
        }
    }
}
