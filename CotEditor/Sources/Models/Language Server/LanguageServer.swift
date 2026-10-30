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
/// The server launches when the first document of the syntax opens and shuts down when the last one closes.
/// See `LanguageServerCommand` for how the server is found.
@MainActor final class LanguageServer {
    
    // MARK: Public Properties
    
    let syntaxName: String
    
    
    // MARK: Private Properties
    
    /// The running servers by syntax name.
    private static var servers: [String: LanguageServer] = [:]
    
    /// The connection, which is set once the server is found and launched.
    private var connection: LanguageServerConnection?
    private var isInitialized = false
    private var isShutDown = false
    
    /// The documents open on the server by URI.
    private var sessions: [String: LanguageServerSession] = [:]
    
    
    // MARK: Lifecycle
    
    private init(syntaxName: String) {
        
        self.syntaxName = syntaxName
    }
    
    
    /// Returns the running server for the syntax, launching it if the syntax has a server.
    ///
    /// The server is found and launched asynchronously; documents open on it once it's ready.
    ///
    /// - Parameter syntaxName: The name of the syntax.
    /// - Returns: The server, or `nil` if the syntax has no server.
    static func server(syntaxName: String) -> LanguageServer? {
        
        if let server = self.servers[syntaxName] { return server }
        
        guard let command = LanguageServerCommand.command(syntaxName: syntaxName) else { return nil }
        
        let server = LanguageServer(syntaxName: syntaxName)
        self.servers[syntaxName] = server
        
        Task {
            await server.launch(command)
        }
        
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
        
        self.isShutDown = true
        self.unregister()
        self.connection?.close()
    }
    
    
    /// Sends a notification to the server.
    ///
    /// - Parameters:
    ///   - method: The method name.
    ///   - params: The parameters, which must be a JSON object or array.
    func notify(_ method: String, params: Any? = nil) {
        
        self.connection?.notify(method, params: params)
    }
    
    
    // MARK: Private Methods
    
    /// Finds the server executable and launches it.
    private func launch(_ command: LanguageServerCommand) async {
        
        let searchPath = await ShellSearchPath.directories()
        
        guard !self.isShutDown else { return }
        
        guard let executableURL = command.executableURL(searchPath: searchPath) else {
            Logger.languageServer.info("no \(self.syntaxName, privacy: .public) server: \(command.name, privacy: .public) is not installed")
            return self.unregister()
        }
        
        let connection = LanguageServerConnection(executableURL: executableURL, arguments: command.arguments, searchPath: searchPath)
        do {
            try connection.start()
        } catch {
            Logger.languageServer.error("cannot launch \(executableURL.path, privacy: .public): \(error, privacy: .public)")
            return self.unregister()
        }
        
        // output is handled on the main actor, so no message arrives before the handlers are set
        connection.notificationHandler = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        connection.terminationHandler = { [weak self] in
            self?.didTerminate()
        }
        self.connection = connection
        self.initialize()
    }
    
    
    /// Removes the server from the running servers, so that the next document launches a new one.
    private func unregister() {
        
        if Self.servers[self.syntaxName] === self {
            Self.servers[self.syntaxName] = nil
        }
    }
    
    
    private func initialize() {
        
        guard let connection = self.connection else { return }
        
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
        
        connection.request("initialize", params: params) { [weak self] _, error in
            guard let self else { return }
            
            if let error {
                Logger.languageServer.error("initialize failed: \(error, privacy: .public)")
                return
            }
            
            connection.notify("initialized", params: [:])
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
