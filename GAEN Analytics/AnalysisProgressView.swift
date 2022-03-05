//
//  AnalysisProgressView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 3/4/22.
//

import SwiftUI

struct AnalysisProgressView: View {
    @ObservedObject var state = AnalysisState.shared
    var body: some View {
        if state.inProgress {
            ProgressView(value: state.progress, total: 1.0) {
                Text("\(state.status)")
            }
        } else if state.available {
            Text("Fetched at \(state.availableAtMessage)")
        }
    }
}

struct AnalysisProgressView_Previews: PreviewProvider {
    static var previews: some View {
        AnalysisProgressView()
    }
}
