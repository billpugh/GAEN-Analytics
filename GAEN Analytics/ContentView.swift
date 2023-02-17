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

struct WelcomeView: View {
    @ObservedObject var state = SetupState.shared

    var body: some View {
        VStack {
            Text("Welcome to GAEN Analytics!")
                .font(.largeTitle)

            Text("The actions available are listed in the left-hand menu; swipe from the left edge to show it.")
                .foregroundColor(.secondary)
            if state.setupNeeded {
                Text("You probably want to select Setup to provide the information needed to use GAENAnalytics")
                    .foregroundColor(.secondary)
            } else {
                Text("You probably want to select Fetch Analytics to fetch the data for \(state.region)")
                    .foregroundColor(.secondary)
            }
            DocView(title: "About GAEN Analyzer", file: "about").padding()
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

    @State private var showAlert = true // !SetupState.shared.alertDismissed
    var body: some View {
        NavigationView {
            if isUnlocked || !state.useFaceID {
                Form {
                    NavigationLink(destination: DocView(title: "About GAEN Analyzer", file: "about"), tag: "about", selection: $viewShown) {
                        Text("About GAEN Analyzer").padding()
                    }

                    NavigationLink(destination: SetupView(), tag: "setup", selection: $viewShown) {
                        HStack {
                            Text(state.setupNeeded ? "Setup needed" : "Setup for \(state.region)").font(.headline).padding()
                            if !state.setupNeeded {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    NavigationLink(destination: SummaryView(viewShown: $viewShown), tag: "summary", selection: $viewShown) {
                        Text(analysisState.available ? "View/update analysis" : "Fetch analytics"
                        ).font(.headline).padding()
                    }.disabled(state.setupNeeded)

                    NavigationLink(destination: ExportView(), tag: "export", selection: $viewShown) {
                        Text("Export analysis").font(.headline).padding()
                    }.disabled(!analysisState.available)
                    NavigationLink(destination: RawExportView(), tag: "raw_export", selection: $viewShown) {
                        Text(analysisState.available && analysisState.rawENPA != nil ? "Export raw ENPA" : "Configure raw ENPA export").font(.headline).padding()
                    }.disabled(state.setupNeeded)

                    if false {
                        HStack {
                            Button(action: { Task(priority: .userInitiated) {
                                self.viewShown = "summary"
                                await AnalysisTask().analyze(config: state.config, result: analysisState)
                            }
                            }) { Text(state.setupNeeded ? "waiting for setup" : analysisState.nextAction).font(.headline) }.padding().disabled(state.setupNeeded || analysisState.inProgress)
                        }
                        AnalysisProgressView().padding(.horizontal)
                    }
                    HStack {
                        Button(action: {
                            showFilePicker = true

                        }) { Text("Load older encv composite stats").font(.headline) }.padding().sheet(isPresented: self.$showFilePicker) {
                            DocumentPicker()
                        }
                    }

                    if false, state.debuggingFeatures, !state.setupNeeded {
                        HStack {
                            Button(action: { Task(priority: .userInitiated) {
                                #if targetEnvironment(macCatalyst)
                                    self.viewShown = "summary"
                                #endif
                                await AnalysisTask().analyze(config: state.config, result: analysisState, analyzeENPA: false)
                            }
                            }) { Text(state.setupNeeded ? "setup needed" : "Fetch/Analyze just ENCV").font(.headline) }.padding().disabled(state.setupNeeded || analysisState.inProgress)
                        }
                        HStack {
                            Button(action: { Task(priority: .userInitiated) {
                                #if targetEnvironment(macCatalyst)
                                    self.viewShown = "summary"
                                #endif
                                await AnalysisTask().analyze(config: state.config, result: analysisState, analyzeENCV: false)
                            }
                            }) { Text(state.setupNeeded ? "setup needed" : "Fetch/Analyze just ENPA").font(.headline) }.padding().disabled(state.setupNeeded || analysisState.inProgress)
                        }
                    }

                }.navigationBarTitle("GAEN Analytics").font(.headline)

                    .fileExporter(isPresented: $analysisState.csvExportReady, document: analysisState.csvExport, contentType: .commaSeparatedText, defaultFilename: analysisState.csvExport?.name) { result in
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
            WelcomeView()
        }
        // NavigationView
        .listStyle(SidebarListStyle())
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Calculation of number of active devices changed"),
                message: Text("With newly available data on the total number of ENPA users in the United States, we have now been able to estimate the overall ENPA opt-in rate for the US. This avoids an issue with the previous calculation of opt-in rate, which was based on users who verified codes, which it not necessarily representative of the entire ENX population. Both the new calculation and the old calculation are shown in graphs for number of active users and total number of notifications"),
                dismissButton: .default(Text("Dismiss"),
                                        action: { // state.alertDismissed = true
                                        })
            )
        }
    } // View
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 13 Pro")
    }
}
