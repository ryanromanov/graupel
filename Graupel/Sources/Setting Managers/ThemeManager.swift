//
//  ThemeManager.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-04-12.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2026 1024jp
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
import Foundation
import UniformTypeIdentifiers
import Defaults
import StringUtils

/// The names of the themes in use.
struct ThemeNames: Equatable, Sendable {
    
    /// The theme that colors the window.
    var window: String
    
    /// The theme that colors the editor.
    var editor: String
}


@MainActor @Observable final class ThemeManager: SettingFileManaging {
    
    typealias Setting = Theme
    
    
    // MARK: Public Properties
    
    static let shared = ThemeManager()
    
    
    // MARK: Setting File Managing Properties
    
    static let directoryName: String = "Themes"
    static let constantSettings: [String: Setting] = [:]
    let reservedNames: [String] = []
    
    /// The themes that can color a window.
    static let windowThemeNames = ["Graupel", "Rain"]
    
    let bundledSettingNames: [String]
    var settingNames: [String] = []
    var cachedSettings: [String: Setting] = [:]
    
    
    // MARK: Lifecycle
    
    private init() {
        
        // cache bundled setting names
        self.bundledSettingNames = Bundle.main.urls(forResourcesWithExtension: Setting.fileType.preferredFilenameExtension, subdirectory: Self.directoryName)!
            .map(Self.settingName(from:))
            .sorted(using: .localizedStandard)
        
        self.migrateThemeSettings()
        
        // cache user setting names
        self.settingNames = self.listAvailableSettings()
    }
    
    
    // MARK: Public Methods
    
    /// Returns whether the given setting name is a dark theme.
    ///
    /// - Parameter name: The setting name to test.
    /// - Returns: A Boolean value.
    nonisolated static func isDark(name: String) -> Bool {
        
        name.hasSuffix("(Dark)")
    }
    
    
    /// Returns a theme name without its appearance suffix.
    ///
    /// - Parameter name: The setting name.
    /// - Returns: The name that the light and dark variants share.
    nonisolated static func baseName(of name: String) -> String {
        
        name.replacing(/\ \((Dark|Light)\)$/, with: "", maxReplacements: 1)
    }
    
    
    /// Returns whether there is a theme with the given base name, in either variant.
    ///
    /// - Parameters:
    ///   - name: A setting name or a base name.
    ///   - settingNames: The names of the existing settings.
    /// - Returns: A Boolean value.
    nonisolated static func hasTheme(_ name: String, in settingNames: [String]) -> Bool {
        
        let baseName = self.baseName(of: name)
        
        return settingNames.contains { self.baseName(of: $0) == baseName }
    }
    
    
    /// Converts the theme settings saved by an earlier version, which stored one theme for the editor
    /// and a light or dark appearance for the windows.
    ///
    /// - Parameters:
    ///   - saved: The values the user has saved.
    ///   - settingNames: The names of the existing settings.
    /// - Returns: The values to save, or an empty dictionary if there's nothing to convert.
    nonisolated static func migratedThemeSettings(saved: [String: Any], settingNames: [String]) -> [String: Any] {
        
        var values = self.migratedEditorTheme(saved: saved, settingNames: settingNames)
        
        // a light or dark appearance now belongs to each theme
        if let mode = saved["appearance"] as? Int, mode != AppearanceMode.default.rawValue {
            for key in [DefaultKeys.windowThemeAppearance.rawValue, DefaultKeys.editorThemeAppearance.rawValue]
            where saved[key] == nil && values[key] == nil {
                values[key] = mode
            }
        }
        
        return values
    }
    
    
    /// Converts the editor theme saved by an earlier version.
    ///
    /// - Parameters:
    ///   - saved: The values the user has saved.
    ///   - settingNames: The names of the existing settings.
    /// - Returns: The values to save, or an empty dictionary if there's nothing to convert.
    private nonisolated static func migratedEditorTheme(saved: [String: Any], settingNames: [String]) -> [String: Any] {
        
        guard
            saved[DefaultKeys.editorMatchesWindowTheme.rawValue] == nil,
            let name = saved[DefaultKeys.theme.rawValue] as? String,
            self.hasTheme(name, in: settingNames)  // a removed theme is replaced by the default
        else { return [:] }
        
        let baseName = self.baseName(of: name)
        let isPinned = saved["pinsThemeAppearance"] as? Bool == true
        
        // the default theme follows the window, which has it too
        guard isPinned || baseName != DefaultSettings.defaults[.theme] as? String else { return [:] }
        
        var values: [String: Any] = [
            DefaultKeys.editorMatchesWindowTheme.rawValue: false,
            DefaultKeys.theme.rawValue: baseName,
        ]
        if isPinned {
            let mode: AppearanceMode = self.isDark(name: name) ? .dark : .light
            values[DefaultKeys.editorThemeAppearance.rawValue] = mode.rawValue
        }
        
        return values
    }
    
    
    /// Returns the themes to use under the specified system appearance.
    ///
    /// - Parameter inDarkMode: The system appearance to evaluate.
    /// - Returns: The resolved theme names.
    func themeNames(inDarkMode: Bool) -> ThemeNames {
        
        let defaults = UserDefaults.standard
        let windowUsesDark = defaults[.windowThemeAppearance].isDark(matchingSystem: inDarkMode)
        let defaultName = DefaultSettings.defaults[.windowTheme] as! String
        let window = self.variantName(of: defaults[.windowTheme], forDark: windowUsesDark)
            ?? self.variantName(of: defaultName, forDark: windowUsesDark)!
        
        guard !defaults[.editorMatchesWindowTheme] else { return ThemeNames(window: window, editor: window) }
        
        let editorUsesDark = defaults[.editorThemeAppearance].isDark(matchingSystem: inDarkMode)
        let editor = self.variantName(of: defaults[.theme], forDark: editorUsesDark) ?? window
        
        return ThemeNames(window: window, editor: editor)
    }
    
    
    /// Returns the user's editor theme name for the specified system appearance.
    ///
    /// - Parameters:
    ///   - inDarkMode: The system appearance to evaluate.
    /// - Returns: The resolved theme name.
    func userDefaultSettingName(inDarkMode: Bool) -> String {
        
        self.themeNames(inDarkMode: inDarkMode).editor
    }
    
    
    /// Returns the name of the theme to use for the given base name, preferring the requested variant.
    ///
    /// - Parameters:
    ///   - name: A setting name or a base name.
    ///   - forDark: `true` when the dark mode version is preferred.
    /// - Returns: A setting name, or `nil` if there's no theme with the name.
    func variantName(of name: String, forDark: Bool) -> String? {
        
        let baseName = Self.baseName(of: name)
        
        return self.equivalentSettingName(to: baseName, forDark: forDark)
            ?? [baseName, baseName + " (Dark)", baseName + " (Light)"].first(where: self.settingNames.contains)
    }
    
    
    /// Returns the setting name for the dark or light variant of the given setting, if available.
    ///
    /// - Parameters:
    ///   - name: The base setting name.
    ///   - forDark: `true` when the dark mode version should be returned.
    /// - Returns: A setting name, or `nil` if none exists.
    func equivalentSettingName(to name: String, forDark: Bool) -> String? {
        
        let baseName = Self.baseName(of: name)
        
        let settingName = baseName + " " + (forDark ? "(Dark)" : "(Light)")
        if self.settingNames.contains(settingName) {
            return settingName
        }
        
        if !forDark, self.settingNames.contains(baseName) {
            return baseName
        }
        
        return nil
    }
    
    
    /// Publishes the themes to use, following the system appearance and the theme settings.
    ///
    /// Observe this rather than the appearance of a window or view, which is set to match its theme.
    var themeNamesPublisher: AnyPublisher<ThemeNames, Never> {
        
        let defaults = UserDefaults.standard
        
        // -> Don’t combine these with `combineLatest`: a defaults publisher then drops its initial value,
        //    and nothing is published until a setting changes. The appearance publisher provides the first value.
        let changes: [AnyPublisher<Void, Never>] = [
            NSApp.publisher(for: \.effectiveAppearance).map { _ in }.eraseToAnyPublisher(),
            defaults.publisher(for: .windowTheme).map { _ in }.eraseToAnyPublisher(),
            defaults.publisher(for: .windowThemeAppearance).map { _ in }.eraseToAnyPublisher(),
            defaults.publisher(for: .theme).map { _ in }.eraseToAnyPublisher(),
            defaults.publisher(for: .editorThemeAppearance).map { _ in }.eraseToAnyPublisher(),
            defaults.publisher(for: .editorMatchesWindowTheme).map { _ in }.eraseToAnyPublisher(),
        ]
        
        return Publishers.MergeMany(changes)
            .map { [unowned self] in self.themeNames(inDarkMode: NSApp.effectiveAppearance.isDark) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    
    /// Saves the given setting to the user domain.
    ///
    /// - Parameters:
    ///   - setting: The setting to save.
    ///   - name: The name under which to save the setting.
    func save(setting: Setting, name: String) throws {
        
        try self.write(setting: setting, name: name)
        
        self.cachedSettings[name] = setting
        
        let change: SettingChange = self.settingNames.contains(name)
            ? .updated(from: name, to: name)
            : .added(name)
        self.updateSettingList(change: change)
    }
    
    
    /// Creates a new untitled setting.
    ///
    /// - Returns: The name of the created setting.
    @discardableResult func createUntitledSetting() throws -> String {
        
        let name = String(localized: "Untitled", comment: "default name")
            .appendingUniqueNumber(in: self.settingNames)
        
        try self.save(setting: Setting(), name: name)
        
        return name
    }
    
    
    // MARK: Setting File Managing
    
    /// Builds the list of available settings by considering both user and bundled settings.
    ///
    /// - Returns: Available setting names.
    nonisolated func listAvailableSettings() -> [String] {
        
        let userSettingNames = self.userSettingFileURLs
            .map(Self.settingName(from:))
        
        let settingNames = Set(self.bundledSettingNames + userSettingNames)
            .sorted(using: .localizedStandard)
        
        // reset user defaults if not found
        if !Self.hasTheme(UserDefaults.standard[.theme], in: settingNames) {
            UserDefaults.standard.restore(key: .theme)
            UserDefaults.standard.restore(key: .editorMatchesWindowTheme)
        }
        
        return settingNames
    }
    
    
    // MARK: Private Methods
    
    /// Carries over the theme settings saved by an earlier version.
    private func migrateThemeSettings() {
        
        guard
            let identifier = Bundle.main.bundleIdentifier,
            let saved = UserDefaults.standard.persistentDomain(forName: identifier)
        else { return }
        
        let settingNames = self.bundledSettingNames + self.userSettingFileURLs.map(Self.settingName(from:))
        
        for (key, value) in Self.migratedThemeSettings(saved: saved, settingNames: settingNames) {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}


extension AppearanceMode {
    
    /// Returns whether the mode means the dark appearance.
    ///
    /// - Parameter matchingSystem: Whether the system uses the dark appearance.
    /// - Returns: A Boolean value.
    func isDark(matchingSystem: Bool) -> Bool {
        
        switch self {
            case .default: matchingSystem
            case .light: false
            case .dark: true
        }
    }
}
