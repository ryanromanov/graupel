//
//  LanguageServerConnection.swift
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

import Foundation
import OSLog

extension Logger {
    
    static let languageServer = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "languageServer")
}


/// A JSON-RPC connection to a language server running as a child process.
@MainActor final class LanguageServerConnection {
    
    typealias Message = [String: Any]
    typealias ResponseHandler = (_ result: Any?, _ error: Message?) -> Void
    
    
    // MARK: Public Properties
    
    /// Called for each notification sent by the server.
    var notificationHandler: ((_ method: String, _ params: Any?) -> Void)?
    
    /// Called with the reason when the server exits before the connection closes.
    var terminationHandler: ((_ reason: String) -> Void)?
    
    
    // MARK: Private Properties
    
    /// How long to wait for the server to answer `shutdown` before closing its input anyway.
    private static let shutdownTimeout: Duration = .seconds(2)
    
    /// How long to wait for the server to exit after its input closed before terminating it.
    private static let exitTimeout: Duration = .seconds(2)
    
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    
    /// The queue to write to the server, so that a slow reader doesn't block the main thread.
    private let writeQueue = DispatchQueue(label: "com.coteditor.CotEditor.languageServer.write")
    
    private var framer = LanguageServerMessageFramer()
    private var nextID = 1
    private var responseHandlers: [Int: ResponseHandler] = [:]
    private var isClosed = false
    
    /// The last line the server wrote to its standard error, which usually explains why it exited.
    private var lastErrorLine: String?
    
    
    // MARK: Lifecycle
    
    /// Creates a connection with an executable that runs the language server on its standard input and output.
    ///
    /// - Parameters:
    ///   - executableURL: The file URL of the server executable or script.
    ///   - arguments: The command-line arguments.
    ///   - searchPath: The directories for the server's `PATH`, so that it finds the same tools as in Terminal.
    init(executableURL: URL, arguments: [String] = [], searchPath: [String] = []) {
        
        self.process.executableURL = executableURL
        self.process.arguments = arguments
        if !searchPath.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = searchPath.joined(separator: ":")
            self.process.environment = environment
        }
        self.process.standardInput = self.inputPipe
        self.process.standardOutput = self.outputPipe
        self.process.standardError = self.errorPipe
        self.process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                await self?.didTerminate(status: status)
            }
        }
        
        // fail writes with EPIPE instead of terminating the app when the server has quit
        _ = fcntl(self.inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    
    
    // MARK: Public Methods
    
    /// Launches the server and starts reading its output.
    ///
    /// - Throws: An error if the server cannot be launched.
    func start() throws {
        
        try self.process.run()
        
        let output = self.outputPipe.readingStream
        let errors = self.errorPipe.readingStream
        
        Task { [weak self] in
            do {
                for try await data in output {
                    self?.receive(data)
                }
            } catch {
                Logger.languageServer.error("failed reading from server: \(error, privacy: .public)")
            }
        }
        
        Task { [weak self] in
            do {
                for try await data in errors {
                    let output = String(bytes: data, encoding: .utf8) ?? ""
                    Logger.languageServer.debug("server: \(output, privacy: .public)")
                    if let line = output.split(whereSeparator: \.isNewline).last(where: { !$0.allSatisfy(\.isWhitespace) }) {
                        self?.lastErrorLine = String(line)
                    }
                }
            } catch {
                Logger.languageServer.error("failed reading server errors: \(error, privacy: .public)")
            }
        }
    }
    
    
    /// Sends a request and calls the handler with the response.
    ///
    /// - Parameters:
    ///   - method: The method name.
    ///   - params: The parameters, which must be a JSON object or array.
    ///   - handler: The handler called on the main actor with the result or the error object.
    func request(_ method: String, params: Any? = nil, handler: @escaping ResponseHandler = { _, _ in }) {
        
        let id = self.nextID
        self.nextID += 1
        self.responseHandlers[id] = handler
        
        var message: Message = ["id": id, "method": method]
        message["params"] = params
        self.send(message)
    }
    
    
    /// Sends a notification.
    ///
    /// - Parameters:
    ///   - method: The method name.
    ///   - params: The parameters, which must be a JSON object or array.
    func notify(_ method: String, params: Any? = nil) {
        
        var message: Message = ["method": method]
        message["params"] = params
        self.send(message)
    }
    
    
    /// Asks the server to shut down and exit, then closes its standard input.
    ///
    /// The connection keeps itself alive until then, even if its owner releases it.
    func close() {
        
        guard !self.isClosed else { return }
        
        self.request("shutdown") { [self] _, _ in
            self.notify("exit")
            self.closeInput()
        }
        
        // close anyway if the server doesn't answer
        Task { [self] in
            try? await Task.sleep(for: Self.shutdownTimeout)
            self.closeInput()
        }
    }
    
    
    // MARK: Private Methods
    
    /// Closes the server's standard input, which makes a well-behaved server exit, and terminates it if it doesn't.
    private func closeInput() {
        
        guard !self.isClosed else { return }
        
        self.isClosed = true
        self.responseHandlers.removeAll()
        
        let handle = self.inputPipe.fileHandleForWriting
        self.writeQueue.async {
            try? handle.close()
        }
        
        Task { [process] in
            try? await Task.sleep(for: Self.exitTimeout)
            if process.isRunning {
                Logger.languageServer.error("server didn't exit; terminating it")
                process.terminate()
            }
        }
    }
    
    
    /// Stops sending to the server after its process exited, and reports an unexpected exit.
    private func didTerminate(status: Int32) async {
        
        guard !self.isClosed else { return }
        
        Logger.languageServer.error("server exited unexpectedly with status \(status, privacy: .public)")
        self.isClosed = true
        self.responseHandlers.removeAll()
        
        // let the last error output arrive
        try? await Task.sleep(for: .milliseconds(100))
        
        let reason = self.lastErrorLine ?? String(localized: "The server stopped with status \(status).", table: "LanguageServer")
        self.terminationHandler?(reason)
    }
    
    
    /// Writes a framed message to the server.
    private func send(_ message: Message) {
        
        guard !self.isClosed else { return }
        
        var message = message
        message["jsonrpc"] = "2.0"
        
        let data: Data
        do {
            data = LanguageServerMessageFramer.frame(try JSONSerialization.data(withJSONObject: message))
        } catch {
            return assertionFailure(error.localizedDescription)
        }
        
        let handle = self.inputPipe.fileHandleForWriting
        self.writeQueue.async {
            do {
                try handle.write(contentsOf: data)
            } catch {
                Logger.languageServer.error("failed writing to server: \(error, privacy: .public)")
            }
        }
    }
    
    
    /// Handles every complete message in the received output.
    private func receive(_ data: Data) {
        
        let bodies: [Data]
        do {
            bodies = try self.framer.append(data)
        } catch {
            Logger.languageServer.error("server sent a header without Content-Length")
            return
        }
        
        for body in bodies {
            guard let message = (try? JSONSerialization.jsonObject(with: body)) as? Message else {
                Logger.languageServer.error("server sent invalid JSON")
                continue
            }
            self.handle(message)
        }
    }
    
    
    /// Dispatches a message from the server.
    private func handle(_ message: Message) {
        
        let method = message["method"] as? String
        
        switch (message["id"], method) {
            case let (id as Int, nil):
                // response to a request
                self.responseHandlers.removeValue(forKey: id)?(message["result"], message["error"] as? Message)
            
            case let (id?, method?):
                // request from the server, which this client doesn't support
                Logger.languageServer.debug("unsupported server request: \(method, privacy: .public)")
                self.send(["id": id, "error": ["code": -32601, "message": "Method not found"]])
            
            case let (nil, method?):
                self.notificationHandler?(method, message["params"])
            
            default:
                Logger.languageServer.error("server sent an unknown message")
        }
    }
}
