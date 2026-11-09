//
//  StatusBar.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-07-11.
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
import ControlUI
import Defaults
import DocumentFile
import FileEncoding
import LineEnding

struct StatusBar: View {
    
    @MainActor @Observable final class Model {
        
        var document: DataDocument?  { willSet { self.invalidateObservation(document: newValue) } }
        
        private var isActive: Bool = false
        private var defaultsObserver: AnyCancellable?
        
        
        init(document: DataDocument? = nil) {
            
            self.document = document
        }
    }
    
    
    @State var model: Model
    
    @AppStorage(.prefersOpaqueBarBackground) private var prefersOpaqueBarBackground
    @AppStorage(.showStatusBar) private var showsStatusBar
    
    
    var body: some View {
        
        if #available(macOS 27, *) {
            self.contentView
        } else {
            VStack(spacing: 0) {
                Divider()
                self.contentView
            }
        }
    }
    
    
    @ContentBuilder private var contentView: some View {
        
        HStack {
            if let document = self.model.document as? TextDocument {
                if !document.isEditable {
                    NotEditableBadge()
                        .transition(.opacity.animation(.linear))
                }
                EditorCountView(result: document.counter.result)
                    .layoutPriority(-1)
                
                if let mark = document.diagnosticAtCursor {
                    DiagnosticView(mark: mark)
                        .layoutPriority(-2)
                        .transition(.opacity.animation(.linear))
                } else if let status = document.languageServerStatus, status.isProblem {
                    LanguageServerProblemView(syntaxName: document.syntaxName, status: status)
                        .layoutPriority(-2)
                        .transition(.opacity.animation(.linear))
                }
            }
            
            Spacer()
            
            if let document = self.model.document {
                FileSizeView(size: document.fileAttributes?.size)
                    .padding(.trailing, (document is TextDocument) ? 0 : 8)
                
                if let document = document as? TextDocument {
                    DocumentStatusBar(document: document)
                }
            }
        }
        .onAppear {
            if self.showsStatusBar {
                self.model.onAppear()
            } else {
                self.model.onDisappear()
            }
        }
        .onDisappear {
            self.model.onDisappear()
        }
        .onChange(of: self.showsStatusBar) { _, newValue in
            if newValue {
                self.model.onAppear()
            } else {
                self.model.onDisappear()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(.init("Status Bar", table: "Document", comment: "accessibility label"))
        .buttonStyle(.borderless)
        .controlSize(.small)
        .lineLimit(1)
        .modifier { container in
            if #available(macOS 27, *) {
                container
                    .frame(height: 13)
            } else {
                container
                    .frame(height: 18)
                    .padding(.vertical, 7)
                    .padding(.leading)
                    .containerCornerOffset(.horizontal, sizeToFit: true)
            }
        }
        .background(.windowBackground.opacity(self.prefersOpaqueBarBackground ? 1 : 0))
        .animation(.default, value: self.prefersOpaqueBarBackground)
    }
}


// MARK: Private APIs

private extension StatusBar.Model {
    
    /// Called when the view is fully transitioned onto the screen.
    func onAppear() {
        
        self.isActive = true
        
        self.invalidateObservation(document: self.document)
        
        // observe changes in defaults
        let editorDefaultKeys: [DefaultKey<Bool>] = [
            .showStatusBarLines,
            .showStatusBarChars,
            .showStatusBarWords,
            .showStatusBarLocation,
            .showStatusBarLine,
            .showStatusBarColumn,
        ]
        let publishers = editorDefaultKeys.map { UserDefaults.standard.publisher(for: $0) }
        self.defaultsObserver = Publishers.MergeMany(publishers)
            .map { _ in UserDefaults.standard.statusBarEditorInfo }
            .sink { [weak self] in (self?.document as? TextDocument)?.counter.statusBarRequirements = $0 }
    }
    
    
    /// Called after the view is removed from the view hierarchy in a window.
    func onDisappear() {
        
        self.isActive = false
        
        self.defaultsObserver = nil
        (self.document as? TextDocument)?.counter.statusBarRequirements = []
    }
    
    
    /// Updates observations.
    ///
    /// - Parameter document: The document to observe.
    private func invalidateObservation(document: DataDocument?) {
        
        (self.document as? TextDocument)?.counter.statusBarRequirements = []
        
        if let document = document as? TextDocument, self.isActive {
            document.counter.statusBarRequirements = UserDefaults.standard.statusBarEditorInfo
        }
    }
}


private struct NotEditableBadge: View {
    
    var body: some View {
        
        Label(.init("Not editable", table: "Document"), systemImage: "pencil.slash")
            .help(.init("The document is not editable.", table: "Document", comment: "tooltip"))
            .labelStyle(.iconOnly)
    }
}


private struct DiagnosticView: View {
    
    var mark: DiagnosticMark
    
    
    var body: some View {
        
        Label {
            Text(self.mark.message)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: self.symbolName)
                .foregroundStyle(self.color)
        }
        .help(self.mark.message)
        .accessibilityElement(children: .combine)
    }
    
    
    private var symbolName: String {
        
        switch self.mark.severity {
            case .error: "xmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .information: "info.circle.fill"
            case .hint: "lightbulb.fill"
        }
    }
    
    
    private var color: Color {
        
        switch self.mark.severity {
            case .error: .red
            case .warning: .orange
            case .information: .blue
            case .hint: .secondary
        }
    }
}


/// Tells that the language server isn't available, and opens its settings when clicked.
private struct LanguageServerProblemView: View {
    
    var syntaxName: String
    var status: LanguageServer.Status
    
    
    var body: some View {
        
        Button {
            NSApp.sendAction(#selector(AppDelegate.showLanguageServerSettings), to: nil, from: nil)
        } label: {
            Label {
                Text(self.title)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .help(self.tooltip)
        .accessibilityHint(self.tooltip)
    }
    
    
    private var title: String {
        
        switch self.status {
            case .notInstalled:
                String(localized: "\(self.syntaxName) server not installed", table: "Document")
            default:
                String(localized: "\(self.syntaxName) server stopped", table: "Document")
        }
    }
    
    
    private var tooltip: String {
        
        let reason = switch self.status {
            case .notInstalled(let command):
                String(localized: "Graupel checks \(self.syntaxName) files with “\(command)”, which isn’t installed.", table: "Document")
            case .failed(let reason):
                reason
            default:
                ""
        }
        
        return reason + "\n" + String(localized: "Click to open the Language Servers settings.", table: "Document")
    }
}


private struct FileSizeView: View {
    
    var size: Int64?
    
    
    var body: some View {
        
        LabeledContent(.init("File size", table: "Document"),
                       optional: self.size?.formatted(.byteCount(style: .file, spellsOutZero: false)))
        .monospacedDigit()
        .labelsVisibility(.hidden)
        .help(.init("File size", table: "Document", comment: "tooltip"))
        .fixedSize()
    }
}


private struct DocumentStatusBar: View {
    
    private var document: TextDocument
    
    @State private var lineEnding: LineEnding
    @State private var fileEncoding: FileEncoding
    @State private var encodingManager: EncodingManager = .shared
    
    
    init(document: TextDocument) {
        
        self.document = document
        self.lineEnding = document.lineEnding
        self.fileEncoding = document.fileEncoding
    }
    
    
    var body: some View {
        
        HStack(spacing: 4) {
            Divider()
            
            Picker(.init("Text Encoding", table: "Document"), selection: $fileEncoding) {
                Section(.init("Text Encoding", table: "Document")) {
                    if !self.encodingManager.fileEncodings.contains(self.fileEncoding) {
                        Text(self.fileEncoding.localizedName).tag(self.fileEncoding)
                        Divider()
                    }
                    ForEach(self.encodingManager.fileEncodings.enumerated(), id: \.offset) { _, fileEncoding in
                        if let fileEncoding {
                            Text(fileEncoding.localizedName).tag(fileEncoding)
                        } else {
                            Divider()
                        }
                    }
                }
            }
            .onChange(of: self.fileEncoding) { _, newValue in
                self.document.askChangingEncoding(to: newValue) {
                    self.fileEncoding = self.document.fileEncoding
                }
            }
            .help(.init("Text Encoding", table: "Document"))
            .labelsVisibility(.hidden)
            
            Divider()
            
            LineEndingPicker(.init("Line Endings", table: "Document"), selection: $lineEnding) { lineEnding in
                self.document.changeLineEnding(to: lineEnding)
            }
            .disabled(!self.document.isEditable)
            .help(.init("Line Endings", table: "Document"))
            .accessibilityLabel(.init("Line Endings", table: "Document"))
            .frame(width: 48)
        }
        .onChange(of: self.document.lineEnding) { _, newValue in self.lineEnding = newValue }
        .onChange(of: self.document.fileEncoding) { _, newValue in self.fileEncoding = newValue }
    }
}


private struct EditorCountView: View {
    
    var result: EditorCounter.Result
    
    @AppStorage(.showStatusBarLines) private var showsLines
    @AppStorage(.showStatusBarChars) private var showsCharacters
    @AppStorage(.showStatusBarWords) private var showsWords
    @AppStorage(.showStatusBarLocation) private var showsLocation
    @AppStorage(.showStatusBarLine) private var showsLine
    @AppStorage(.showStatusBarColumn) private var showsColumn
    
    
    var body: some View {
        
        TruncatingHStack {
            ForEach(CountType.allCases, id: \.self) { type in
                if self.shows(type: type) {
                    let valueText = self.result.formattedValue(type: type).map { Text($0).foregroundStyle(.primary) } ?? Text.none
                    Text("\(type.label): \(valueText)")
                        .accessibilityLabel("\(type.label): \(self.result.formattedValue(type: type, forAccessibility: true) ?? String(localized: "None"))")
                }
            }
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
    
    
    private func shows(type: CountType) -> Bool {
        
        switch type {
            case .characters: self.showsCharacters
            case .lines: self.showsLines
            case .words: self.showsWords
            case .location: self.showsLocation
            case .line: self.showsLine
            case .column: self.showsColumn
        }
    }
}


private struct LineEndingPicker: NSViewRepresentable {
    
    typealias NSViewType = NSPopUpButton
    
    var label: LocalizedStringResource
    @Binding var selection: LineEnding
    var onSelect: (LineEnding) -> Void
    
    
    init(_ titleResource: LocalizedStringResource, selection: Binding<LineEnding>, onSelect: @escaping (LineEnding) -> Void) {
        
        self.label = titleResource
        self._selection = selection
        self.onSelect = onSelect
    }
    
    
    func makeNSView(context: Context) -> NSPopUpButton {
        
        let label = String(localized: self.label)
        let menu = OptionalMenu(title: label)
        menu.autoenablesItems = false
        menu.items = [.sectionHeader(title: label)]
        menu.items += LineEnding.allCases.map { lineEnding in
            let item = NSMenuItem()
            item.title = lineEnding.label
            item.toolTip = lineEnding.description
            item.action = #selector(Coordinator.didSelectItem)
            item.target = context.coordinator
            item.representedObject = lineEnding
            item.isHidden = !lineEnding.isBasic
            item.keyEquivalentModifierMask = lineEnding.isBasic ? [] : [.option]
            
            return item
        }
        
        let popUpButton = NSPopUpButton()
        popUpButton.menu = menu
        popUpButton.isBordered = false
        popUpButton.controlSize = .small
        popUpButton.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        
        return popUpButton
    }
    
    
    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        
        let index = nsView.indexOfItem(withRepresentedObject: self.selection)
        nsView.selectItem(at: index)
        context.coordinator.onSelect = self.onSelect
    }
    
    
    func makeCoordinator() -> Coordinator {
        
        Coordinator(selection: $selection, onSelect: self.onSelect)
    }
    
    
    final class Coordinator: NSObject {
        
        @Binding private var selection: LineEnding
        var onSelect: (LineEnding) -> Void
        
        
        init(selection: Binding<LineEnding>, onSelect: @escaping (LineEnding) -> Void) {
            
            self._selection = selection
            self.onSelect = onSelect
        }
        
        
        @objc func didSelectItem(_ sender: NSMenuItem) {
            
            self.selection = sender.representedObject as! LineEnding
            self.onSelect(self.selection)
        }
    }
}


private extension UserDefaults {
    
    /// The info types needed to be calculated.
    var statusBarEditorInfo: EditorCounter.Types {
        
        EditorCounter.Types()
            .union(self[.showStatusBarChars] ? .characters : [])
            .union(self[.showStatusBarLines] ? .lines : [])
            .union(self[.showStatusBarWords] ? .words : [])
            .union(self[.showStatusBarLocation] ? .location : [])
            .union(self[.showStatusBarLine] ? .line : [])
            .union(self[.showStatusBarColumn] ? .column : [])
    }
}


// MARK: - Preview

#Preview {
    let document = TextDocument()
    document.isEditable = false
    document.counter.result.lines = .init(entire: 1024, selected: 64)
    
    return StatusBar(model: StatusBar.Model(document: document))
}
