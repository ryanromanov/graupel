//
//  LanguageServerSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-10-30.
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

import SwiftUI
import Defaults
import StringUtils

struct LanguageServerSettingsView: View {
    
    @State private var syntaxNames: [String] = []
    @State private var selection: String?
    
    
    var body: some View {
        
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                LanguageServerListView(syntaxNames: $syntaxNames, selection: $selection)
                    .frame(width: 140)
                
                GroupBox {
                    if let selection {
                        LanguageServerOptionsView(syntaxName: selection)
                            .id(selection)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No Selection", tableName: "LanguageServerSettings")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 240)
            
            HStack(alignment: .firstTextBaseline) {
                Text("A language server checks your code as you type and marks the problems it finds. Graupel finds the servers of the languages it comes with by itself.", tableName: "LanguageServerSettings")
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                HelpLink(anchor: "settings_language_servers")
            }
        }
        .onAppear {
            self.syntaxNames = Self.listedSyntaxNames
            self.selection = self.selection ?? self.syntaxNames.first
        }
        .frame(width: SettingsPane.width)
    }
    
    
    /// The syntaxes that have a server by default or in the settings.
    static var listedSyntaxNames: [String] {
        
        (LanguageServerCommand.defaultSyntaxNames + UserDefaults.standard[.languageServers].keys)
            .uniqued
            .sorted(using: .localizedStandard)
    }
}


private struct LanguageServerListView: View {
    
    @Binding var syntaxNames: [String]
    @Binding var selection: String?
    
    
    var body: some View {
        
        List(selection: $selection) {
            ForEach(self.syntaxNames, id: \.self) { syntaxName in
                Text(syntaxName)
                    .tag(syntaxName)
                    .lineLimit(1)
                    .listRowSeparator(.hidden)
            }
        }
        .safeAreaBar(edge: .bottom) {
            if #available(macOS 27, *) {
                self.bottomAccessoryView
                    .padding(6)
            } else {
                VStack(spacing: 0) {
                    Divider()
                    self.bottomAccessoryView
                        .padding(6)
                }
            }
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .clipShape(.rect(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator))
        .accessibilityLabel(.init("Languages", table: "LanguageServerSettings"))
    }
    
    
    /// The buttons to add and remove a language.
    @ViewBuilder private var bottomAccessoryView: some View {
        
        HStack {
            Menu {
                ForEach(SyntaxManager.shared.settingNames, id: \.self) { syntaxName in
                    Button(syntaxName) {
                        UserDefaults.standard[.languageServers][syntaxName] = ""
                        withAnimation {
                            self.syntaxNames = LanguageServerSettingsView.listedSyntaxNames
                            self.selection = syntaxName
                        }
                    }
                    .disabled(self.syntaxNames.contains(syntaxName))
                }
            } label: {
                Label(.init("Action.add.label", defaultValue: "Add"), systemImage: "plus")
            }
            .help(.init("Action.add.tooltip", defaultValue: "Add new item"))
            .menuIndicator(.hidden)
            
            Button {
                guard let syntaxName = self.selection else { return }
                
                UserDefaults.standard[.languageServers][syntaxName] = nil
                UserDefaults.standard[.disabledLanguageServers].removeAll { $0 == syntaxName }
                TextDocument.restartLanguageServer(syntaxName: syntaxName)
                withAnimation {
                    self.syntaxNames = LanguageServerSettingsView.listedSyntaxNames
                    self.selection = self.syntaxNames.first
                }
            } label: {
                Label(.init("Action.delete.label", defaultValue: "Delete"), systemImage: "minus")
                    .fontWeight(.medium)
                    .frame(width: 16, height: 16)
            }
            .help(.init("Action.delete.tooltip", defaultValue: "Delete selected items"))
            // languages with a server by default can be turned off, but not removed
            .disabled(self.selection.map { LanguageServerCommand.defaultSyntaxNames.contains($0) } ?? true)
            
            Spacer()
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }
}


private struct LanguageServerOptionsView: View {
    
    var syntaxName: String
    
    @State private var isEnabled = true
    @State private var commandLine = ""
    @State private var isInstalled: Bool?
    @FocusState private var isCommandFocused: Bool
    
    private var store: LanguageServerStatusStore = .shared
    
    
    init(syntaxName: String) {
        
        self.syntaxName = syntaxName
    }
    
    
    var body: some View {
        
        let defaultCommand = LanguageServerCommand.defaultCommand(syntaxName: self.syntaxName)
        
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 14) {
            GridRow {
                Text("Server:", tableName: "LanguageServerSettings")
                    .gridColumnAlignment(.trailing)
                
                Toggle(String(localized: "Check \(self.syntaxName) files as you type", table: "LanguageServerSettings"), isOn: $isEnabled)
                    .onChange(of: self.isEnabled) { _, newValue in
                        guard newValue == UserDefaults.standard[.disabledLanguageServers].contains(self.syntaxName) else { return }
                        
                        var disabled = UserDefaults.standard[.disabledLanguageServers].filter { $0 != self.syntaxName }
                        if !newValue {
                            disabled.append(self.syntaxName)
                        }
                        UserDefaults.standard[.disabledLanguageServers] = disabled
                        TextDocument.restartLanguageServer(syntaxName: self.syntaxName)
                    }
            }
            
            GridRow {
                Text("Command:", tableName: "LanguageServerSettings")
                
                VStack(alignment: .leading) {
                    TextField(.init("Command:", table: "LanguageServerSettings"), text: $commandLine,
                              prompt: Text(defaultCommand?.commandLine ?? ""))
                    .labelsVisibility(.hidden)
                    .font(.body.monospaced())
                    .focused($isCommandFocused)
                    .onSubmit { self.saveCommandLine() }
                    .onChange(of: self.isCommandFocused) { _, isFocused in
                        if !isFocused {
                            self.saveCommandLine()
                        }
                    }
                    
                    Text(self.commandDescription(defaultCommand: defaultCommand))
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(!self.isEnabled)
            }
            
            GridRow {
                Text("Status:", tableName: "LanguageServerSettings")
                
                HStack(alignment: .firstTextBaseline) {
                    let status = self.status
                    Label {
                        Text(status.message)
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        StatusImage(status: status.image)
                            .imageScale(.small)
                    }
                    .labelIconToTitleSpacing(6)
                    
                    Spacer()
                    
                    Button(String(localized: "Restart", table: "LanguageServerSettings", comment: "button")) {
                        TextDocument.restartLanguageServer(syntaxName: self.syntaxName)
                        self.isInstalled = nil
                    }
                    .disabled(!self.isEnabled)
                }
            }
        }
        .onAppear {
            self.isEnabled = !UserDefaults.standard[.disabledLanguageServers].contains(self.syntaxName)
            self.commandLine = UserDefaults.standard[.languageServers][self.syntaxName] ?? ""
        }
        .onDisappear {
            self.saveCommandLine()
        }
        .task(id: self.store.statuses[self.syntaxName]) {
            // check whether the server is installed while no document uses it
            guard
                self.store.statuses[self.syntaxName] == nil,
                let command = LanguageServerCommand.command(syntaxName: self.syntaxName),
                command.source != .settings
            else {
                self.isInstalled = nil
                return
            }
            
            let searchPath = await ShellSearchPath.directories()
            self.isInstalled = command.executableURL(searchPath: searchPath) != nil
        }
    }
    
    
    /// Saves the edited command and restarts the server if it changed.
    private func saveCommandLine() {
        
        let commandLine = self.commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = UserDefaults.standard[.languageServers][self.syntaxName]
        
        guard commandLine != (stored ?? "") else { return }
        
        // keep an empty entry for a language without a default server, so that it stays in the list
        if commandLine.isEmpty, LanguageServerCommand.defaultSyntaxNames.contains(self.syntaxName) {
            UserDefaults.standard[.languageServers][self.syntaxName] = nil
        } else {
            UserDefaults.standard[.languageServers][self.syntaxName] = commandLine
        }
        TextDocument.restartLanguageServer(syntaxName: self.syntaxName)
    }
    
    
    private func commandDescription(defaultCommand: LanguageServerCommand?) -> String {
        
        switch defaultCommand?.source {
            case .builtIn:
                String(localized: "Leave empty to use the standard server for \(self.syntaxName).", table: "LanguageServerSettings")
            case .script:
                String(localized: "Leave empty to use your script in the Application Scripts folder.", table: "LanguageServerSettings")
            case .settings, nil:
                String(localized: "A command or the path of a script that runs the server on standard input and output.", table: "LanguageServerSettings")
        }
    }
    
    
    /// The status to show.
    private var status: (message: String, image: StatusImage.Status) {
        
        if !self.isEnabled {
            return (String(localized: "Off", table: "LanguageServerSettings"), .none)
        }
        
        switch self.store.statuses[self.syntaxName] {
            case .launching:
                return (String(localized: "Starting…", table: "LanguageServerSettings"), .partiallyAvailable)
            case .running(let url):
                return (String(localized: "Running \((url.path as NSString).abbreviatingWithTildeInPath)", table: "LanguageServerSettings"), .available)
            case .notInstalled(let command):
                return (String(localized: "“\(command)” isn’t installed.", table: "LanguageServerSettings"), .unavailable)
            case .failed(let reason):
                return (String(localized: "Stopped: \(reason)", table: "LanguageServerSettings"), .unavailable)
            case nil:
                break
        }
        
        guard let command = LanguageServerCommand.command(syntaxName: self.syntaxName) else {
            return (String(localized: "Enter a command to use a server.", table: "LanguageServerSettings"), .none)
        }
        
        if self.isInstalled == false {
            return (String(localized: "“\(command.name)” isn’t installed.", table: "LanguageServerSettings"), .unavailable)
        }
        
        return (String(localized: "Starts when you open a \(self.syntaxName) file.", table: "LanguageServerSettings"), .none)
    }
}


// MARK: - Preview

#Preview {
    LanguageServerSettingsView()
        .scenePadding()
}
