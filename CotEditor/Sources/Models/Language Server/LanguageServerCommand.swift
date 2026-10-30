//
//  LanguageServerCommand.swift
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
import StringUtils

/// How to launch the language server for a syntax.
///
/// An executable script `_Language Servers/<syntax name>.sh` in the application scripts directory
/// takes priority, so that users can override or add servers. The leading underscore hides the folder
/// from the Script menu. Otherwise, a bundled syntax uses its usual server, if it's installed.
struct LanguageServerCommand: Equatable, Sendable {
    
    /// The command name, which is looked up in the search path, or the absolute path of the executable.
    var name: String
    var arguments: [String] = []
    
    
    /// The servers of the bundled syntaxes, by syntax name.
    static let defaults: [String: LanguageServerCommand] = [
        "Boreas": LanguageServerCommand(name: "boreas", arguments: ["lsp"]),
    ]
    
    private static let directoryName = "_Language Servers"
    
    
    /// Returns the command to launch the server for the syntax, if any.
    ///
    /// - Parameter syntaxName: The name of the syntax.
    /// - Returns: The user's script, the default command for the syntax, or `nil`.
    static func command(syntaxName: String) -> LanguageServerCommand? {
        
        if let scriptsURL = try? URL(for: .applicationScriptsDirectory, in: .userDomainMask) {
            let url = scriptsURL.appending(components: Self.directoryName, "\(syntaxName).sh")
            
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return LanguageServerCommand(name: url.path)
            }
        }
        
        return self.defaults[syntaxName]
    }
    
    
    /// Finds the executable of the command.
    ///
    /// - Parameter searchPath: The directories to look up a command name in.
    /// - Returns: The file URL of the executable, or `nil` if it's not installed.
    func executableURL(searchPath: [String]) -> URL? {
        
        if self.name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: self.name) ? URL(filePath: self.name) : nil
        }
        
        return searchPath.lazy
            .map { URL(filePath: $0, directoryHint: .isDirectory).appending(component: self.name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}


/// The command search path of the user's login shell.
///
/// Apps opened from the Finder or the Dock don't inherit the `PATH` that users set up for their shell,
/// so a command that works in Terminal wouldn't be found. The path is read from the shell once.
enum ShellSearchPath {
    
    static let marker = "__GRAUPEL_PATH__"
    
    @MainActor private static var task: Task<[String], Never>?
    
    
    /// Returns the directories of the user's shell `PATH`, followed by common install locations.
    @MainActor static func directories() async -> [String] {
        
        if let task = self.task {
            return await task.value
        }
        
        let task = Task.detached {
            let shellPath = self.readShellPath() ?? []
            let processPath = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
            let common = [
                URL.homeDirectory.appending(path: ".local/bin").path,
                "/opt/homebrew/bin",
                "/usr/local/bin",
            ]
            
            return (shellPath + processPath + common).uniqued
        }
        self.task = task
        
        return await task.value
    }
    
    
    /// Extracts the search path from the shell output, which may contain other output from the shell's startup files.
    ///
    /// - Parameter output: The output of the shell, with the `PATH` value between two markers.
    /// - Returns: The directories, or `nil` if the output has no path.
    static func directories(shellOutput output: String) -> [String]? {
        
        let parts = output.components(separatedBy: self.marker)
        
        guard parts.count >= 3 else { return nil }
        
        let directories = parts[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .map(String.init)
        
        return directories.isEmpty ? nil : directories
    }
    
    
    /// Asks the user's login shell for its `PATH`.
    private static func readShellPath() -> [String]? {
        
        let process = Process()
        process.executableURL = URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        // interactive, so that the shell also reads the startup files where users usually set `PATH`
        process.arguments = ["-l", "-i", "-c", "echo \(self.marker); /usr/bin/printenv PATH; echo \(self.marker)"]
        
        let outputPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
        } catch {
            return nil
        }
        
        // give up on a shell whose startup files wait for something
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning {
                process.terminate()
            }
        }
        
        let data = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        
        guard let output = String(bytes: data, encoding: .utf8) else { return nil }
        
        return self.directories(shellOutput: output)
    }
}
