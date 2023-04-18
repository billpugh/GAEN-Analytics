//
//  TopicView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 2/25/22.
//

import SwiftUI

struct TopicView: View {
    var topic: String
    @State private var showingPopover = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(topic)
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut) {
                        showingPopover.toggle()
                    }
                }) {
                    Image(systemName: "info.circle").padding(.horizontal)
                }
            }.font(.title)
            if showingPopover {
                Text(markdown(file: topic))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).transition(.scale).font(.body)
            }
        }.textCase(nil)
    }
}

struct TopicActionView: View {
    var topic: String
    var action: () -> Void

    @State private var showingPopover = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(topic).font(.headline)
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut) {
                        showingPopover.toggle()
                    }
                }) {
                    Image(systemName: "info.circle").padding(.horizontal)
                }
            }.font(.title)
            if showingPopover {
                Text(markdown(file: topic))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).transition(.scale).font(.body)
            }
        }.textCase(nil)
    }
}

struct TopicView_Previews: PreviewProvider {
    static var previews: some View {
        TopicView(topic: "Test")
    }
}
