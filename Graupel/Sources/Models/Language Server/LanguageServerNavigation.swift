//
//  LanguageServerNavigation.swift
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

/// A place in a file that a language server points to, such as where a name is declared.
struct LanguageServerLocation: Equatable, Sendable {
    
    var fileURL: URL
    var start: LanguageServerDiagnostic.Position
    var end: LanguageServerDiagnostic.Position
    
    
    /// Reads the answer to `textDocument/definition`: a Location, a LocationLink, an array of either, or `null`.
    ///
    /// - Parameter result: The `result` of the response.
    /// - Returns: The locations, in the server's order; empty if there are none.
    static func locations(result: Any?) -> [LanguageServerLocation] {
        
        let items: [Any] = switch result {
            case let array as [Any]: array
            case let item?: [item]
            case nil: []
        }
        
        return items.compactMap { item in
            guard let item = item as? [String: Any] else { return nil }
            
            // a LocationLink has `targetUri`; its `targetSelectionRange` is the name, `targetRange` the whole declaration
            let uri = (item["uri"] ?? item["targetUri"]) as? String
            let range = (item["range"] ?? item["targetSelectionRange"] ?? item["targetRange"]) as? [String: Any]
            
            guard
                let uri, let url = URL(string: uri), url.isFileURL,
                let start = Self.position(range?["start"]),
                let end = Self.position(range?["end"])
            else { return nil }
            
            return LanguageServerLocation(fileURL: url, start: start, end: end)
        }
    }
    
    
    private static func position(_ value: Any?) -> LanguageServerDiagnostic.Position? {
        
        guard
            let position = value as? [String: Any],
            let line = position["line"] as? Int,
            let character = position["character"] as? Int
        else { return nil }
        
        return LanguageServerDiagnostic.Position(line: line, character: character)
    }
}


/// What a language server says about the name under the pointer.
struct LanguageServerHover: Equatable, Sendable {
    
    /// The text to show, in Markdown unless `isMarkdown` is false.
    var text: String
    var isMarkdown: Bool
    
    /// The range of the word the text is about, in the document as it was when asked, if the server gave it.
    var range: NSRange?
    
    
    /// Reads the answer to `textDocument/hover`.
    ///
    /// - Parameters:
    ///   - result: The `result` of the response.
    ///   - string: The document's text when it was asked, to convert the range.
    /// - Returns: The hover, or `nil` if there's nothing to show.
    static func hover(result: Any?, in string: NSString) -> LanguageServerHover? {
        
        guard let result = result as? [String: Any] else { return nil }
        
        let (text, isMarkdown): (String, Bool)
        switch result["contents"] {
            case let content as [String: Any] where content["kind"] != nil:  // MarkupContent
                text = content["value"] as? String ?? ""
                isMarkdown = (content["kind"] as? String) == "markdown"
            case let contents as [Any]:  // MarkedString array
                text = contents.compactMap(Self.markdown(markedString:)).joined(separator: "\n\n")
                isMarkdown = true
            case let content?:  // one MarkedString
                text = Self.markdown(markedString: content) ?? ""
                isMarkdown = true
            case nil:
                return nil
        }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        var range: NSRange?
        if let rangeValue = result["range"] as? [String: Any],
           let start = rangeValue["start"] as? [String: Any], let end = rangeValue["end"] as? [String: Any],
           let startLine = start["line"] as? Int, let startCharacter = start["character"] as? Int,
           let endLine = end["line"] as? Int, let endCharacter = end["character"] as? Int
        {
            let converter = LanguageServerPositionConverter(string: string)
            let lower = converter.location(of: .init(line: startLine, character: startCharacter))
            let upper = converter.location(of: .init(line: endLine, character: endCharacter))
            range = NSRange(lower..<max(lower, upper))
        }
        
        return LanguageServerHover(text: trimmed, isMarkdown: isMarkdown, range: range)
    }
    
    
    /// A MarkedString as Markdown: a string is Markdown already; `{language, value}` is a code block.
    private static func markdown(markedString: Any) -> String? {
        
        switch markedString {
            case let string as String:
                string
            case let code as [String: Any]:
                (code["value"] as? String).map { "```" + (code["language"] as? String ?? "") + "\n" + $0 + "\n```" }
            default:
                nil
        }
    }
    
    
    /// The text split into prose and code blocks, for showing code in a monospaced font.
    var parts: [(text: String, isCode: Bool)] {
        
        guard self.isMarkdown else { return [(self.text, false)] }
        
        var parts: [(text: String, isCode: Bool)] = []
        var prose: [Substring] = []
        var code: [Substring]?
        
        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append((text, false)) }
            prose.removeAll()
        }
        
        for line in self.text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let lines = code {
                    parts.append((lines.joined(separator: "\n"), true))
                    code = nil
                } else {
                    flushProse()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else {
                prose.append(line)
            }
        }
        if let lines = code {  // an unclosed block
            parts.append((lines.joined(separator: "\n"), true))
        }
        flushProse()
        
        return parts
    }
}
