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
import ControlUI
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
    
    /// The solid fill of the selected tab or row.
    var selection: NSColor
    
    /// The color of text and icons on the selection.
    var onSelection: NSColor
    
    /// The fill of text fields.
    var fill: NSColor
    
    /// Whether the chrome is dark.
    var isDark: Bool
    
    
    /// The lowest contrast between the selection and the text on it.
    ///
    /// Short labels stay readable here, and a higher value would lose the muted color.
    static let minimumContrast = 3.5
    
    
    init(theme: Theme) {
        
        let background = theme.background.color.usingColorSpace(.sRGB) ?? theme.background.color
        let text = theme.text.color.usingColorSpace(.sRGB) ?? theme.text.color
        
        self.background = background
        self.sidebar = background.mixed(with: text, fraction: 0.03)
        self.border = background.mixed(with: text, fraction: 0.12)
        self.text = text
        self.secondaryText = background.mixed(with: text, fraction: 0.55)
        let accent = theme.keywords.color.usingColorSpace(.sRGB) ?? theme.keywords.color
        self.accent = theme.keywords.color
        self.fill = background.mixed(with: text, fraction: 0.08)
        self.isDark = theme.isDarkTheme
        
        // a grayed accent, moved away from the text color on it until the text is easy to read
        let onSelection: NSColor = theme.isDarkTheme ? background : .white
        let away: NSColor = theme.isDarkTheme ? .white : .black
        var selection = accent.mixed(with: background.mixed(with: text, fraction: 0.45), fraction: 0.45)
        for _ in 0..<40 where selection.contrastRatio(with: onSelection) < Self.minimumContrast {
            selection = selection.mixed(with: away.usingColorSpace(.sRGB) ?? away, fraction: 0.04)
        }
        self.selection = selection
        // a custom theme can leave too little room, so fall back to black or white
        self.onSelection = (selection.contrastRatio(with: onSelection) >= Self.minimumContrast)
            ? onSelection
            : [NSColor.black, .white].max { selection.contrastRatio(with: $0) < selection.contrastRatio(with: $1) }!
    }
}


extension NSColor {
    
    /// Returns the contrast ratio with another color, as defined by WCAG.
    ///
    /// - Parameter color: The color to compare with.
    /// - Returns: A ratio from 1 to 21.
    func contrastRatio(with color: NSColor) -> Double {
        
        let luminances = [self.relativeLuminance, color.relativeLuminance].sorted()
        
        return (luminances[1] + 0.05) / (luminances[0] + 0.05)
    }
    
    
    /// The relative luminance in the sRGB color space.
    private var relativeLuminance: Double {
        
        guard let color = self.usingColorSpace(.sRGB) else { return 0 }
        
        let components = [color.redComponent, color.greenComponent, color.blueComponent]
            .map { Double($0) }
            .map { ($0 <= 0.04045) ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        
        return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
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


extension ChromeStyle {
    
    /// The colors of the sidebar’s and inspector’s pane switchers.
    var tabBarColors: FlatTabBar.Colors {
        
        FlatTabBar.Colors(selection: self.selection, onSelection: self.onSelection,
                          icon: self.secondaryText, border: self.border)
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
