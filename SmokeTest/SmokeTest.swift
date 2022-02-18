//
//  SmokeTest.swift
//  SmokeTest
//
//  Created by Bill Pugh on 2/18/22.
//

import XCTest

class SmokeTest: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() async throws {
        let setupState = SetupState(testConfigWithNotifications: 1)
        let config = setupState.config
        let analysis = AnalysisState()
        let actor = AnalysisTask()
        await actor.analyze(config: config, result: analysis)
    }
}
