//
//  LanguageServerSession.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-10-27.
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

import AppKit

/// Keeps a language server informed about one document and marks the problems it reports.
@MainActor final class LanguageServerSession {
    
    // MARK: Public Properties
    
    let syntaxName: String
    let fileURL: URL?
    let uri: String
    
    /// Called after the marks in the text are updated.
    var didUpdateDiagnostics: (() -> Void)?
    
    /// Called after the status of the server changed.
    var didUpdateServerStatus: (() -> Void)?
    
    /// The command that launched the server.
    var command: LanguageServerCommand { self.server.command }
    
    var serverStatus: LanguageServer.Status { self.server.status }
    
    /// The characters after which the server suggests completions, or `nil` if it can't complete.
    var completionTriggerCharacters: [String]? { self.isOpen ? self.server.completionTriggerCharacters : nil }
    
    
    // MARK: Private Properties
    
    private let server: LanguageServer
    private weak var textStorage: NSTextStorage?
    
    private var version = 0
    private var isOpen = false
    private var textObserver: (any NSObjectProtocol)?
    private var changeDebouncer: Debouncer?
    
    
    // MARK: Lifecycle
    
    /// Starts a session if a language server exists for the syntax.
    ///
    /// - Parameters:
    ///   - syntaxName: The name of the document's syntax.
    ///   - fileURL: The document file URL, or `nil` for an untitled document.
    ///   - textStorage: The document contents.
    init?(syntaxName: String, fileURL: URL?, textStorage: NSTextStorage) {
        
        guard let server = LanguageServer.server(syntaxName: syntaxName) else { return nil }
        
        self.server = server
        self.syntaxName = syntaxName
        self.fileURL = fileURL
        self.uri = (fileURL ?? URL(filePath: "/Untitled-\(UUID().uuidString)")).absoluteString
        self.textStorage = textStorage
        
        server.open(self)
    }
    
    
    // MARK: Public Methods
    
    /// Closes the document on the server and removes the marks.
    func close() {
        
        self.changeDebouncer?.cancel()
        self.changeDebouncer = nil
        self.textObserver = nil
        
        if self.isOpen {
            self.server.notify("textDocument/didClose", params: ["textDocument": ["uri": self.uri]])
            self.isOpen = false
        }
        self.server.close(self)
        
        self.textStorage?.apply(diagnostics: [])
        self.didUpdateDiagnostics?()
    }
    
    
    /// Opens the document on the server and starts sending its changes.
    ///
    /// Called by the server once it's ready.
    func didOpen() {
        
        guard !self.isOpen, let textStorage = self.textStorage else { return }
        
        self.version = 1
        self.isOpen = true
        self.server.notify("textDocument/didOpen", params: [
            "textDocument": [
                "uri": self.uri,
                "languageId": self.syntaxName.lowercased(),
                "version": self.version,
                "text": textStorage.string,
            ],
        ])
        
        self.changeDebouncer = Debouncer(delay: .milliseconds(300)) { [weak self] in
            self?.didChange()
        }
        self.textObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: textStorage, queue: .main) { [weak self] notification in
            guard (notification.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) == true else { return }
            
            MainActor.assumeIsolated {
                self?.changeDebouncer?.schedule()
            }
        }
    }
    
    
    /// Asks the server for the words that complete the word at a location.
    ///
    /// - Parameters:
    ///   - location: The character location of the cursor.
    ///   - handler: The handler called with the words, which isn't called if the server doesn't answer.
    /// - Returns: Whether the server was asked; it isn't if it can't complete.
    func requestCompletions(at location: Int, handler: @escaping ([String]) -> Void) -> Bool {
        
        guard self.completionTriggerCharacters != nil, let textStorage = self.textStorage else { return false }
        
        // let the server complete the current text rather than the text before the pending change
        self.changeDebouncer?.fire()
        
        let position = LanguageServerPositionConverter(string: textStorage.string as NSString).position(at: location)
        self.server.request("textDocument/completion", params: [
            "textDocument": ["uri": self.uri],
            "position": ["line": position.line, "character": position.character],
        ]) { result, error in
            guard error == nil else { return }
            
            handler(LanguageServerCompletionItem.words(result: result))
        }
        
        return true
    }
    
    
    /// Called by the server when its status changed.
    func serverStatusDidChange() {
        
        self.didUpdateServerStatus?()
    }
    
    
    /// Marks the problems the server reported for the document.
    ///
    /// - Parameter params: The parameters of the `textDocument/publishDiagnostics` notification.
    func didPublishDiagnostics(_ params: [String: Any]) {
        
        guard self.isOpen else { return }
        
        // skip diagnostics for an older version, which positions no longer match the contents
        if let version = params["version"] as? Int, version != self.version { return }
        
        let diagnostics = (params["diagnostics"] as? [[String: Any]] ?? [])
            .compactMap(LanguageServerDiagnostic.init(json:))
        self.textStorage?.apply(diagnostics: diagnostics)
        self.didUpdateDiagnostics?()
    }
    
    
    // MARK: Private Methods
    
    /// Sends the whole document, as the session uses full document synchronization.
    private func didChange() {
        
        guard self.isOpen, let textStorage = self.textStorage else { return }
        
        self.version += 1
        self.server.notify("textDocument/didChange", params: [
            "textDocument": ["uri": self.uri, "version": self.version],
            "contentChanges": [["text": textStorage.string]],
        ])
    }
}
