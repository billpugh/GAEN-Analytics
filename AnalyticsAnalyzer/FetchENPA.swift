//
//  FetchENPA.swift
//  AnalyticsAnalyzer
//
//  Created by Bill Pugh on 1/30/22.
//

import Foundation

let urlSession = URLSession(configuration: .ephemeral)

public func getStat(metric: String, configuration: Configuration) -> NSDictionary {
    let sDate: String
    if let startDate = configuration.prefetchStart {
        sDate = dayFormatter.string(from: startDate)
    } else {
        sDate = "2021-01-01"
    }
    let host = configuration.useTestServers ? "api.dev.enpa-pha.io" : "api.enpa-pha.io"
    let s = "https://\(host)/api/public/v2/enpa-data?datasets=\(metric)&raw=True&start_date=\(sDate)&country=US&state=\(configuration.region!)"
    let url = URL(string: s)!
    // print(url)
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue("application/json", forHTTPHeaderField: "accept")
    // print("apiKey: \(configuration.enpaAPIKey)")
    request.setValue(configuration.enpaAPIKey, forHTTPHeaderField: "x-api-key")

    let data = getData(request)
    guard let data = data else {
        return [:]
    }

    let json = try! JSONSerialization.jsonObject(with: data, options: [])
    return json as! NSDictionary
}

func getData(_ request: URLRequest) -> Data? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Data?
    let task = urlSession.dataTask(with: request) { data, response, error in

        // Check if Error took place
        if let error = error {
            print("Error took place \(error)")
            semaphore.signal()
            return
        }

        // Read HTTP Response Status code
        if let response = response as? HTTPURLResponse {
            if response.statusCode != 200 {
                print("Response HTTP Status code: \(response.statusCode)")
            }
        }

        // Convert HTTP Response Data to a simple String
        if let data = data {
            // completion("Response data string:\n \(dataString)")
            result = data
        } // let data
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()
    return result
}
