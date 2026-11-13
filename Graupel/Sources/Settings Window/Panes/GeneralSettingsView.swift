//
//  GeneralSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2023-01-25.
//
//  ---------------------------------------------------------------------------
//
//  © 2023-2026 1024jp
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

struct GeneralSettingsView: View {
    
    @Environment(\.locale) private var locale
    
    @Namespace private var accessibility
    
    @AppStorage(.quitAlwaysKeepsWindows) private var quitAlwaysKeepsWindows: Bool
    @AppStorage(.noDocumentOnLaunchOption) private var noDocumentOnLaunchOption: NoDocumentOnLaunchOption
    @AppStorage(.enablesAutosaveInPlace) private var enablesAutosaveInPlace: Bool
    @AppStorage(.documentConflictOption) private var documentConflictOption: DocumentConflictOption
    
    @State private var initialEnablesAutosaveInPlace: Bool = false
    
    @State private var isAutosaveChangeConfirmationPresented = false
    @State private var suppressesQuitAlwaysKeepsWindowsChangeConfirmation = false
    @State private var isQuitAlwaysKeepsWindowsChangeConfirmationPresented = false
    @State private var isSettingsExporterPresented = false
    @State private var isWarningsSettingPresented = false
    
    
    // MARK: View
    
    var body: some View {
        
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                Text("On startup:", tableName: "GeneralSettings")
                    .gridColumnAlignment(.trailing)
                
                VStack(alignment: .leading) {
                    Toggle(.init("Reopen windows from last session", table: "GeneralSettings", comment: "verb; checkbox"), isOn: $quitAlwaysKeepsWindows)
                        .onChange(of: self.quitAlwaysKeepsWindows) {
                            guard !self.suppressesQuitAlwaysKeepsWindowsChangeConfirmation else { return }
                            
                            self.isQuitAlwaysKeepsWindowsChangeConfirmationPresented = true
                            self.suppressesQuitAlwaysKeepsWindowsChangeConfirmation = true
                        }
                        .confirmationDialog(.init("NextSessionApplicationConfirmation.title", defaultValue: "The change will be applied first on the next launch.", table: "GeneralSettings"), isPresented: $isQuitAlwaysKeepsWindowsChangeConfirmationPresented) {
                        } message: {
                            Text(.init("NextSessionApplicationConfirmation.nextAfterNext.message", defaultValue: "The app’s behavior will change from the next launch after that one.", table: "GeneralSettings"))
                        }
                    
                    Text("When nothing else is open:", tableName: "GeneralSettings")
                        .accessibilityLabeledPair(role: .label, id: "noDocumentOnLaunchOption", in: self.accessibility)
                    Picker(selection: $noDocumentOnLaunchOption) {
                        ForEach(NoDocumentOnLaunchOption.allCases, id: \.self) {
                            Text($0.label)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.menu)
                    .labelsVisibility(.hidden)
                    .accessibilityLabeledPair(role: .content, id: "noDocumentOnLaunchOption", in: self.accessibility)
                    .padding(.leading, 20)
                }
            }
            
            GridRow {
                Text("Document save:", tableName: "GeneralSettings")
                    .gridColumnAlignment(.trailing)
                
                Toggle(isOn: $enablesAutosaveInPlace) {
                    Text("Enable Auto Save with Versions", tableName: "GeneralSettings", comment: "verb; checkbox")
                    Text("A system feature that automatically overwrites your files while editing. Even if turned off, Graupel still keeps a backup in case it unexpectedly quits.", tableName: "GeneralSettings")
                }
                .onChange(of: self.enablesAutosaveInPlace) { _, newValue in
                    if newValue != self.initialEnablesAutosaveInPlace {
                        self.isAutosaveChangeConfirmationPresented = true
                    }
                }
                .onAppear {
                    self.initialEnablesAutosaveInPlace = self.enablesAutosaveInPlace
                }
                .confirmationDialog(.init("NextSessionApplicationConfirmation.title", defaultValue: "The change will be applied first on the next launch.", table: "GeneralSettings"), isPresented: $isAutosaveChangeConfirmationPresented) {
                    Button(.init("Restart Now", table: "GeneralSettings", comment: "verb; button")) {
                        (NSApp.delegate as? AppDelegate)?.needsRelaunch = true
                        NSApp.terminate(self)
                    }
                    Button(.init("Later", table: "GeneralSettings", comment: "button")) {
                        // do nothing
                    }
                    Button(role: .cancel) {
                        self.enablesAutosaveInPlace.toggle()
                    }
                } message: {
                    Text(.init("NextSessionApplicationConfirmation.message", defaultValue: "Do you want to restart Graupel now?", table: "GeneralSettings"))
                }
            }
            
            
            GridRow {
                Text("When document is changed by another application:", tableName: "GeneralSettings")
                    .accessibilityLabeledPair(role: .label, id: "documentConflictOption", in: self.accessibility)
                    .gridCellColumns(2)
            }.padding(.bottom, -10)
            
            GridRow {
                Color.clear
                    .frame(width: 1, height: 1)
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .accessibilityHidden(true)
                
                Picker(selection: $documentConflictOption) {
                    ForEach(DocumentConflictOption.allCases, id: \.self) {
                        Text($0.label)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityLabeledPair(role: .content, id: "documentConflictOption", in: self.accessibility)
            }
            
            if self.hasLongImportAndExportLabel {
                GridRow {
                    Text("Settings import & export:", tableName: "GeneralSettings")
                        .accessibilityLabeledPair(role: .label, id: "settingsPorting", in: self.accessibility)
                        .gridCellColumns(2)
                }.padding(.bottom, -10)
            }
            
            GridRow {
                if self.hasLongImportAndExportLabel {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                        .accessibilityHidden(true)
                } else {
                    Text("Settings import & export:", tableName: "GeneralSettings")
                        .gridColumnAlignment(.trailing)
                        .accessibilityLabeledPair(role: .label, id: "settingsPorting", in: self.accessibility)
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Button(.init("Action.export.ellipsis.label", defaultValue: "Export…")) {
                            self.isSettingsExporterPresented.toggle()
                        }
                        SettingsImportMenu()
                    }
                }
                .accessibilityLabeledPair(role: .content, id: "settingsPorting", in: self.accessibility)
                .sheet(isPresented: $isSettingsExporterPresented) {
                    ExportSettingsView(includedTypes: PortableSettingsDocument.exportableSettings)
                        .scenePadding()
                        .frame(width: 420)
                        .presentationSizing(.fitted)
                }
            }
            
            GridRow {
                Text("Dialog warnings:", tableName: "GeneralSettings")
                    .gridColumnAlignment(.trailing)
                    .accessibilityLabeledPair(role: .label, id: "dialogWarnings", in: self.accessibility)
                
                Button(.init("Manage Warnings…", table: "GeneralSettings", comment: "verb; button")) {
                    self.isWarningsSettingPresented.toggle()
                }
                .accessibilityLabeledPair(role: .content, id: "dialogWarnings", in: self.accessibility)
                .sheet(isPresented: $isWarningsSettingPresented) {
                    WarningsSettingView()
                        .scenePadding()
                }
            }
            
            Divider()
            
            UpdatesSettingView()
            
            HStack {
                Spacer()
                HelpLink(anchor: "settings_general")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: SettingsPane.width)
    }
    
    
    /// Whether the localized import and export label needs its own row.
    private var hasLongImportAndExportLabel: Bool {
        
        self.locale.language.languageCode.map([.german, .french, .italian, .spanish].contains) == true
    }
}


private struct SettingsImportMenu: View {
    
    @State private var importingSettings: PortableSettingsDocument?
    @State private var error: any Error?
    
    @State private var isImporterPresented = false
    
    
    var body: some View {
        
        Button(.init("Action.import.ellipsis.label", defaultValue: "Import…")) {
            self.isImporterPresented.toggle()
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.cotSettings]) { result in
            switch result {
                case .success(let url):
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing { url.stopAccessingSecurityScopedResource() }
                    }
                    
                    do {
                        self.importingSettings = try PortableSettingsDocument(contentsOf: url)
                    } catch {
                        self.error = error
                    }
                case .failure(let error):
                    self.error = error
            }
        }
        .fileDialogMessage(.init("Choose a Graupel settings archive to import.", table: "SettingsPorting"))
        .fileDialogConfirmationLabel(.init("Action.import.label", defaultValue: "Import"))
        .sheet(item: $importingSettings) { document in
            ImportSettingsView(document: document)
                .scenePadding()
                .frame(width: 420)
                .presentationSizing(.fitted)
        }
        .alert(error: $error)
    }
}


private struct UpdatesSettingView: View {
    
    @ObservedObject private var updater = SoftwareUpdater.shared
    
    
    var body: some View {
        
        GridRow {
            Text("Updates:", tableName: "GeneralSettings")
                .gridColumnAlignment(.trailing)
            
            VStack(alignment: .leading) {
                Toggle(String(localized: "Look for new versions automatically", table: "GeneralSettings", comment: "checkbox"), isOn: $updater.checksAutomatically)
                
                Toggle(String(localized: "Download and install them without asking", table: "GeneralSettings", comment: "checkbox; them refers to new versions of the app"), isOn: $updater.installsAutomatically)
                    .disabled(!self.updater.checksAutomatically)
                    .padding(.leading, 20)
            }
        }
    }
}


private struct WarningsSettingView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage(.suppressesInconsistentLineEndingAlert) private var suppressesInconsistentLineEndingAlert: Bool
    
    
    var body: some View {
        
        VStack {
            Form {
                Text("Suppress the following warnings:", tableName: "GeneralSettings")
                Toggle(.init("Inconsistent line endings", table: "GeneralSettings", comment: "checkbox"), isOn: $suppressesInconsistentLineEndingAlert)
            }
            
            HStack {
                HelpLink(anchor: "howto_manage_warnings")
                Spacer()
                Button(.done) {
                    self.dismiss()
                }.keyboardShortcut(.defaultAction)
            }.padding(.top)
        }
        .fixedSize()
    }
}


private extension NoDocumentOnLaunchOption {
    
    var label: LocalizedStringResource {
        
        switch self {
            case .untitledDocument:
                .init("NoDocumentOnLaunchOption.untitledDocument.label",
                      defaultValue: "Create New Document",
                      table: "GeneralSettings",
                      comment: "verb; menu item")
            case .openPanel:
                .init("NoDocumentOnLaunchOption.openPanel.label",
                      defaultValue: "Show Open Dialog",
                      table: "GeneralSettings",
                      comment: "verb; menu item")
            case .none:
                .init("NoDocumentOnLaunchOption.none.label",
                      defaultValue: "Do Nothing",
                      table: "GeneralSettings",
                      comment: "verb; menu item")
        }
    }
}


private extension DocumentConflictOption {
    
    var label: LocalizedStringResource {
        
        switch self {
            case .ignore:
                .init("DocumentConflictOption.ignore.label",
                      defaultValue: "Keep Graupel’s version",
                      table: "GeneralSettings",
                      comment: "verb; button; version refers to the document’s contents")
            case .notify:
                .init("DocumentConflictOption.notify.label",
                      defaultValue: "Ask how to resolve",
                      table: "GeneralSettings",
                      comment: "verb; button")
            case .revert:
                .init("DocumentConflictOption.revert.label",
                      defaultValue: "Update to modified version",
                      table: "GeneralSettings",
                      comment: "verb; button; version refers to the document’s contents")
        }
    }
}


// MARK: - Preview

#Preview {
    GeneralSettingsView()
        .scenePadding()
}

#Preview("Warnings Setting") {
    WarningsSettingView()
        .scenePadding()
}
