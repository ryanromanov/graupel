//
//  AppearanceFollowingTests.swift
//  Tests
//
//  Graupel
//
//  Created by Ryan Romanosky on 2026-11-26.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 Ryan Romanosky
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Combine
import Testing
import Defaults
@testable import Graupel

@MainActor @Suite(.serialized) struct AppearanceFollowingTests {
    
    @Test func publishesSystemAppearanceChanges() {
        
        let setting = UserDefaults.standard[.documentAppearance]
        let appearance = NSApp.appearance
        defer {
            UserDefaults.standard[.documentAppearance] = setting
            NSApp.appearance = appearance
        }
        UserDefaults.standard[.documentAppearance] = .default
        NSApp.appearance = NSAppearance(named: .aqua)
        
        var values: [Bool] = []
        let observer = ThemeManager.shared.usesDarkAppearancePublisher
            .sink { values.append($0) }
        defer { observer.cancel() }
        
        #expect(values == [false])
        
        NSApp.appearance = NSAppearance(named: .darkAqua)
        #expect(values == [false, true])
        
        // the setting overrides the system appearance
        UserDefaults.standard[.documentAppearance] = .light
        #expect(values == [false, true, false])
    }
}
