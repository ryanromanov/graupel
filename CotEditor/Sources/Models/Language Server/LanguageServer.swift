//
//  LanguageServer.swift
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

import Foundation
import OSLog

/// A language server shared by all open documents of a syntax.
///
/// The server for a syntax is the executable script `_Language Servers/<syntax name>.sh`
/// in the application scripts directory. The leading underscore hides the folder from the Script menu.
/// The server launches when the first document of the syntax opens and shuts down when the last one closes.
@MainActor final class LanguageServer {

    // MARK: Public Properties

    let syntaxName: String


    // MARK: Private Properties

    private static let directoryName = "_Language Servers"

    /// The running servers by syntax name.
    private static var servers: [String: LanguageServer] = [:]

    private let connection: LanguageServerConnection
    private var isInitialized = false

    /// The documents open on the server by URI.
    private var sessions: [String: LanguageServerSession] = [:]


    // MARK: Lifecycle

    private init(syntaxName: String, connection: LanguageServerConnection) {

        self.syntaxName = syntaxName
        self.connection = connection
    }


    /// Returns the running server for the syntax, launching it if a server script exists.
    ///
    /// - Parameter syntaxName: The name of the syntax.
    /// - Returns: The server, or `nil` if the syntax has no server or it cannot be launched.
    static func server(syntaxName: String) -> LanguageServer? {

        if let server = self.servers[syntaxName] { return server }

        guard let scriptURL = self.scriptURL(syntaxName: syntaxName) else { return nil }

        let connection = LanguageServerConnection(executableURL: scriptURL)
        do {
            try connection.start()
        } catch {
            Logger.languageServer.error("cannot launch \(scriptURL.path, privacy: .public): \(error, privacy: .public)")
            return nil
        }

        // output is handled on the main actor, so no message arrives before the handlers are set
        let server = LanguageServer(syntaxName: syntaxName, connection: connection)
        connection.notificationHandler = { [weak server] method, params in
            server?.handleNotification(method: method, params: params)
        }
        connection.terminationHandler = { [weak server] in
            server?.didTerminate()
        }
        self.servers[syntaxName] = server
        server.initialize()

        return server
    }


    // MARK: Public Methods

    /// Adds a document to the server, which opens it as soon as the server is ready.
    ///
    /// - Parameter session: The session of the document.
    func open(_ session: LanguageServerSession) {

        self.sessions[session.uri] = session

        if self.isInitialized {
            session.didOpen()
        }
    }


    /// Removes a document from the server, and shuts the server down if it was the last one.
    ///
    /// - Parameter session: The session of the document.
    func close(_ session: LanguageServerSession) {

        guard self.sessions.removeValue(forKey: session.uri) != nil, self.sessions.isEmpty else { return }

        self.unregister()
        self.connection.close()
    }


    /// Sends a notification to the server.
    ///
    /// - Parameters:
    ///   - method: The method name.
    ///   - params: The parameters, which must be a JSON object or array.
    func notify(_ method: String, params: Any? = nil) {

        self.connection.notify(method, params: params)
    }


    // MARK: Private Methods

    /// The URL of the executable script for the syntax, if any.
    private static func scriptURL(syntaxName: String) -> URL? {

        guard let scriptsURL = try? URL(for: .applicationScriptsDirectory, in: .userDomainMask) else { return nil }

        let url = scriptsURL.appending(components: Self.directoryName, "\(syntaxName).sh")

        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }


    /// Removes the server from the running servers, so that the next document launches a new one.
    private func unregister() {

        if Self.servers[self.syntaxName] === self {
            Self.servers[self.syntaxName] = nil
        }
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
            self.isInitialized = true

            for session in self.sessions.values {
                session.didOpen()
            }
        }
    }


    /// Forgets the server after its process exited.
    private func didTerminate() {

        if !self.sessions.isEmpty {
            Logger.languageServer.error("\(self.syntaxName, privacy: .public) server exited while documents were open")
        }
        self.unregister()
    }


    private func handleNotification(method: String, params: Any?) {

        switch method {
            case "textDocument/publishDiagnostics":
                guard
                    let params = params as? [String: Any],
                    let uri = params["uri"] as? String
                else { return }

                self.sessions[uri]?.didPublishDiagnostics(params)

            default:
                Logger.languageServer.debug("ignored notification: \(method, privacy: .public)")
        }
    }
}
