//
//  AppearanceSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-04-18.
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

import SwiftUI
import Combine
import Defaults
import StringUtils

struct AppearanceSettingsView: View {
    
    private static let windowAlphaRange = 0.2...1.0
    private static let verticalSpace: CGFloat = 6
    
    @Environment(\.layoutDirection) private var layoutDirection
    
    @AppStorage(.font) private var font
    @AppStorage(.shouldAntialias) private var shouldAntialias
    @AppStorage(.ligature) private var ligature
    @AppStorage(.monospacedFont) private var monospacedFont
    @AppStorage(.monospacedShouldAntialias) private var monospacedShouldAntialias
    @AppStorage(.monospacedLigature) private var monospacedLigature
    
    @AppStorage(.lineHeight) private var lineHeight
    @AppStorage(.windowAlpha) private var windowAlpha
    
    @State private var isThemeEditorPresented = false
    @State private var monospacedAlertFont: Data?
    @State private var isRestoringMonospacedFont = false
    
    
    var body: some View {
        
        VStack {
            Form {
                LabeledContent(.init("Standard font:", table: "AppearanceSettings")) {
                    FontSettingView(data: $font, fallback: FontType.standard.systemFont(), antialias: $shouldAntialias, ligature: $ligature)
                }
                .padding(.bottom, Self.verticalSpace)
                
                LabeledContent(.init("Monospaced font:", table: "AppearanceSettings")) {
                    FontSettingView(data: $monospacedFont, fallback: FontType.monospaced.systemFont(), antialias: $monospacedShouldAntialias, ligature: $monospacedLigature)
                        .onChange(of: self.monospacedFont) { oldValue, newValue in
                            if self.isRestoringMonospacedFont {
                                self.isRestoringMonospacedFont = false
                                return
                            }
                            guard
                                let newValue,
                                let font = NSFont(archivedData: newValue),
                                !font.isFixedPitch
                            else { return }
                            
                            // ignore if only font size changed
                            if let oldValue,
                               let oldFont = NSFont(archivedData: oldValue),
                               font.fontName == oldFont.fontName
                            { return }
                            
                            self.monospacedAlertFont = oldValue
                        }
                        .alert(.init("MonospacedFontAlert.title", defaultValue: "The selected font doesn’t seem to be monospaced.", table: "AppearanceSettings"), item: $monospacedAlertFont) { font in
                            Button(.ok) { }
                            Button(role: .cancel) {
                                self.isRestoringMonospacedFont = true
                                self.monospacedFont = font
                            }
                        } message: { _ in
                            Text(.init("MonospacedFontAlert.message", defaultValue: "Do you want to use it for the monospaced font?", table: "AppearanceSettings", comment: "“it” is the selected font in the title."))
                        }
                }
                .padding(.bottom, Self.verticalSpace)
                
                LabeledContent(.init("Line height:", table: "AppearanceSettings")) {
                    HStack(alignment: .firstTextBaseline) {
                        Stepper(value: $lineHeight, in: 0.1...10, step: 0.1, format: .number.precision(.fractionLength(1...2)).numberLocale, label: EmptyView.init)
                            .monospacedDigit()
                            .multilineTextAlignment(self.layoutDirection == .rightToLeft ? .leading : .trailing)
                            .accessibilityValue(.init("\(self.lineHeight, format: .number) times", table: "AppearanceSettings",
                                                      comment: "accessibility label for line height"))
                        
                        Text("times", tableName: "AppearanceSettings", comment: "unit for line height")
                            .accessibilityHidden(true)
                    }
                    .labelsHidden()
                }
                .padding(.bottom, Self.verticalSpace)
                
                ThemeSelectionView()
                
                LabeledContent {
                    Button(.init("Create or Edit Theme…", table: "AppearanceSettings", comment: "button; opens the theme editor")) {
                        self.isThemeEditorPresented = true
                    }
                } label: {
                    EmptyView()
                }
                .padding(.bottom, Self.verticalSpace)
                
                LabeledContent(.init("Editor opacity:", table: "AppearanceSettings")) {
                    HStack(alignment: .firstTextBaseline) {
                        Slider(value: self.windowAlphaBinding, enabledBounds: Self.windowAlphaRange) {
                            EmptyView()
                        } currentValueLabel: {
                            Text(self.windowAlphaBinding.wrappedValue, format: .percent)
                        } minimumValueLabel: {
                            OpacitySample(opacity: Self.windowAlphaRange.lowerBound)
                                .frame(height: 20)
                                .help(.init("OpacitySlider.minimumValue.label", defaultValue: "Transparent", table: "AppearanceSettings"))
                        } maximumValueLabel: {
                            OpacitySample(opacity: Self.windowAlphaRange.upperBound)
                                .frame(height: 20)
                                .help(.init("OpacitySlider.maximumValue.label", defaultValue: "Opaque", table: "AppearanceSettings"))
                        } ticks: {
                            SliderTickContentForEach(Array(stride(from: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? 0.2 : 0, through: 1, by: 0.1)), id: \.self) { value in
                                SliderTick(value)
                            }
                        }
                        .frame(maxWidth: 260)
                        
                        TextField(value: self.windowAlphaBinding, format: .percent.precision(.fractionLength(0)), prompt: Text(1, format: .percent), label: EmptyView.init)
                            .monospacedDigit()
                            .multilineTextAlignment(self.layoutDirection == .rightToLeft ? .leading : .trailing)
                            .frame(width: 64)
                    }
                    .labelsHidden()
                }
                .accessibilityElement(children: .contain)
            }
            .padding(.bottom)
            
            HStack {
                Spacer()
                HelpLink(anchor: "settings_appearance")
            }
        }
        .frame(width: SettingsPane.width)
        .sheet(isPresented: $isThemeEditorPresented) {
            ThemeEditorSheet()
        }
    }
    
    
    /// A binding for the editor opacity clamped to the supported range.
    private var windowAlphaBinding: Binding<Double> {
        
        Binding(get: { self.windowAlpha.clamped(to: Self.windowAlphaRange) },
                set: { self.windowAlpha = $0.clamped(to: Self.windowAlphaRange) })
    }
}


/// The list of themes and their colors, in a sheet.
private struct ThemeEditorSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    
    
    var body: some View {
        
        VStack {
            ThemeView()
                .frame(height: 360)
            
            HStack {
                HelpLink(anchor: "howto_customize_theme")
                Spacer()
                Button(.init("Done", table: "AppearanceSettings", comment: "button; closes the theme editor")) {
                    self.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .scenePadding()
        .frame(width: SettingsPane.width)
        .onDisappear {
            // the Colors window would otherwise stay open with nothing to change
            if NSColorPanel.sharedColorPanelExists {
                NSColorPanel.shared.close()
            }
        }
    }
}


/// The menus to choose the themes of the window and the editor.
private struct ThemeSelectionView: View {
    
    private var manager: ThemeManager = .shared
    
    @AppStorage(.windowTheme) private var windowTheme
    @AppStorage(.windowThemeAppearance) private var windowThemeAppearance
    @AppStorage(.theme) private var editorTheme
    @AppStorage(.editorThemeAppearance) private var editorThemeAppearance
    @AppStorage(.editorMatchesWindowTheme) private var editorMatchesWindowTheme
    
    
    var body: some View {
        
        LabeledContent(.init("Window theme:", table: "AppearanceSettings")) {
            HStack {
                Picker(.init("Window theme:", table: "AppearanceSettings"), selection: $windowTheme) {
                    ForEach(ThemeManager.windowThemeNames, id: \.self) {
                        Text($0)
                    }
                }
                .fixedSize()
                
                AppearanceModePicker(.init("Window theme appearance", table: "AppearanceSettings"), selection: $windowThemeAppearance)
            }
            .labelsHidden()
        }
        
        LabeledContent(.init("Editor theme:", table: "AppearanceSettings")) {
            HStack {
                Picker(.init("Editor theme:", table: "AppearanceSettings"), selection: self.editorSelection) {
                    Text("Match Window", tableName: "AppearanceSettings", comment: "menu item; the editor uses the window’s theme")
                        .tag(String?.none)
                    Divider()
                    ForEach(self.editorThemeNames, id: \.self) {
                        Text($0).tag(String?.some($0))
                    }
                }
                .fixedSize()
                
                if !self.editorMatchesWindowTheme {
                    AppearanceModePicker(.init("Editor theme appearance", table: "AppearanceSettings"), selection: $editorThemeAppearance)
                }
            }
            .labelsHidden()
        }
        .padding(.bottom, 6)
    }
    
    
    /// The names of the themes for the editor, listing a pair of light and dark themes once.
    private var editorThemeNames: [String] {
        
        self.manager.settingNames.map(ThemeManager.baseName(of:)).uniqued
    }
    
    
    /// The editor theme, or `nil` to match the window.
    private var editorSelection: Binding<String?> {
        
        Binding(get: { self.editorMatchesWindowTheme ? nil : ThemeManager.baseName(of: self.editorTheme) },
                set: { name in
                    if let name {
                        self.editorTheme = name
                    }
                    self.editorMatchesWindowTheme = (name == nil)
                })
    }
}


/// A menu to choose whether a theme is light or dark, or matches the system.
private struct AppearanceModePicker: View {
    
    private var title: LocalizedStringResource
    @Binding private var selection: AppearanceMode
    
    
    init(_ title: LocalizedStringResource, selection: Binding<AppearanceMode>) {
        
        self.title = title
        self._selection = selection
    }
    
    
    var body: some View {
        
        Picker(self.title, selection: $selection) {
            ForEach(AppearanceMode.allCases, id: \.self) {
                Text($0.label)
            }
        }
        .fixedSize()
    }
}


private struct FontSettingView: View {
    
    @Binding var data: Data?
    var fallback: NSFont
    @Binding var antialias: Bool
    @Binding var ligature: Bool
    
    private var font: Binding<NSFont> {
        
        Binding(get: { self.data.flatMap(NSFont.init(archivedData:)) ?? self.fallback },
                set: { self.data = (try? $0.archivedData) ?? self.data })
    }
    
    
    var body: some View {
        
        VStack(alignment: .leading) {
            HStack {
                let font = self.font.wrappedValue
                
                AntialiasingText(font.displayNameAndSize)
                    .antialiasDisabled(!self.antialias)
                    .font(nsFont: font.withSize(0))
                    .help(font.displayNameAndSize)
                    .frame(maxWidth: 260)
                    .alignmentGuide(.firstTextBaseline, computeValue: \.height)
                FontSizeStepper(.init("Font size", table: "AppearanceSettings"), font: self.font)
                    .accessibilityValue(.init("\(font.pointSize, format: .number) points",
                                              table: "AppearanceSettings", comment: "accessibility label for font size"))
                    .labelsHidden()
                    .padding(.leading, -4)
                FontPicker(.init("Select…", table: "AppearanceSettings", comment: "verb; button; opens the font picker"), selection: self.font)
            }
            HStack {
                Toggle(.init("Antialias", table: "AppearanceSettings", comment: "verb; checkbox"), isOn: $antialias)
                Toggle(.init("Ligatures", table: "AppearanceSettings", comment: "noun; checkbox"), isOn: $ligature)
            }.controlSize(.small)
        }
    }
}


private extension NSFont {
    
    /// Returns the font name and size to display.
    var displayNameAndSize: String {
        
        "\(self.displayName ?? self.fontName)  \(self.pointSize.formatted())"
    }
}


private extension AppearanceMode {
    
    var label: LocalizedStringResource {
        
        switch self {
            case .default:
                .init("AppearanceMode.automatic.label",
                      defaultValue: "Match System",
                      table: "AppearanceSettings",
                      comment: "verb; menu item; use the system’s appearance setting")
            case .light:
                .init("AppearanceMode.light.label",
                      defaultValue: "Light",
                      table: "AppearanceSettings")
            case .dark:
                .init("AppearanceMode.dark.label",
                      defaultValue: "Dark",
                      table: "AppearanceSettings")
        }
    }
}


// MARK: - Preview

#Preview {
    AppearanceSettingsView()
        .scenePadding()
}

#Preview("FontSettingView") {
    @Previewable @State var antialias = false
    @Previewable @State var ligature = false
    
    FontSettingView(data: .constant(Data()), fallback: .systemFont(ofSize: 0), antialias: $antialias, ligature: $ligature)
        .scenePadding()
}
