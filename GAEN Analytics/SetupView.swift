//
//  SetupView.swift
//  AnalysisApp
//
//  Created by Bill Pugh on 1/30/22.
//

import SwiftUI

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

            Section {
                #if !targetEnvironment(macCatalyst)
                    Toggle("Protect with FaceID", isOn: self.$state.useFaceID)
                #endif
                if !self.state.usingTestData {
                    Toggle("Enable debugging features", isOn: self.$state.debuggingFeatures.animation())
                }
                if self.state.isClear && self.state.debuggingFeatures || self.state.isUsingTestData {
                    Toggle("Use test data", isOn: self.$state.usingTestData.animation())

                } else if !self.state.isClear {
                    Button(action: {
                        withAnimation {
                            showingReset = true
                        }
                    }) {
                        Text("Clear all")
                    }.alert(isPresented: $showingReset) {
                        makeAlert(title: "Really clear ",
                                  message: "Are you sure you want to delete all keys and analysis?",
                                  destructiveButton: "Clear all",
                                  destructiveAction: {
                                      self.state.clear()
                                      self.showingReset = false
                                      print("\(self.state.isClear)")
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
