//
//  SetupView.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import SwiftUI
import UniformTypeIdentifiers

func makeAlert(
    title: String,
    message: String,
    destructiveButton: String,
    destructiveAction: @escaping () -> Void,
    cancelAction: @escaping () -> Void
) -> Alert {
    Alert(title: Text(title), message: Text(message),
          primaryButton: .destructive(Text(destructiveButton), action: destructiveAction),
          secondaryButton: .cancel(cancelAction))
}

struct CompositePicker: UIViewControllerRepresentable {
    func makeCoordinator() -> CompositePicker.Coordinator {
        CompositePicker.Coordinator()
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<CompositePicker>) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.commaSeparatedText], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: CompositePicker.UIViewControllerType, context _: UIViewControllerRepresentableContext<CompositePicker>) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            AnalysisState.shared.loadComposite(urls[0])
        }
    }
}

struct SetupView: View {
    @ObservedObject var state = SetupState.shared
    @State var showingReset: Bool = false
    @State var showingResetENCV: Bool = false
    @State var showingTestData: Bool = false
    @State var showCompositePicker = false

    func describe(key: String) -> String {
        if key.isEmpty {
            return " not provided"
        }
        return ", length \(key.count), \(key.prefix(8))…"
    }

    func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section(header: Text("Analysis parameters").font(.title)) {
                HStack {
                    Text("Region")
                    TextField("e.g, US-HT", text: Binding(get: { self.state.region },
                                                          set: {
                                                              self.state.region = trim($0.uppercased())
                                                          })).disabled(state.isUsingTestData)
                }

                HStack {
                    Text("# of notification classifications")
                    Spacer()
                    Picker("", selection: $state.notifications) {
                        ForEach(1 ... 4, id: \.self) {
                            Text("\($0)")
                        }
                    }
                }
                HStack {
                    Text("baseline exposure duration")
                    Spacer()
                    Picker("", selection: $state.durationBaselineMinutes) {
                        ForEach([7.5, 10, 15], id: \.self) {
                            Text(format(minutes: $0))
                        }
                    }
                }
                HStack {
                    Text("High infectiousness weight")
                    Spacer()
                    Picker("", selection: $state.highInfectiousnessWeight) {
                        ForEach([100, 200], id: \.self) {
                            Text("\($0)")
                        }
                    }
                }
                HStack {
                    Text("# of days for rolling averages")
                    Spacer()
                    Picker("", selection: $state.daysRollup) {
                        ForEach([1, 4, 7, 14, 28, 56], id: \.self) {
                            Text("\($0)")
                        }
                    }
                }
                DatePicker(
                    "Start Date",
                    selection: $state.startDate,
                    displayedComponents: [.date]
                )
                HStack {
                    DatePicker(
                        "End Date",
                        selection: $state.endDate,
                        displayedComponents: [.date]
                    )
                    Text(state.endNotNow ? "" : "(now)")
                }
                //                DatePicker(
                //                    "Config Start Date",
                //                    selection: $state.configStartDate,
                //                    displayedComponents: [.date]
                //                )
            } // Sectikon

            if !self.state.useArchivalData {
                Section(header: Text("API keys").font(.title)) {
                    HStack {
                        NavigationLink(destination:
                            ApiKeyView(title: "ENCV API key", apiKey:
                                Binding(get: { self.state.encvKey },
                                        set: {
                                            self.state.encvKey = trim($0)
                                        }))) {
                            Text("ENCV\(describe(key: state.encvKey))")
                        }.disabled(self.state.isUsingTestData)

                    }.padding(.vertical)
                    HStack {
                        NavigationLink(destination:
                            ApiKeyView(title: "ENPA API key", apiKey: Binding(get: { self.state.enpaKey },
                                                                              set: {
                                                                                  self.state.enpaKey = trim($0)
                                                                              })))
                        { Text("ENPA\(describe(key: state.enpaKey))") }.disabled(self.state.isUsingTestData)

                    }.padding(.vertical)
                } // Section
            } // if

            Section(header: Text("Archival data").font(.title)) {
                Toggle("Use only archival data, ignoring of API keys", isOn: self.$state.useArchivalData.animation()).padding()
                HStack {
                    Button(action: {
                        showCompositePicker = true

                    }) { Text("Load older encv composite stats").font(.headline) }.padding().sheet(isPresented: self.$showCompositePicker) {
                        CompositePicker()
                    }
                }
            }

            Section(header: Text("App features").font(.title)) {
                #if !targetEnvironment(macCatalyst)
                    Toggle("Protect with FaceID", isOn: self.$state.useFaceID).padding()
                #endif

                if !self.state.usingTestData {
                    Toggle(self.state.disableTestServer ? "Enable debugging features" : "Enable test/debugging features", isOn: self.$state.debuggingFeatures.animation())
                        .padding()
                }

                if !self.state.disableTestServer, self.state.isClear && self.state.debuggingFeatures || self.state.isUsingTestData {
                    Toggle("Use test data", isOn: self.$state.usingTestData.animation())

                } else if !self.state.isClear {
                    Button(action: {
                        withAnimation {
                            showingReset = true
                        }
                    }) {
                        Text("Clear all").font(.headline)
                    }.alert(isPresented: $showingReset) {
                        makeAlert(title: "Really clear ",
                                  message: "Are you sure you want to delete all keys and analysis?",
                                  destructiveButton: "Clear all",
                                  destructiveAction: {
                                      self.state.clear()
                                      self.showingReset = false

                                  },
                                  cancelAction: { self.showingReset = false })
                    }.padding()
                }

                Button(action: {
                    withAnimation {
                        showingResetENCV = true
                    }
                }) {
                    Text("Discard cached ENCV data").font(.headline)
                }.alert(isPresented: $showingResetENCV) {
                    makeAlert(title: "Discard ENCV data?",
                              message: "Are you sure you want to discard cached ENCV data? You should only do this if you are having problems with the app crashing when loading new ENCV data.",
                              destructiveButton: "Discard",
                              destructiveAction: {
                                  AnalysisState.shared.deleteComposite()

                                  self.showingResetENCV = false

                              },
                              cancelAction: { self.showingResetENCV = false })
                }.padding()
            } // Section
        }.padding().navigationBarTitle("Setup", displayMode: .inline)
    }
}

struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SetupView()
        }
    }
}
