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


/// A JSON-RPC connection to a language server launched from a user script.
///
/// The server runs as a user Unix task, the same way as the scripts in the Script menu,
/// so that it lives outside of the app sandbox.
@MainActor final class LanguageServerConnection {

    typealias Message = [String: Any]
    typealias ResponseHandler = (_ result: Any?, _ error: Message?) -> Void


    // MARK: Public Properties

    /// Called for each notification sent by the server.
    var notificationHandler: ((_ method: String, _ params: Any?) -> Void)?


    // MARK: Private Properties

    /// How long to wait for the server to answer `shutdown` before closing its input anyway.
    private static let shutdownTimeout: Duration = .seconds(2)

    private let task: NSUserUnixTask
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()

    /// The queue to write to the server, so that a slow reader doesn't block the main thread.
    private let writeQueue = DispatchQueue(label: "com.coteditor.CotEditor.languageServer.write")

    private var framer = LanguageServerMessageFramer()
    private var nextID = 1
    private var responseHandlers: [Int: ResponseHandler] = [:]
    private var isClosed = false


    // MARK: Lifecycle

    /// Creates a connection with a script that runs the language server on its standard input and output.
    ///
    /// - Parameter scriptURL: The script file URL in the application scripts directory.
    init(scriptURL: URL) throws {

        self.task = try NSUserUnixTask(url: scriptURL)
        self.task.standardInput = self.inputPipe.fileHandleForReading
        self.task.standardOutput = self.outputPipe.fileHandleForWriting
        self.task.standardError = self.errorPipe.fileHandleForWriting

        // fail writes with EPIPE instead of terminating the app when the server has quit
        _ = fcntl(self.inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }


    // MARK: Public Methods

    /// Launches the server and starts reading its output.
    func start() {

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

        Task {
            for try await data in errors {
                Logger.languageServer.debug("server: \(String(bytes: data, encoding: .utf8) ?? "", privacy: .public)")
            }
        }

        Task { [task] in
            do {
                try await task.execute(withArguments: [])
            } catch {
                Logger.languageServer.error("server failed: \(error, privacy: .public)")
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

    /// Closes the server's standard input, which makes a well-behaved server exit.
    private func closeInput() {

        guard !self.isClosed else { return }

        self.isClosed = true
        self.responseHandlers.removeAll()

        let handle = self.inputPipe.fileHandleForWriting
        self.writeQueue.async {
            try? handle.close()
        }
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
