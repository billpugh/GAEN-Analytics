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
            }.font(.body)
        }
    }
}

struct RawExportView: View {
    @ObservedObject var analysisState = AnalysisState.shared
    @ObservedObject var state = SetupState.shared
  
    func exportRawENPA() {
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

            zipName = name
            showingZipSheet = true

        #endif
    }

    @State private var showingZipSheet: Bool = false
    @State private var zipDocument: ZipFile?
    @State private var zipName: String = ""

    var body: some View {
        List {
            Section(header: Text("Additional interaction metrics").font(.headline).textCase(nil)) {
                CheckView(id: "riskParameters")
                CheckView(id: "beaconCount")
            }
            Section(header: Text("Additional low noise 14 day metrics").font(.headline).textCase(nil)) {
                CheckView(id: "codeVerifiedWithReportType14d")
                CheckView(id: "keysUploadedWithReportType14d")
                CheckView(id: "periodicExposureNotification14d")
                CheckView(id: "secondaryAttack14d")
                CheckView(id: "dateExposure14d")
            }

            Section(header: Text("Actions").font(.headline).textCase(nil)) {
                #if !targetEnvironment(macCatalyst)
                    Button(action: { Task(priority: .userInitiated) {
                        await AnalysisTask().analyze(config: state.config, result: analysisState)
                    }
                    }) { Text(state.setupNeeded ? "setup needed" : analysisState.nextAction).font(.headline) }.padding().disabled(state.setupNeeded || analysisState.inProgress)

                    AnalysisProgressView().padding(.horizontal)
                #endif
                Button(action: { Task(priority: .userInitiated) { exportRawENPA() }}) {
                    Text("Export Raw ENPA data")
                }.padding().font(.headline).disabled(!analysisState.available || analysisState.rawENPA == nil)
            }
        }.font(.subheadline)
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
                                       title: self.zipName),
                           ] as [Any], applicationActivities: nil, isPresented: self.$showingZipSheet)
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
