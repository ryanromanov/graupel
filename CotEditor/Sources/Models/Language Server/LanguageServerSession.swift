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
import OSLog

/// Keeps a language server informed about one document and marks the problems it reports.
///
/// The server for a syntax is the executable script `_Language Servers/<syntax name>.sh`
/// in the application scripts directory. The leading underscore hides the folder from the Script menu.
@MainActor final class LanguageServerSession {

    // MARK: Public Properties

    let syntaxName: String
    let fileURL: URL?


    // MARK: Private Properties

    private static let directoryName = "_Language Servers"

    private let connection: LanguageServerConnection
    private let uri: String
    private weak var textStorage: NSTextStorage?

    private var version = 0
    private var isOpen = false
    private var textObserver: (any NSObjectProtocol)?
    private var changeDebouncer: Debouncer?


    // MARK: Lifecycle

    /// Starts a session if a language server script exists for the syntax.
    ///
    /// - Parameters:
    ///   - syntaxName: The name of the document's syntax.
    ///   - fileURL: The document file URL, or `nil` for an untitled document.
    ///   - textStorage: The document contents.
    init?(syntaxName: String, fileURL: URL?, textStorage: NSTextStorage) {

        guard let scriptURL = Self.scriptURL(syntaxName: syntaxName) else { return nil }

        do {
            self.connection = try LanguageServerConnection(scriptURL: scriptURL)
        } catch {
            Logger.languageServer.error("cannot launch \(scriptURL.path, privacy: .public): \(error, privacy: .public)")
            return nil
        }

        self.syntaxName = syntaxName
        self.fileURL = fileURL
        self.uri = (fileURL ?? URL(filePath: "/Untitled-\(UUID().uuidString)")).absoluteString
        self.textStorage = textStorage

        self.connection.notificationHandler = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        self.connection.start()
        self.initialize()
    }


    // MARK: Public Methods

    /// Closes the document on the server, stops the server, and removes the marks.
    func close() {

        self.changeDebouncer?.cancel()
        self.changeDebouncer = nil
        self.textObserver = nil

        if self.isOpen {
            self.connection.notify("textDocument/didClose", params: ["textDocument": ["uri": self.uri]])
            self.isOpen = false
        }
        self.connection.close()

        self.textStorage?.apply(diagnostics: [])
    }


    // MARK: Private Methods

    /// The URL of the executable script for the syntax, if any.
    private static func scriptURL(syntaxName: String) -> URL? {

        guard let scriptsURL = try? URL(for: .applicationScriptsDirectory, in: .userDomainMask) else { return nil }

        let url = scriptsURL.appending(components: Self.directoryName, "\(syntaxName).sh")

        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }


    private func initialize() {

        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "clientInfo": ["name": Bundle.main.bundleIdentifier!],
            "rootUri": NSNull(),
            "capabilities": [
                "general": ["positionEncodings": ["utf-16"]],
                "textDocument": [
                    "synchronization": ["dynamicRegistration": false],
                    "publishDiagnostics": ["versionSupport": true],
                ],
            ],
        ]

        self.connection.request("initialize", params: params) { [weak self] _, error in
            guard let self else { return }

            if let error {
                Logger.languageServer.error("initialize failed: \(error, privacy: .public)")
                return
            }

            self.connection.notify("initialized", params: [:])
            self.didOpen()
        }
    }


    private func didOpen() {

        guard let textStorage = self.textStorage else { return }

        self.version = 1
        self.isOpen = true
        self.connection.notify("textDocument/didOpen", params: [
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


    /// Sends the whole document, as the session uses full document synchronization.
    private func didChange() {

        guard self.isOpen, let textStorage = self.textStorage else { return }

        self.version += 1
        self.connection.notify("textDocument/didChange", params: [
            "textDocument": ["uri": self.uri, "version": self.version],
            "contentChanges": [["text": textStorage.string]],
        ])
    }


    private func handleNotification(method: String, params: Any?) {

        switch method {
            case "textDocument/publishDiagnostics":
                guard
                    self.isOpen,
                    let params = params as? [String: Any],
                    params["uri"] as? String == self.uri
                else { return }

                // skip diagnostics for an older version, which positions no longer match the contents
                if let version = params["version"] as? Int, version != self.version { return }

                let diagnostics = (params["diagnostics"] as? [[String: Any]] ?? [])
                    .compactMap(LanguageServerDiagnostic.init(json:))
                self.textStorage?.apply(diagnostics: diagnostics)

            default:
                Logger.languageServer.debug("ignored notification: \(method, privacy: .public)")
        }
    }
}
