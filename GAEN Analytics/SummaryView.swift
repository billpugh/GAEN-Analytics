//
//  SummaryView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/9/22.
//

import os.log
import SwiftUI

import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.ninjamonkeycoders.GAENAnalytics", category: "SummaryView")

struct ENPAPicker: UIViewControllerRepresentable {
    func makeCoordinator() -> ENPAPicker.Coordinator {
        ENPAPicker.Coordinator()
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ENPAPicker>) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.zip], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: ENPAPicker.UIViewControllerType, context _: UIViewControllerRepresentableContext<ENPAPicker>) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let config = SetupState.shared.config
            
            Task(priority: .userInitiated) {
                let task = AnalysisTask()
             
                
                
                if let rawENPA = await task.loadENPAArchive(config: config, urls[0], result: AnalysisState.shared)
                {
                    AnalysisState.shared.rawENPA = rawENPA
                    await task.analyze(config: config, result: AnalysisState.shared, archivalData: true)
                }
                
                
            }
 
        }
    }
}

struct SummaryView: View {
    @ObservedObject var state = SetupState.shared
    @Environment(\.presentationMode) var presentationMode
    @Binding var viewShown: String?
    @ObservedObject var analysisState = AnalysisState.shared
    @State var showENPAArchivePicker = false
    var body: some View {
        List {
            Section(header: Text("GAEN Analytics for\u{00a0}\(analysisState.region)"
            ).font(.title)) {
                AnalysisProgressView()
                if analysisState.available, !state.useArchivalData {
                    Button(action: { Task(priority: .userInitiated) {
                        analysisState.start(config: state.config)
                        await AnalysisTask().analyze(config: state.config,
                                                     result: analysisState,
                                                     archivalData: state.useArchivalData
                                                    )
                    }
                    }) { Text("Update analytics").font(.headline).padding()
                    }
                }
                if !analysisState.available, !analysisState.inProgress, state.useArchivalData {
                    
                        Button(action: {
                            showENPAArchivePicker = true
                            
                        }) { Text("Load ENPA archive").font(.headline) }.sheet(isPresented: self.$showENPAArchivePicker) {
                            ENPAPicker()
                        }.padding()
                    
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
            if let da = analysisState.durationAnalysis,
               let summary = analysisState.durationSummary
            {
                DurationSummaryView(title: "Duration summary", df: da, summary: summary)
            }
         
                Section(header: TopicView(topic: "Appendix").padding(.top)) {}
            VStack {
                ENXChartsView(charts: analysisState.appendixCharts)
                ENXChartsView(charts: analysisState.appendixENPACharts)
            }
        }.listStyle(GroupedListStyle())
            .onAppear {
                if !state.setupNeeded, !analysisState.inProgress, !analysisState.available, !state.useArchivalData {
                    Task(priority: .userInitiated) {
                        analysisState.start(config: state.config)
                        await AnalysisTask().analyze(config: state.config, result: analysisState, archivalData: state.useArchivalData)
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
    @State static var viewShown: String?
    static var previews: some View {
        SummaryView(viewShown: $viewShown)
    }
}
