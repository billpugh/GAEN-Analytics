//
//  ApiKeyView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/7/22.
//

import SwiftUI

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = value + nextValue()
    }
}

struct ApiKeyView: View {
    var title: String
    @Binding var apiKey: String
    @State var textEditorHeight: CGFloat = 20
    @State var showingClear = false
    var body: some View {
        VStack {
            Text(title)
            ZStack(alignment: .leading) {
                Text(apiKey)
                    .font(.system(.body))
                    .foregroundColor(.clear)
                    .padding(14)
                    .background(GeometryReader {
                        Color.clear.preference(key: ViewHeightKey.self,
                                               value: $0.frame(in: .local).size.height)
                    })

                TextEditor(text: $apiKey)
                    .font(.system(.body))
                    .frame(height: max(40, textEditorHeight))
                    .cornerRadius(10.0)
                    .shadow(radius: 1.0)
            }.onPreferenceChange(ViewHeightKey.self) { textEditorHeight = $0 }
            Text("\(apiKey.count) characters").foregroundColor(apiKey.count < 100 || apiKey.count > 250 ? .red : .black)
            if apiKey.count < 100 || apiKey.count > 250 {
                Text("api keys are typically between 100 and 250 characters, with no line breaks or spaces")
            }
            Button(action: { self.showingClear = true }) {
                Text("clear")
            }.alert(isPresented: $showingClear) {
                makeAlert(title: "Really erase?",
                          message: "Are you sure you want to erase the API key?",
                          destructiveButton: "Erase",
                          destructiveAction: {
                              apiKey = ""
                              self.showingClear = false
                          },
                          cancelAction: { self.showingClear = false })
            }.padding()
        }
    }
}

struct ApiKeyView_Previews: PreviewProvider {
    static var previews: some View {
        ApiKeyView(title: "ENCV key", apiKey: Binding(get: { SetupState.shared.encvKey },
                                                      set: {
                                                          SetupState.shared.encvKey = $0
                                                      }))
            .previewDevice("iPhone 13 Pro")
    }
}
