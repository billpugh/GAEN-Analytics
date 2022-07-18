//
//  DocView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/15/22.
//

import SwiftUI

func markdown(file: String) -> AttributedString {
    let fileName = file.replacingOccurrences(of: "/", with: ":")
    // let about =  stringPath = Bundle.main.path(forResource: "input", ofType: "txt")
    do {
        guard let filepath = Bundle.main.path(forResource: fileName, ofType: "md") else {
            return markdown("unable to load text for \(file)")
        }
        // print(filepath)
        let txt = try String(contentsOf: URL(fileURLWithPath: filepath), encoding: .utf8)
        // print(txt)
        return markdown(txt)

    } catch {
        return markdown("unable to load text for \(file)")
    }
}

func markdown(_ s: String) -> AttributedString {
    do {
        return try AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    } catch {
        return AttributedString(s)
    }
}

struct DocView: View {
    var title: String
    var file: String
    var body: some View {
        ScrollView {
            VStack {
                if title == "About GAEN Analyzer" {
                    Text("Version \(SetupState.shared.appVersion), build \(SetupState.shared.build)")
                }

                Text(markdown(file: file))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }.padding().navigationBarTitle(title, displayMode: .inline)
        }
    }
}

struct DocView_Previews: PreviewProvider {
    static var previews: some View {
        DocView(title: "about", file: "about")
    }
}
