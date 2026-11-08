//
//  RunOutputLink.swift
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

/// A place in a file that a run's output points to, such as `tour.bor:12:5` in an error message.
struct RunOutputLink: Equatable, Sendable {
    
    var fileURL: URL
    var line: Int
    var column: Int?
    
    
    private static let scheme = "graupel-run-location"
    
    /// `File "script.py", line 3`, as in Python tracebacks.
    private static let quotedFileRegex = try! NSRegularExpression(pattern: #"File "([^"\n]+)", line (\d+)"#)
    
    /// `path/file.ext:12` or `path/file.ext:12:5`, as most compilers and `boreas check` write.
    private static let fileLineRegex = try! NSRegularExpression(pattern: #"((?:~|\.{1,2})?/?(?:[\w.\-~]+/)*[\w\-]+\.\w+):(\d+)(?::(\d+))?"#)
    
    /// `line 12` or `line 12, column 5`, as Boreas writes errors in the file being run.
    private static let lineRegex = try! NSRegularExpression(pattern: #"\bline (\d+)(?:, column (\d+))?"#)
    
    
    /// The URL that the output's text view stores as the link.
    var url: URL {
        
        var components = URLComponents()
        components.scheme = Self.scheme
        components.queryItems = [
            URLQueryItem(name: "path", value: self.fileURL.path),
            URLQueryItem(name: "line", value: String(self.line)),
        ] + (self.column.map { [URLQueryItem(name: "column", value: String($0))] } ?? [])
        
        return components.url!
    }
    
    
    init(fileURL: URL, line: Int, column: Int? = nil) {
        
        self.fileURL = fileURL
        self.line = line
        self.column = column
    }
    
    
    /// Reads a link back from the URL that `url` made.
    init?(url: URL) {
        
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == Self.scheme,
            let items = components.queryItems,
            let path = items.first(where: { $0.name == "path" })?.value,
            let line = items.first(where: { $0.name == "line" })?.value.flatMap(Int.init)
        else { return nil }
        
        self.fileURL = URL(filePath: path)
        self.line = line
        self.column = items.first(where: { $0.name == "column" })?.value.flatMap(Int.init)
    }
    
    
    /// Finds the places that a line of output points to.
    ///
    /// A path counts only if the file exists, relative paths being in the folder the program ran in. In an error line
    /// without a path, `line 12` means a line of the file being run.
    ///
    /// - Parameters:
    ///   - text: One line of output.
    ///   - isError: Whether the program wrote the line to its standard error.
    ///   - directory: The folder the program ran in.
    ///   - runFileURL: The file being run.
    ///   - fileExists: Whether a file exists; for tests.
    /// - Returns: The ranges in `text` to make into links, with where each goes.
    static func links(in text: String, isError: Bool, directory: URL, runFileURL: URL,
                      fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [(range: NSRange, link: RunOutputLink)]
    {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        
        func file(_ path: String) -> URL? {
            let url = path.hasPrefix("/") ? URL(filePath: path)
                : path.hasPrefix("~") ? URL(filePath: (path as NSString).expandingTildeInPath)
                : directory.appending(path: path).standardizedFileURL
            
            return fileExists(url) ? url : nil
        }
        
        func number(_ match: NSTextCheckingResult, _ index: Int) -> Int? {
            let range = match.range(at: index)
            
            return (range.location == NSNotFound) ? nil : Int(nsText.substring(with: range))
        }
        
        var links: [(range: NSRange, link: RunOutputLink)] = []
        
        for match in self.quotedFileRegex.matches(in: text, range: fullRange) {
            guard let url = file(nsText.substring(with: match.range(at: 1))), let line = number(match, 2) else { continue }
            links.append((match.range, RunOutputLink(fileURL: url, line: line)))
        }
        
        for match in self.fileLineRegex.matches(in: text, range: fullRange)
        where !links.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 })
        {
            guard let url = file(nsText.substring(with: match.range(at: 1))), let line = number(match, 2) else { continue }
            links.append((match.range, RunOutputLink(fileURL: url, line: line, column: number(match, 3))))
        }
        
        if isError, links.isEmpty {
            for match in self.lineRegex.matches(in: text, range: fullRange) {
                guard let line = number(match, 1) else { continue }
                links.append((match.range, RunOutputLink(fileURL: runFileURL, line: line, column: number(match, 2))))
            }
        }
        
        return links.sorted { $0.range.location < $1.range.location }
    }
}
