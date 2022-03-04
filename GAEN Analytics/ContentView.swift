//
//  ContentView.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    func makeCoordinator() -> DocumentPicker.Coordinator {
        DocumentPicker.Coordinator()
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.commaSeparatedText], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: DocumentPicker.UIViewControllerType, context _: UIViewControllerRepresentableContext<DocumentPicker>) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            AnalysisState.shared.loadComposite(urls[0])
        }
    }
}

struct ContentView: View {
    @ObservedObject var state = SetupState.shared

    @ObservedObject var analysisState = AnalysisState.shared
    @State var viewShown: String? = nil
    @State var showFilePicker = false
    @State var isUnlocked = false

    init() {
        analysisState.loadComposite()
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Please authenticate yourself to unlock your information."

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in

                if success {
                    self.isUnlocked = true
                } else {
                    // error
                }
            }
        } else {
            // no biometrics
        }
    }

    var body: some View {
        NavigationView {
            if isUnlocked || !state.useFaceID {
                List {
                    Section(header: Text("GAEN Analytics app").font(.title).textCase(nil)) {
                        if self.state.isUsingTestData {
                            Text("Using test data and servers").padding(.horizontal)
                        }
                        if !state.isClear {
                            Text("Region: \(state.region)").padding(.horizontal)
                        }
                        NavigationLink(destination: DocView(title: "About GAEN Analyzer", file: "about"), tag: "about", selection: $viewShown) {
                            Text("About GAEN Analyzer").padding(.horizontal)
                        }
                    }.font(.headline)
                    Section(header: Text("Actions").font(.title).textCase(nil)) {
                        NavigationLink(destination: SetupView(), tag: "setup", selection: $viewShown) {
                            HStack {
                                Text(state.setupNeeded ? "Setup needed" : "Setup").font(.headline).padding(.horizontal)
                                if !state.setupNeeded {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        #if targetEnvironment(macCatalyst)
                            NavigationLink(destination: SummaryView(), tag: "summary", selection: $viewShown) {
                                Text("View Analysis summary").font(.headline).padding(.horizontal)
                            }.disabled(!analysisState.available)
                        #endif

                        NavigationLink(destination: ExportView(), tag: "export", selection: $viewShown) {
                            Text("Export analysis").font(.headline).padding(.horizontal)
                        }.disabled(!analysisState.available)
                        NavigationLink(destination: RawExportView(), tag: "raw_export", selection: $viewShown) {
                            Text("Export Raw ENPA").font(.headline).padding(.horizontal)
                        }.disabled(state.setupNeeded)

                        HStack {
                            Button(action: { Task(priority: .userInitiated) {
                                #if targetEnvironment(macCatalyst)
                                    self.viewShown = "summary"
                                #endif
                                await AnalysisTask().analyze(config: state.config, result: analysisState)
                            }
                            }) { Text(state.setupNeeded ? "waiting for setup" : analysisState.nextAction).font(.headline) }.padding(.horizontal).disabled(state.setupNeeded || analysisState.inProgress)
                        }
                        AnalysisProgressView().padding(.horizontal)

                        HStack {
                            Button(action: {
                                showFilePicker = true

                            }) { Text("Load older composite stats").font(.headline) }.padding(.horizontal).sheet(isPresented: self.$showFilePicker) {
                                DocumentPicker()
                            }
                        }

                        if state.debuggingFeatures && !state.setupNeeded {
                            HStack {
                                Button(action: { Task(priority: .userInitiated) {
                                    #if targetEnvironment(macCatalyst)
                                        self.viewShown = "summary"
                                    #endif
                                    await AnalysisTask().analyze(config: state.config, result: analysisState, analyzeENPA: false)
                                }
                                }) { Text(state.setupNeeded ? "setup needed" : "Fetch/Analyze just ENCV").font(.headline) }.padding(.horizontal).disabled(state.setupNeeded || analysisState.inProgress)
                            }
                            HStack {
                                Button(action: { Task(priority: .userInitiated) {
                                    #if targetEnvironment(macCatalyst)
                                        self.viewShown = "summary"
                                    #endif
                                    await AnalysisTask().analyze(config: state.config, result: analysisState, analyzeENCV: false)
                                }
                                }) { Text(state.setupNeeded ? "setup needed" : "Fetch/Analyze just ENPA").font(.headline) }.padding(.horizontal).disabled(state.setupNeeded || analysisState.inProgress)
                            }
                        }
                    }
                    #if !targetEnvironment(macCatalyst)

                        if true {
                            Section(header: TopicView(topic: "ENCV")) {
                                Text(analysisState.encvSummary).textSelection(.enabled)
                            }
                            ENXChartsView(charts: analysisState.encvCharts)
                                .environmentObject(analysisState)

                            Section(header: TopicView(topic: "ENPA").font(.title)) {
                                Text(analysisState.enpaSummary).textSelection(.enabled)
                            }
                            ENXChartsView(charts: analysisState.enpaCharts)
                                .environmentObject(analysisState)
                        }

                    #endif
                }.fileExporter(isPresented: $analysisState.csvExportReady, document: analysisState.csvExport, contentType: .commaSeparatedText, defaultFilename: analysisState.csvExport?.name) { result in
                    switch result {
                    case let .success(url):
                        print("Saved to \(url)")
                    case let .failure(error):
                        print(error.localizedDescription)
                    }
                }
            } else {
                VStack {
                    Button("Unlock GAEN Analytics") {
                        authenticate()
                    }
                    .padding()
                    .background(.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
        } // .listStyle(SidebarListStyle())

        .navigationBarTitle("GAEN Analytics")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 13 Pro")
    }
}
