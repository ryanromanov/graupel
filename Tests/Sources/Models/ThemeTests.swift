//
//  ThemeTests.swift
//  Tests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-03-15.
//
//  ---------------------------------------------------------------------------
//
//  © 2016-2026 1024jp
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
import UniformTypeIdentifiers
import Testing
import Numerics
import SyntaxFormat
@testable import Graupel

actor ThemeTests {
    
    private let themeDirectoryName = "Themes"
    
    
    @Test func defaultTheme() throws {
        
        let theme = try self.loadThemeWithName("Graupel")
        
        #expect(!theme.isDarkTheme)
        
        let aqua = try #require(NSAppearance(named: .aqua))
        aqua.performAsCurrentDrawingAppearance {
            #expect(theme.unemphasizedSelectionColor != nil)
        }
        
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        darkAppearance.performAsCurrentDrawingAppearance {
            #expect(theme.unemphasizedSelectionColor != nil)
        }
        
        for type in SyntaxType.allCases {
            let style = try #require(theme.style(for: type))
            #expect(style.color.hueComponent > 0)
        }
    }
    
    
    @Test func graupelThemes() throws {
        
        for name in ["Graupel", "Rain"] {
            let light = try self.loadThemeWithName(name)
            let dark = try self.loadThemeWithName(name + " (Dark)")
            
            #expect(!light.isDarkTheme)
            #expect(dark.isDarkTheme)
            
            for type in SyntaxType.allCases {
                #expect(light.style(for: type) != nil)
                #expect(dark.style(for: type) != nil)
            }
        }
        
        #expect(DefaultSettings.defaults[.theme] as? String == "Graupel")
    }
    
    
    /// Tests if all of bundled themes are valid.
    @Test func bundledThemes() throws {
        
        let themeDirectoryURL = try #require(Bundle.main.url(forResource: self.themeDirectoryName, withExtension: nil))
        let datas = try FileManager.default.contentsOfDirectory(at: themeDirectoryURL, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
            .filter { UTType.cotTheme.preferredFilenameExtension == $0.pathExtension }
            .map { try Data(contentsOf: $0) }
        
        #expect(!datas.isEmpty)
        
        let decoder = JSONDecoder()
        for data in datas {
            #expect(throws: Never.self) { try decoder.decode(Theme.self, from: data) }
        }
    }
}


private extension ThemeTests {
    
    func loadThemeWithName(_ name: String) throws -> Theme {
        
        guard
            let url = Bundle.main.url(forResource: name, withExtension: UTType.cotTheme.preferredFilenameExtension, subdirectory: self.themeDirectoryName)
        else { throw CocoaError(.fileNoSuchFile) }
        
        let data = try Data(contentsOf: url)
        
        return try JSONDecoder().decode(Theme.self, from: data)
    }
}
