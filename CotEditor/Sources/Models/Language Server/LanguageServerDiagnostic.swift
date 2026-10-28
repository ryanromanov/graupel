//
//  LanguageServerDiagnostic.swift
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

/// A problem reported by a language server.
struct LanguageServerDiagnostic: Equatable, Sendable {

    enum Severity: Int, Sendable {

        case error = 1
        case warning
        case information
        case hint
    }


    /// A position as defined in the Language Server Protocol: a zero-based line and a UTF-16 offset in the line.
    struct Position: Equatable, Sendable {

        var line: Int
        var character: Int
    }


    var start: Position
    var end: Position
    var severity: Severity
    var message: String
}


extension LanguageServerDiagnostic {

    /// Creates a diagnostic from the JSON object of the `publishDiagnostics` notification.
    ///
    /// - Parameter json: The decoded `Diagnostic` object.
    init?(json: [String: Any]) {

        guard
            let range = json["range"] as? [String: Any],
            let start = Position(json: range["start"]),
            let end = Position(json: range["end"]),
            let message = json["message"] as? String
        else { return nil }

        self.start = start
        self.end = end
        // -> The protocol lets the client decide when the severity is omitted.
        self.severity = (json["severity"] as? Int).flatMap(Severity.init(rawValue:)) ?? .error
        self.message = message
    }
}


private extension LanguageServerDiagnostic.Position {

    init?(json: Any?) {

        guard
            let json = json as? [String: Any],
            let line = json["line"] as? Int,
            let character = json["character"] as? Int
        else { return nil }

        self.init(line: line, character: character)
    }
}


/// Converts Language Server Protocol positions to character locations in a string.
///
/// The protocol counts characters in UTF-16 code units, which are what `NSString` indexes,
/// and treats `\n`, `\r\n`, and `\r` as line endings.
struct LanguageServerPositionConverter {

    private let string: NSString
    private let lineStarts: [Int]


    init(string: NSString) {

        var lineStarts = [0]
        var index = 0
        while index < string.length {
            switch string.character(at: index) {
                case 0x0A:  // \n
                    lineStarts.append(index + 1)
                case 0x0D:  // \r or \r\n
                    if index + 1 < string.length, string.character(at: index + 1) == 0x0A {
                        index += 1
                    }
                    lineStarts.append(index + 1)
                default:
                    break
            }
            index += 1
        }

        self.string = string
        self.lineStarts = lineStarts
    }


    /// Returns the character location of a position.
    ///
    /// Following the protocol, a character offset beyond the line end means the line end,
    /// and a line beyond the last line means the end of the string.
    ///
    /// - Parameter position: The position to convert.
    /// - Returns: A location in the string.
    func location(of position: LanguageServerDiagnostic.Position) -> Int {

        guard position.line >= 0 else { return 0 }
        guard position.line < self.lineStarts.count else { return self.string.length }

        let lineStart = self.lineStarts[position.line]
        let lineEnd = self.contentsEnd(ofLineAt: position.line)

        return min(lineStart + max(position.character, 0), lineEnd)
    }


    /// Returns the character range to mark for a diagnostic.
    ///
    /// An empty range is widened to the adjacent character, and a range only on trailing whitespace
    /// is moved to the last visible character of the line, so that the mark stays visible.
    ///
    /// - Parameter diagnostic: The diagnostic.
    /// - Returns: A range in the string, or `nil` if the string is empty.
    func range(of diagnostic: LanguageServerDiagnostic) -> NSRange? {
        
        guard self.string.length > 0 else { return nil }
        
        let start = self.location(of: diagnostic.start)
        let end = max(self.location(of: diagnostic.end), start)
        let lineEnd = self.contentsEnd(ofLineAt: diagnostic.start.line)
        
        let range: NSRange = if start < end {
            NSRange(start..<end)
        } else if start < lineEnd {
            NSRange(location: start, length: 1)
        } else {
            // the character before the line end
            NSRange(location: max(start - 1, 0), length: 1)
        }
        
        return self.avoidingTrailingWhitespace(range, inLine: diagnostic.start.line)
    }
    
    
    // MARK: Private Methods

    /// Moves a range within the trailing whitespace of a line onto the last visible character of the line,
    /// because text views don't draw underlines on trailing whitespace.
    private func avoidingTrailingWhitespace(_ range: NSRange, inLine line: Int) -> NSRange {
        
        guard line >= 0, line < self.lineStarts.count else { return range }
        
        let lineStart = self.lineStarts[line]
        let lineEnd = self.contentsEnd(ofLineAt: line)
        
        var visibleEnd = lineEnd
        while visibleEnd > lineStart, [0x20, 0x09].contains(self.string.character(at: visibleEnd - 1)) {
            visibleEnd -= 1
        }
        
        guard
            visibleEnd > lineStart,
            range.location >= visibleEnd,
            range.upperBound <= lineEnd
        else { return range }
        
        return NSRange(location: visibleEnd - 1, length: 1)
    }
    
    
    /// The location just before the line ending of the given line.
    private func contentsEnd(ofLineAt line: Int) -> Int {

        guard line >= 0, line < self.lineStarts.count else { return self.string.length }

        var end = (line + 1 < self.lineStarts.count) ? self.lineStarts[line + 1] : self.string.length
        while end > self.lineStarts[line], [0x0A, 0x0D].contains(self.string.character(at: end - 1)) {
            end -= 1
        }

        return end
    }
}
