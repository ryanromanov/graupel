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
import Observation
import OSLog

/// A language server shared by all open documents of a syntax.
///
/// The server launches when the first document of the syntax opens and shuts down when the last one closes.
/// See `LanguageServerCommand` for how the server is found.
@MainActor final class LanguageServer {
    
    enum Status: Equatable, Sendable {
        
        /// The server is being found and started.
        case launching
        
        /// The server is running from the executable.
        case running(URL)
        
        /// The command of the server isn't installed.
        case notInstalled(command: String)
        
        /// The server couldn't start or stopped unexpectedly.
        case failed(reason: String)
        
        
        /// Whether the server isn't available because of a problem to tell users about.
        var isProblem: Bool {
            
            switch self {
                case .notInstalled, .failed: true
                case .launching, .running: false
            }
        }
    }
    
    
    // MARK: Public Properties
    
    let syntaxName: String
    let command: LanguageServerCommand
    
    /// The characters after which the server suggests completions, or `nil` if it can't complete.
    private(set) var completionTriggerCharacters: [String]?
    
    /// Whether the server can format a whole document (`textDocument/formatting`).
    private(set) var supportsFormatting = false
    
    /// Whether the server finds where a name is declared (`textDocument/definition`).
    private(set) var supportsDefinition = false
    
    /// Whether the server describes the name under the pointer (`textDocument/hover`).
    private(set) var supportsHover = false
    
    private(set) var status: Status = .launching {
        
        didSet {
            guard self.status != oldValue else { return }
            
            if self.isRegistered {
                LanguageServerStatusStore.shared.statuses[self.syntaxName] = self.status
            }
            for session in self.sessions.values {
                session.serverStatusDidChange()
            }
        }
    }
    
    
    // MARK: Private Properties
    
    /// The servers in use by syntax name.
    private static var servers: [String: LanguageServer] = [:]
    
    /// The connection, which is set once the server is found and launched.
    private var connection: LanguageServerConnection?
    private var isInitialized = false
    private var isShutDown = false
    
    /// The documents open on the server by URI.
    private var sessions: [String: LanguageServerSession] = [:]
    
    
    // MARK: Lifecycle
    
    private init(syntaxName: String, command: LanguageServerCommand) {
        
        self.syntaxName = syntaxName
        self.command = command
    }
    
    
    /// Returns the server in use for the syntax, launching one if the syntax has a server.
    ///
    /// The server is found and launched asynchronously; documents open on it once it's ready.
    /// A server that failed stays in use, so that its documents can show why, until it's restarted.
    ///
    /// - Parameter syntaxName: The name of the syntax.
    /// - Returns: The server, or `nil` if the syntax has no server.
    static func server(syntaxName: String) -> LanguageServer? {
        
        if let server = self.servers[syntaxName] { return server }
        
        guard let command = LanguageServerCommand.command(syntaxName: syntaxName) else { return nil }
        
        let server = LanguageServer(syntaxName: syntaxName, command: command)
        self.servers[syntaxName] = server
        LanguageServerStatusStore.shared.statuses[syntaxName] = server.status
        
        Task {
            await server.launch()
        }
        
        return server
    }
    
    
    /// Stops using the current server for the syntax, so that the next document launches a new one.
    ///
    /// The old server shuts down when its documents close their sessions.
    ///
    /// - Parameter syntaxName: The name of the syntax.
    static func discardServer(syntaxName: String) {
        
        self.servers[syntaxName]?.unregister()
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
    
    
    /// Sends a request to the server.
    ///
    /// The handler isn't called if the server stops before answering.
    ///
    /// - Parameters:
    ///   - method: The method name.
    ///   - params: The parameters, which must be a JSON object or array.
    ///   - handler: The handler called with the result or the error object.
    func request(_ method: String, params: Any? = nil, handler: @escaping LanguageServerConnection.ResponseHandler) {
        
        self.connection?.request(method, params: params, handler: handler)
    }
    
    
    // MARK: Private Methods
    
    private var isRegistered: Bool {
        
        Self.servers[self.syntaxName] === self
    }
    
    
    /// Removes the server from the servers in use.
    private func unregister() {
        
        guard self.isRegistered else { return }
        
        Self.servers[self.syntaxName] = nil
        LanguageServerStatusStore.shared.statuses[self.syntaxName] = nil
    }
    
    
    /// Finds the server executable and launches it.
    private func launch() async {
        
        let searchPath = await ShellSearchPath.directories()
        
        guard !self.isShutDown else { return }
        
        guard let executableURL = self.command.executableURL(searchPath: searchPath) else {
            Logger.languageServer.info("no \(self.syntaxName, privacy: .public) server: \(self.command.name, privacy: .public) is not installed")
            self.status = .notInstalled(command: self.command.name)
            return
        }
        
        let connection = LanguageServerConnection(executableURL: executableURL, arguments: self.command.arguments, searchPath: searchPath)
        do {
            try connection.start()
        } catch {
            Logger.languageServer.error("cannot launch \(executableURL.path, privacy: .public): \(error, privacy: .public)")
            self.status = .failed(reason: error.localizedDescription)
            return
        }
        
        // output is handled on the main actor, so no message arrives before the handlers are set
        connection.notificationHandler = { [weak self] method, params in
            self?.handleNotification(method: method, params: params)
        }
        connection.terminationHandler = { [weak self] reason in
            self?.status = .failed(reason: reason)
        }
        self.connection = connection
        self.initialize(executableURL: executableURL)
    }
    
    
    private func initialize(executableURL: URL) {
        
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
                    "completion": ["completionItem": ["snippetSupport": false]],
                    "formatting": ["dynamicRegistration": false],
                ],
            ],
        ]
        
        connection.request("initialize", params: params) { [weak self] result, error in
            guard let self else { return }
            
            if let error {
                Logger.languageServer.error("initialize failed: \(error, privacy: .public)")
                self.status = .failed(reason: error["message"] as? String ?? "The server didn’t start.")
                return
            }
            
            let capabilities = (result as? [String: Any])?["capabilities"] as? [String: Any]
            if let completionProvider = capabilities?["completionProvider"] as? [String: Any] {
                self.completionTriggerCharacters = completionProvider["triggerCharacters"] as? [String] ?? []
            }
            // -> `documentFormattingProvider` is either `true` or an options object.
            self.supportsFormatting = Self.isSupported(capabilities?["documentFormattingProvider"])
            self.supportsDefinition = Self.isSupported(capabilities?["definitionProvider"])
            self.supportsHover = Self.isSupported(capabilities?["hoverProvider"])
            
            connection.notify("initialized", params: [:])
            self.isInitialized = true
            self.status = .running(executableURL)
            
            for session in self.sessions.values {
                session.didOpen()
            }
        }
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


/// The status of the language server in use for each syntax, for showing in the settings.
@MainActor @Observable final class LanguageServerStatusStore {
    
    static let shared = LanguageServerStatusStore()
    
    /// The statuses by syntax name. A syntax without a server in use has none.
    fileprivate(set) var statuses: [String: LanguageServer.Status] = [:]
    
    
    private init() { }
}


extension LanguageServer {
    
    /// Whether a capability in the server's `initialize` result is on: it's either `true` or an options object.
    nonisolated static func isSupported(_ capability: Any?) -> Bool {
        
        switch capability {
            case let isSupported as Bool: isSupported
            case is [String: Any]: true
            default: false
        }
    }
}
