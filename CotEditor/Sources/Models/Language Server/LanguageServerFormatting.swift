//
//  LanguageServerFormatting.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-11-06.
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

/// A change a language server asks for when formatting a document (`TextEdit`).
struct LanguageServerTextEdit: Equatable, Sendable {
    
    /// The range to replace, in UTF-16 code units of the document.
    var range: NSRange
    
    /// The text that replaces the range.
    var newText: String
}


extension LanguageServerTextEdit {
    
    /// Reads the result of `textDocument/formatting`.
    ///
    /// The edits all refer to the document before any of them is applied, so they're returned sorted by location,
    /// ready to be replaced together.
    ///
    /// - Parameters:
    ///   - result: The result: an array of `TextEdit`, or `null` for no change.
    ///   - string: The document the server formatted.
    /// - Returns: The edits, or `nil` if the result isn't valid, such as when edits overlap.
    static func edits(result: Any?, in string: NSString) -> [Self]? {
        
        if result == nil || result is NSNull { return [] }
        guard let objects = result as? [[String: Any]] else { return nil }
        
        let converter = LanguageServerPositionConverter(string: string)
        var edits: [Self] = []
        for object in objects {
            guard
                let range = object["range"] as? [String: Any],
                let start = Self.position(range["start"]),
                let end = Self.position(range["end"]),
                let newText = object["newText"] as? String
            else { return nil }
            
            let lower = converter.location(of: start)
            let upper = converter.location(of: end)
            guard lower <= upper else { return nil }
            
            edits.append(Self(range: NSRange(lower..<upper), newText: newText))
        }
        
        edits.sort { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
        
        // the protocol doesn't allow overlapping edits
        for (edit, next) in zip(edits, edits.dropFirst()) where edit.range.upperBound > next.range.location {
            return nil
        }
        
        return edits
    }
    
    
    /// Returns where a location moves to after the edits are applied.
    ///
    /// A location inside a replaced range moves to the end of its new text.
    ///
    /// - Parameters:
    ///   - location: A location in the document before the edits.
    ///   - edits: The edits, sorted by location.
    /// - Returns: The location in the edited document.
    static func location(_ location: Int, after edits: [Self]) -> Int {
        
        var offset = 0
        for edit in edits {
            if edit.range.upperBound <= location {
                offset += (edit.newText as NSString).length - edit.range.length
            } else if edit.range.location < location {
                return edit.range.location + offset + (edit.newText as NSString).length
            } else {
                break
            }
        }
        return location + offset
    }
    
    
    private static func position(_ object: Any?) -> LanguageServerDiagnostic.Position? {
        
        guard
            let object = object as? [String: Any],
            let line = object["line"] as? Int,
            let character = object["character"] as? Int
        else { return nil }
        
        return .init(line: line, character: character)
    }
}
