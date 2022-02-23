//
//  RawExportView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/23/22.
//

import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

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

struct CheckView: View, Identifiable {
    let analysisState = AnalysisState.shared
    var id: String
    @State var selected: Bool
    @MainActor init(id: String) {
        self.id = id
        selected = analysisState.metricSelected(id)
    }

    var body: some View {
        Button(action: { selected.toggle()
            analysisState.toggleMetric(id)

        }) {
            HStack {
                Image(systemName: selected ? "checkmark.square" : "square")
                Text(id)
            }

        }.padding()
    }
}

struct RawExportView: View {
    let analysisState = AnalysisState.shared
    let additionalMetrics = ["riskParameters",
                             "beaconCount",
                             "dateExposure14d",
                             "keysUploadedWithReportType14d",
                             "periodicExposureNotification14d",
                             "secondaryAttack14d"]
    @MainActor func exportRawENPA() {
        guard let raw = analysisState.rawENPA, let url = raw.writeMetrics() else { return }
        let name = url.lastPathComponent
        #if targetEnvironment(macCatalyst)
            do {
                let data = try Data(contentsOf: url)
                zipDocument = ZipFile(name: name, data)
                showingZipSheet = true
            } catch {
                print("Error getting raw ENPA archive: \(error.localizedDescription)")
            }

        #else
            shareURL = url

            shareTitle = name
            showingSheet = true

        #endif
    }

    @State private var showingZipSheet: Bool = false
    @State private var zipDocument: ZipFile?

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(additionalMetrics, id: \.self) {
                CheckView(id: $0)
            } // ForEach

            Button(action: { exportRawENPA() }) {
                Text("Raw ENPA data")
            }.padding().disabled(!analysisState.available)
        }.font(.headline)
        #if targetEnvironment(macCatalyst)
            .fileExporter(isPresented: $showingZipSheet, document: zipDocument, contentType: UTType.zip, defaultFilename: zipDocument?.name ?? "") { result in
                switch result {
                case let .success(url):
                    print("Saved to \(url)")
                case let .failure(error):
                    print(error.localizedDescription)
                }
                zipDocument = nil
            }
        #else
                .sheet(isPresented: self.$showingZipSheet, onDismiss: { print("share sheet dismissed") },
                       content: {
                           ActivityView(activityItems: [
                               ZipItem(url: shareURL,
                                       title: self.shareTitle),
                           ] as [Any], applicationActivities: nil, isPresented: self.$showingSheet)
                       })
        #endif

        .navigationBarTitle("Export raw ENPA data")
    }
}

struct RawExportView_Previews: PreviewProvider {
    static var previews: some View {
        RawExportView()
    }
}
