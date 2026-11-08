//
//  RunCommand.swift
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
import Defaults

/// How to run a document of a syntax: the program that runs the saved file, such as `boreas` for Boreas.
///
/// The command in the settings takes priority, then an executable script `_Run/<syntax name>.sh` in the application
/// scripts directory, and then the command that a bundled syntax uses by default, the same order as for language servers.
/// The file is passed as the last argument.
struct RunCommand: Equatable, Sendable {
    
    enum Source: Equatable, Sendable {
        
        case settings
        case script
        case builtIn
    }
    
    
    /// The command name, which is looked up in the search path, or the absolute path of the executable.
    var name: String
    
    /// The arguments before the file.
    var arguments: [String] = []
    var source: Source = .builtIn
    
    /// The command as users would type it, without the file.
    var commandLine: String
    
    
    /// The run commands of the bundled syntaxes, by syntax name.
    static let defaults: [String: RunCommand] = [
        "Boreas": RunCommand(name: "boreas"),
    ]
    
    static let directoryName = "_Run"
    
    
    /// Creates a command that runs an executable.
    ///
    /// - Parameters:
    ///   - name: The command name or the absolute path of the executable.
    ///   - arguments: The arguments before the file.
    ///   - source: Where the command comes from.
    init(name: String, arguments: [String] = [], source: Source = .builtIn) {
        
        self.name = name
        self.arguments = arguments
        self.source = source
        self.commandLine = ([name] + arguments).joined(separator: " ")
    }
    
    
    /// Creates a command that the shell runs, so that it can contain quotes, `~`, and paths with spaces.
    ///
    /// - Parameter commandLine: The command line that the user entered, without the file.
    init?(commandLine: String) {
        
        let commandLine = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !commandLine.isEmpty else { return nil }
        
        // `exec` replaces the shell with the program, so that Stop reaches the program itself;
        // the file arrives as `$1`, which keeps a path with spaces in one piece
        self.name = "/bin/sh"
        self.arguments = ["-c", "exec \(commandLine) \"$1\"", "sh"]
        self.source = .settings
        self.commandLine = commandLine
    }
    
    
    /// Returns the command to run a document of the syntax, if any.
    ///
    /// - Parameter syntaxName: The name of the syntax.
    /// - Returns: The command, or `nil` if the syntax has none.
    static func command(syntaxName: String) -> RunCommand? {
        
        self.command(syntaxName: syntaxName,
                     settings: UserDefaults.standard[.runCommands],
                     scriptsDirectoryURL: try? URL(for: .applicationScriptsDirectory, in: .userDomainMask))
    }
    
    
    /// Returns the command to run a document of the syntax, if any.
    ///
    /// - Parameters:
    ///   - syntaxName: The name of the syntax.
    ///   - settings: The command lines in the settings, by syntax name.
    ///   - scriptsDirectoryURL: The application scripts directory.
    /// - Returns: The command, or `nil` if the syntax has none.
    static func command(syntaxName: String, settings: [String: String], scriptsDirectoryURL: URL?) -> RunCommand? {
        
        if let commandLine = settings[syntaxName], let command = RunCommand(commandLine: commandLine) {
            return command
        }
        
        return self.defaultCommand(syntaxName: syntaxName, scriptsDirectoryURL: scriptsDirectoryURL)
    }
    
    
    /// Returns the command used when the settings have none for the syntax: the user's script or the built-in command.
    ///
    /// - Parameters:
    ///   - syntaxName: The name of the syntax.
    ///   - scriptsDirectoryURL: The application scripts directory.
    /// - Returns: The command, or `nil` if the syntax has none by default.
    static func defaultCommand(syntaxName: String, scriptsDirectoryURL: URL?) -> RunCommand? {
        
        if let url = scriptsDirectoryURL?.appending(components: Self.directoryName, "\(syntaxName).sh"),
           FileManager.default.isExecutableFile(atPath: url.path)
        {
            return RunCommand(name: url.path, source: .script)
        }
        
        return self.defaults[syntaxName]
    }
    
    
    /// The arguments to run the file.
    ///
    /// - Parameter fileURL: The file to run.
    /// - Returns: The command's arguments followed by the file's path.
    func arguments(fileURL: URL) -> [String] {
        
        self.arguments + [fileURL.path]
    }
    
    
    /// Finds the executable of the command.
    ///
    /// - Parameter searchPath: The directories to look up a command name in.
    /// - Returns: The file URL of the executable, or `nil` if it's not installed.
    func executableURL(searchPath: [String]) -> URL? {
        
        LanguageServerCommand(name: self.name).executableURL(searchPath: searchPath)
    }
}
