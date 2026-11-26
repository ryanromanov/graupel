//
//  ChromeStyle.swift
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
import Defaults
import Observation

/// The colors of the window chrome, derived from a theme.
///
/// The colors come from keys every theme already has (background, text and keywords),
/// so the chrome follows any theme, including users' own.
struct ChromeStyle: Equatable {
    
    /// The color of the title bar, rail and status bar.
    var background: NSColor
    
    /// The color of the sidebar.
    var sidebar: NSColor
    
    /// The color of hairlines between areas.
    var border: NSColor
    
    /// The color of primary labels.
    var text: NSColor
    
    /// The color of secondary labels and inactive icons.
    var secondaryText: NSColor
    
    /// The color of the active item.
    var accent: NSColor
    
    /// Whether the chrome is dark.
    var isDark: Bool
    
    
    init(theme: Theme) {
        
        let background = theme.background.color.usingColorSpace(.sRGB) ?? theme.background.color
        let text = theme.text.color.usingColorSpace(.sRGB) ?? theme.text.color
        
        self.background = background
        self.sidebar = background.mixed(with: text, fraction: 0.03)
        self.border = background.mixed(with: text, fraction: 0.12)
        self.text = text
        self.secondaryText = background.mixed(with: text, fraction: 0.55)
        self.accent = theme.keywords.color
        self.isDark = theme.isDarkTheme
    }
}


private extension NSColor {
    
    /// Returns a color mixed with another one.
    ///
    /// - Parameters:
    ///   - color: The color to mix in.
    ///   - fraction: The share of the other color, from 0 to 1.
    func mixed(with color: NSColor, fraction: Double) -> NSColor {
        
        self.blended(withFraction: fraction, of: color) ?? self
    }
}


/// The chrome of one window, colored by the window theme.
///
/// `style` is `nil` only if the theme can't be read, in which case views draw with the system style.
@MainActor @Observable final class WindowChrome {
    
    private(set) var style: ChromeStyle?
    
    /// Whether the window is drawn with a custom style.
    var isActive: Bool  { self.style != nil }
    
    /// A counter that changes whenever the style changes, for observers that can't hold the style itself.
    private(set) var revision = 0
    
    @ObservationIgnored private var themeName: String?
    @ObservationIgnored private var observers: Set<AnyCancellable> = []
    
    
    init() {
        
        self.observers = [
            ThemeManager.shared.themeNamesPublisher
                .map(\.window)
                .removeDuplicates()
                .sink { [weak self] in
                    self?.themeName = $0
                    self?.update()
                },
            // follow edits to the theme
            NotificationCenter.default.publisher(for: DidManagerUpdateSettingMessage<ThemeManager>.name, object: ThemeManager.shared)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.update() },
        ]
    }
    
    
    private func update() {
        
        guard
            let themeName = self.themeName,
            let theme = try? ThemeManager.shared.setting(name: themeName)
        else { return }
        
        let style = ChromeStyle(theme: theme)
        
        if self.style != style {
            self.style = style
            self.revision += 1
        }
    }
}
