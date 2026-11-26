//
//  ThemeSelectionTests.swift
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
import Combine
import Testing
import Defaults
@testable import Graupel

@MainActor @Suite(.serialized) final class ThemeSelectionTests {
    
    private static let keys = [
        DefaultKeys.windowTheme.rawValue,
        DefaultKeys.windowThemeAppearance.rawValue,
        DefaultKeys.theme.rawValue,
        DefaultKeys.editorThemeAppearance.rawValue,
        DefaultKeys.editorMatchesWindowTheme.rawValue,
    ]
    
    private let savedValues: [String: Any]
    private let appearance = NSApp.appearance
    
    
    init() {
        
        // start from the default settings, and keep the user’s to restore them
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier!) ?? [:]
        self.savedValues = domain.filter { Self.keys.contains($0.key) }
        Self.keys.forEach(UserDefaults.standard.removeObject(forKey:))
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    
    
    isolated deinit {
        
        Self.keys.forEach(UserDefaults.standard.removeObject(forKey:))
        self.savedValues.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
        NSApp.appearance = self.appearance
    }
    
    
    @Test func editorMatchesTheWindowByDefault() {
        
        let manager = ThemeManager.shared
        
        #expect(manager.themeNames(inDarkMode: false) == ThemeNames(window: "Graupel", editor: "Graupel"))
        #expect(manager.themeNames(inDarkMode: true) == ThemeNames(window: "Graupel (Dark)", editor: "Graupel (Dark)"))
        
        // the editor follows the window’s own light or dark choice
        UserDefaults.standard[.windowTheme] = "Rain"
        UserDefaults.standard[.windowThemeAppearance] = .dark
        #expect(manager.themeNames(inDarkMode: false) == ThemeNames(window: "Rain (Dark)", editor: "Rain (Dark)"))
    }
    
    
    @Test func mixesTheWindowAndEditorThemes() {
        
        UserDefaults.standard[.windowThemeAppearance] = .light
        UserDefaults.standard[.theme] = "Rain"
        UserDefaults.standard[.editorThemeAppearance] = .dark
        UserDefaults.standard[.editorMatchesWindowTheme] = false
        
        #expect(ThemeManager.shared.themeNames(inDarkMode: true) == ThemeNames(window: "Graupel", editor: "Rain (Dark)"))
        
        // an editor theme matching the system ignores the window’s choice
        UserDefaults.standard[.editorThemeAppearance] = .default
        #expect(ThemeManager.shared.themeNames(inDarkMode: true) == ThemeNames(window: "Graupel", editor: "Rain (Dark)"))
        #expect(ThemeManager.shared.themeNames(inDarkMode: false) == ThemeNames(window: "Graupel", editor: "Rain"))
    }
    
    
    @Test func publishesChanges() {
        
        var values: [ThemeNames] = []
        let observer = ThemeManager.shared.themeNamesPublisher
            .sink { values.append($0) }
        defer { observer.cancel() }
        
        #expect(values.map(\.window) == ["Graupel"])
        
        NSApp.appearance = NSAppearance(named: .darkAqua)
        #expect(values.last == ThemeNames(window: "Graupel (Dark)", editor: "Graupel (Dark)"))
        
        UserDefaults.standard[.windowThemeAppearance] = .light
        #expect(values.last?.window == "Graupel")
        
        UserDefaults.standard[.windowTheme] = "Rain"
        #expect(values.last?.window == "Rain")
        
        UserDefaults.standard[.windowThemeAppearance] = .dark
        #expect(values.last?.window == "Rain (Dark)")
        
        // on its own, the editor matches the system, which is dark here
        UserDefaults.standard[.editorMatchesWindowTheme] = false
        #expect(values.last?.editor == "Graupel (Dark)")
        
        UserDefaults.standard[.editorThemeAppearance] = .light
        #expect(values.last?.editor == "Graupel")
        
        UserDefaults.standard[.theme] = "Rain"
        #expect(values.last?.editor == "Rain")
    }
    
    
    @Test func findsVariants() {
        
        let names = ["Solo (Dark)", "Pair (Light)", "Pair (Dark)"]
        
        #expect(ThemeManager.baseName(of: "Pair (Light)") == "Pair")
        #expect(ThemeManager.hasTheme("Pair", in: names))
        #expect(ThemeManager.hasTheme("Solo", in: names))
        #expect(!ThemeManager.hasTheme("Anura", in: names))
        #expect(ThemeManager.shared.variantName(of: "No Such Theme", forDark: false) == nil)
        #expect(ThemeManager.shared.variantName(of: "Rain (Dark)", forDark: false) == "Rain")
    }
    
    
    @Test func migratesTheEarlierSetting() {
        
        let names = ["Graupel", "Graupel (Dark)", "Rain", "Rain (Dark)", "Mine"]
        func migrated(_ saved: [String: Any]) -> NSDictionary {
            ThemeManager.migratedThemeSettings(saved: saved, settingNames: names) as NSDictionary
        }
        
        let theme = DefaultKeys.theme.rawValue
        
        // a theme the user chose is kept for the editor
        #expect(migrated([theme: "Mine"]) == [theme: "Mine", "editorMatchesWindowTheme": false] as NSDictionary)
        
        // a theme locked to light or dark stays locked
        #expect(migrated([theme: "Rain (Dark)", "pinsThemeAppearance": true])
                == [theme: "Rain", "editorMatchesWindowTheme": false,
                    "editorThemeAppearance": AppearanceMode.dark.rawValue] as NSDictionary)
        
        // the default theme, a removed theme, and converted settings are left alone
        #expect(migrated([theme: "Graupel"]).count == 0)
        #expect(migrated([theme: "Anura"]).count == 0)
        #expect(migrated([theme: "Mine", "editorMatchesWindowTheme": true]).count == 0)
        #expect(migrated([:]).count == 0)
    }
    
    
    @Test func migratesTheAppearanceSetting() {
        
        func migrated(_ saved: [String: Any]) -> NSDictionary {
            ThemeManager.migratedThemeSettings(saved: saved, settingNames: ["Graupel", "Rain"]) as NSDictionary
        }
        let dark = AppearanceMode.dark.rawValue
        let light = AppearanceMode.light.rawValue
        
        #expect(migrated(["appearance": dark]) == ["windowThemeAppearance": dark, "editorThemeAppearance": dark] as NSDictionary)
        
        // choices already made for the themes win
        #expect(migrated(["appearance": dark, "windowThemeAppearance": 0, "editorThemeAppearance": light]).count == 0)
        #expect(migrated(["appearance": dark, DefaultKeys.theme.rawValue: "Rain", "pinsThemeAppearance": true])
                == [DefaultKeys.theme.rawValue: "Rain", "editorMatchesWindowTheme": false,
                    "editorThemeAppearance": light, "windowThemeAppearance": dark] as NSDictionary)
        
        #expect(migrated(["appearance": AppearanceMode.default.rawValue]).count == 0)
    }
}
