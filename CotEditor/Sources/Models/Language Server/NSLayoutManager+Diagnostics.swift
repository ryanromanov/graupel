//
//  NSLayoutManager+Diagnostics.swift
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

import AppKit
import StringUtils

extension NSAttributedString.Key {
    
    /// Marks the ranges underlined for diagnostics, so that they can be removed without touching other attributes.
    static let diagnosticSeverity = NSAttributedString.Key("CotEditor.diagnosticSeverity")
}


extension NSTextStorage {
    
    /// Replaces the diagnostic marks in all layout managers.
    ///
    /// - Parameter diagnostics: The diagnostics to mark, which positions refer to the current contents.
    @MainActor func apply(diagnostics: [LanguageServerDiagnostic]) {
        
        let converter = LanguageServerPositionConverter(string: self.string as NSString)
        let marks = diagnostics.compactMap { diagnostic in
            converter.range(of: diagnostic).map { (range: $0, diagnostic: diagnostic) }
        }
        
        for layoutManager in self.layoutManagers {
            layoutManager.apply(diagnosticMarks: marks)
        }
    }
}


/// A diagnostic as marked in the text.
struct DiagnosticMark: Equatable {
    
    var severity: LanguageServerDiagnostic.Severity
    var message: String
}


extension NSLayoutManager {
    
    /// Returns the diagnostic marked at a location, or right before it so that a caret just after a mark finds it.
    ///
    /// - Parameter location: The character location, typically the insertion point.
    /// - Returns: The mark, or `nil` if none.
    @MainActor final func diagnosticMark(at location: Int) -> DiagnosticMark? {
        
        let length = self.attributedString().length
        
        for index in [location, location - 1] where (0..<length).contains(index) {
            if let rawValue = self.temporaryAttribute(.diagnosticSeverity, atCharacterIndex: index, effectiveRange: nil) as? Int,
               let severity = LanguageServerDiagnostic.Severity(rawValue: rawValue),
               let message = self.temporaryAttribute(.toolTip, atCharacterIndex: index, effectiveRange: nil) as? String
            {
                return DiagnosticMark(severity: severity, message: message)
            }
        }
        
        return nil
    }
}


private extension NSLayoutManager {
    
    /// Replaces the diagnostic underlines and tooltips.
    @MainActor final func apply(diagnosticMarks marks: [(range: NSRange, diagnostic: LanguageServerDiagnostic)]) {
        
        let wholeRange = self.attributedString().range
        
        guard !marks.isEmpty || self.hasTemporaryAttribute(.diagnosticSeverity, in: wholeRange) else { return }
        
        self.groupTemporaryAttributesUpdate(in: wholeRange) {
            var markedRanges: [NSRange] = []
            self.enumerateTemporaryAttribute(.diagnosticSeverity, type: Int.self, in: wholeRange) { _, range, _ in
                markedRanges.append(range)
            }
            for range in markedRanges {
                self.removeTemporaryAttribute(.diagnosticSeverity, forCharacterRange: range)
                self.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
                self.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
                self.removeTemporaryAttribute(.toolTip, forCharacterRange: range)
            }
            
            // apply less severe ones first so that more severe ones win where they overlap
            for mark in marks.sorted(using: KeyPathComparator(\.diagnostic.severity.rawValue, order: .reverse)) {
                self.addTemporaryAttributes([
                    .diagnosticSeverity: mark.diagnostic.severity.rawValue,
                    .underlineStyle: NSUnderlineStyle([.thick, .patternDot]).rawValue,
                    .underlineColor: mark.diagnostic.severity.color,
                    .toolTip: mark.diagnostic.message,
                ], forCharacterRange: mark.range)
            }
        }
    }
}


private extension LanguageServerDiagnostic.Severity {
    
    var color: NSColor {
        
        switch self {
            case .error: .systemRed
            case .warning: .systemOrange
            case .information: .systemBlue
            case .hint: .systemGray
        }
    }
}
