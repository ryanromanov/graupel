//
//  IndentationSettingTests.swift
//  Tests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-11-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 CotEditor Project
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

import Testing
@testable import CotEditor

struct IndentationSettingTests {
    
    private let defaults = (expandsTab: false, width: 4)
    private let none = IndentationSetting()
    
    
    private func resolve(manual: IndentationSetting = .init(), detected: IndentationSetting? = nil,
                         editorConfig: IndentationSetting = .init(), syntaxMode: IndentationSetting? = nil,
                         syntaxDefault: IndentationSetting = .init(), kindMode: IndentationSetting? = nil) -> (Bool, Int)
    {
        let result = IndentationSetting.resolve(manual: manual, detected: detected, editorConfig: editorConfig,
                                                syntaxMode: syntaxMode, syntaxDefault: syntaxDefault, kindMode: kindMode,
                                                defaults: self.defaults)
        return (result.expandsTab, result.width)
    }
    
    
    @Test func defaultsWhenNothingIsSet() {
        
        #expect(self.resolve() == (false, 4))
    }
    
    
    @Test func eachLayerBeatsTheOnesAfterIt() {
        
        let spaces2 = IndentationSetting(expandsTab: true, width: 2)
        let tabs8 = IndentationSetting(expandsTab: false, width: 8)
        
        #expect(self.resolve(syntaxDefault: spaces2, kindMode: tabs8) == (true, 2))  // a new Boreas document
        #expect(self.resolve(syntaxMode: tabs8, syntaxDefault: spaces2) == (false, 8))  // the user's Boreas mode
        #expect(self.resolve(detected: tabs8, syntaxMode: spaces2) == (false, 8))
        #expect(self.resolve(detected: spaces2, editorConfig: tabs8) == (false, 8))  // .editorconfig beats the file
        #expect(self.resolve(manual: spaces2, editorConfig: tabs8) == (true, 2))
    }
    
    
    @Test func eachSettingIsResolvedSeparately() {
        
        // .editorconfig sets only the style, the syntax only the width
        #expect(self.resolve(editorConfig: .init(expandsTab: true), syntaxDefault: .init(width: 2)) == (true, 2))
        
        // .editorconfig sets only the style; the detected width still counts
        #expect(self.resolve(detected: .init(expandsTab: false, width: 3), editorConfig: .init(expandsTab: true)) == (true, 3))
        
        // a detected tab file keeps the width from below
        #expect(self.resolve(detected: .init(expandsTab: false), syntaxDefault: .init(expandsTab: true, width: 2)) == (false, 2))
        
        // a manual width alone keeps the detected style
        #expect(self.resolve(manual: .init(width: 3), detected: .init(expandsTab: true, width: 2)) == (true, 3))
    }
}
