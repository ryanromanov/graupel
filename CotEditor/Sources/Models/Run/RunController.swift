//
//  RunController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-11-08.
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

/// The runs of a document window.
///
/// A window has one run at a time for now: Run stops the current one before starting the next. The runs are kept in
/// a list so that a later version can keep several, each in its own tab of the Run panel.
@MainActor @Observable final class RunController {
    
    /// The runs, oldest first.
    private(set) var sessions: [RunSession] = []
    
    /// A message to show in place of output, such as why nothing could run.
    private(set) var notice: String?
    
    /// The run the Run panel shows.
    var currentSession: RunSession?  { self.sessions.last }
    
    var isRunning: Bool  { self.currentSession?.isRunning == true }
    
    /// Counts the run requests, so that only the latest of several overlapping ones starts a program.
    @ObservationIgnored private var requestCount = 0
    
    
    /// Runs a saved file, after stopping the current run.
    ///
    /// - Parameters:
    ///   - fileURL: The file to run.
    ///   - command: The command that runs it.
    func run(fileURL: URL, command: RunCommand) async {
        
        // Command-R pressed twice quickly asks twice; the newer request wins
        self.requestCount += 1
        let request = self.requestCount
        
        if let session = self.currentSession, session.isRunning {
            session.stop()
            await session.waitUntilEnded()
        }
        
        let searchPath = await ShellSearchPath.directories()
        
        guard request == self.requestCount else { return }
        
        guard let executableURL = command.executableURL(searchPath: searchPath) else {
            self.sessions.removeAll()
            self.notice = String(localized: "Graupel can’t find “\(command.name)”. Install it, or set the command to run this language in Settings > Language Servers.", table: "Run")
            return
        }
        
        let session = RunSession(fileURL: fileURL,
                                 executableURL: executableURL,
                                 arguments: command.arguments(fileURL: fileURL),
                                 commandLine: command.commandLine + " " + fileURL.lastPathComponent)
        self.notice = nil
        self.sessions.filter(\.isRunning).forEach { $0.stop() }  // never leave a run that can't be reached
        self.sessions = [session]  // one run per window for now
        session.start(searchPath: searchPath)
    }
    
    
    /// Shows a message in place of output, such as that the language has no run command.
    ///
    /// - Parameter notice: The message.
    func show(notice: String) {
        
        self.sessions.removeAll { !$0.isRunning }
        self.notice = notice
    }
    
    
    /// Stops the current run.
    func stop() {
        
        self.currentSession?.stop()
    }
    
    
    /// Stops every run, such as when the window closes.
    func stopAll() {
        
        self.sessions.forEach { $0.stop() }
    }
    
    
    /// Clears the output: a running program keeps running, a finished run is removed.
    func clear() {
        
        self.notice = nil
        
        if let session = self.currentSession, session.isRunning {
            session.clearOutput()
        } else {
            self.sessions.removeAll()
        }
    }
}
