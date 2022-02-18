//
//  SetupView.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import SwiftUI

let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df
}()

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

struct SetupView: View {
    @ObservedObject var state = SetupState.shared
    @State var showingReset: Bool = false
    @State var showingTestData: Bool = false
    func describe(key: String) -> String {
        if key.isEmpty {
            return " <empty>"
        }
        return ", length \(key.count), \(key.prefix(8))…"
    }

    func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section(header: Text("What to analyze")) {
                HStack {
                    Text("Region")
                    TextField("e.g, US-HT", text: Binding(get: { self.state.region },
                                                          set: {
                                                              self.state.region = trim($0)
                                                          }))
                }

                HStack {
                    Text("# of notifications")
                    Spacer()
                    Picker("", selection: $state.notifications) {
                        ForEach(1 ... 4, id: \.self) {
                            Text("\($0)")
                        }
                    }
                }
                DatePicker(
                    "Start Date",
                    selection: $state.startDate,
                    displayedComponents: [.date]
                )
//                DatePicker(
//                    "Config Start Date",
//                    selection: $state.configStartDate,
//                    displayedComponents: [.date]
//                )
            } // Sectikon
            Section(header: Text("API keys")) {
                HStack {
                    NavigationLink(destination:
                        ApiKeyView(title: "ENCV API key", apiKey:
                            Binding(get: { self.state.encvKey },
                                    set: {
                                        self.state.encvKey = trim($0)
                                    }))) {
                        Text("ENCV\(describe(key: state.encvKey))")
                    }

                }.padding(.vertical)
                HStack {
                    NavigationLink(destination:
                        ApiKeyView(title: "ENPA API key", apiKey: Binding(get: { self.state.enpaKey },
                                                                          set: {
                                                                              self.state.enpaKey = trim($0)
                                                                          })))
                    { Text("ENPA\(describe(key: state.enpaKey))") }

                }.padding(.vertical)
                Toggle("Use test servers", isOn: self.$state.useTestServers)
            } // Section

            Section {
                #if !targetEnvironment(macCatalyst)
                    Toggle("Protect with FaceID", isOn: self.$state.useFaceID)
                #endif

                if self.state.setupNeeded {
                    Button(action: {
                        self.state.useTestData()
                    }) {
                        Text("Use test data")
                    }
                } else {
                    Button(action: { showingReset = true }) {
                        Text("Clear all")
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
