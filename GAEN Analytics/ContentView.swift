//
//  ContentView.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import LocalAuthentication
import SwiftUI

// struct ActivityIndicator: UIViewRepresentable {
//
//    typealias UIView = UIActivityIndicatorView
//    var isAnimating: Bool
//    fileprivate var configuration = { (indicator: UIView) in }
//
//    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIView { UIView() }
//    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<Self>) {
//        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
//        configuration(uiView)
//    }
// }

struct ContentView: View {
    @ObservedObject var state = SetupState.shared

    @ObservedObject var analysisState = AnalysisState.shared
    @State var viewShown: String? = nil
    @State var isUnlocked = false

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
                        Text("Region: \(state.region)").font(.headline).padding(.horizontal)
                        NavigationLink(destination: DocView(title: "About GAEN Analyzer", file: "about"), tag: "about", selection: $viewShown) {
                            Text("About GAEN Analyzer").padding(.horizontal)
                        }
                    }
                    Section(header: Text("Actions").font(.title).textCase(nil)) {
                        NavigationLink(destination: SetupView(), tag: "setup", selection: $viewShown) {
                            HStack {
                                Text("Setup").font(.headline).padding(.horizontal)
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

                        HStack {
                            Button(action: { Task(priority: .userInitiated) {
                                #if targetEnvironment(macCatalyst)
                                    self.viewShown = "summary"
                                #endif
                                await AnalysisTask().analyze(config: state.config, result: analysisState)
                            }
                            }) { Text(state.setupNeeded ? "setup needed" : analysisState.status).font(.headline) }.padding(.horizontal).disabled(state.setupNeeded || analysisState.inProgress)
                        }
                    }
                    #if !targetEnvironment(macCatalyst)
                        Section(header: Text("ENCV").font(.title)) {
                            Text(analysisState.encvSummary)
                        }
                        ENXChartsView(charts: analysisState.encvCharts)
                            .environmentObject(analysisState)

                        Section(header: Text("ENPA").font(.title)) {
                            Text(analysisState.enpaSummary)
                        }
                        ENXChartsView(charts: analysisState.enpaCharts)
                            .environmentObject(analysisState)

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
