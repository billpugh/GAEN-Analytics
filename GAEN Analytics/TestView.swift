//
//  TestView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/15/22.
//

import SwiftUI

struct TestView: View {
    @State var csv = CSVFile(name: "test", csv: "a,b,c\n1,2,3".data(using: .utf8)!)
    @State private var showingSheet: Bool = false
    var body: some View {
        VStack {
            Text("Export test")
            Toggle("Export test", isOn: $showingSheet)
                .fileExporter(isPresented: $showingSheet, document: csv, contentType: .commaSeparatedText, defaultFilename: csv.name) { result in
                    switch result {
                    case let .success(url):
                        print("Saved to \(url)")
                    case let .failure(error):
                        print(error.localizedDescription)
                    }
                }
        }
    }
}

struct TestView_Previews: PreviewProvider {
    static var previews: some View {
        TestView()
    }
}
