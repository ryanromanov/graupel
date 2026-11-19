//
//  ChromeStyleTests.swift
//
//  Graupel
//  https://github.com/ryanromanov/graupel
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Testing
@testable import Graupel

@MainActor struct ChromeStyleTests {
    
    @Test func followsTheTheme() throws {
        
        let light = ChromeStyle(theme: try ThemeManager.shared.setting(name: "Graupel"))
        let dark = ChromeStyle(theme: try ThemeManager.shared.setting(name: "Graupel (Dark)"))
        
        #expect(!light.isDark)
        #expect(dark.isDark)
        #expect(light != dark)
        
        // the chrome is drawn in the theme's own colors
        let background = try #require(light.background.usingColorSpace(.sRGB))
        #expect(abs(background.redComponent - 0xfb / 255.0) < 0.01)
        #expect(abs(background.blueComponent - 0xfd / 255.0) < 0.01)
        #expect(light.accent == (try ThemeManager.shared.setting(name: "Graupel")).keywords.color)
    }
    
    
    @Test func separatesTheAreas() throws {
        
        for name in ["Graupel", "Graupel (Dark)", "Rain", "Rain (Dark)"] {
            let style = ChromeStyle(theme: try ThemeManager.shared.setting(name: name))
            
            // each area differs from the background so that lines and panels stay visible
            #expect(style.sidebar != style.background, "\(name)")
            #expect(style.border != style.background, "\(name)")
            #expect(style.secondaryText != style.background, "\(name)")
        }
    }
    
    
    @Test func windowStyleDefaultsToSystem() {
        
        #expect(DefaultSettings.defaults[.windowStyle] as? Int == WindowStyle.system.rawValue)
    }
}
