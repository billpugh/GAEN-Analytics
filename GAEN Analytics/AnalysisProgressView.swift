//
//  AnalysisProgressView.swift
//  GAEN Analytics
//
//  Created by Bill Pugh on 3/4/22.
//

import SwiftUI

struct AnalysisProgressView: View {
    @ObservedObject var state = AnalysisState.shared
    @ObservedObject var setup = SetupState.shared
    var body: some View {
        if state.inProgress {
            ProgressView(value: state.progress, total: 1.0) {
                Text("\(state.status)")
            }
        } else if state.available {
            VStack(alignment: .leading) {
                if setup.useArchivalData {
                    Text("ENPA loaded from archive")
                } else {
                    Text("Fetched at \(state.availableAtMessage)")
                }
                if let config = state.config {
                    Text(config.numDays == 1 ? "Data for individual days" : "Rolling \(config.numDays) day averages")
                }
            }
        }
    }
}

struct AnalysisProgressView_Previews: PreviewProvider {
    static var previews: some View {
        AnalysisProgressView()
    }
}
