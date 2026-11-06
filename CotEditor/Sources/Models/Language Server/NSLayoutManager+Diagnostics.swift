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
    
    /// Marks the ranges of diagnostics, so that they can be found and removed without touching other attributes.
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
    
    
    /// Draws a row of dots under the diagnostics in the given glyphs.
    ///
    /// The dots aren't an underline attribute, because AppKit leaves underlines out where glyphs cross them,
    /// and so can draw nothing at all under a single character such as `g` or `{`.
    ///
    /// - Parameters:
    ///   - glyphsToShow: The range of glyphs being drawn.
    ///   - origin: The position of the text container in the coordinate system of the focused view.
    final func drawDiagnosticMarks(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        
        guard self.hasTemporaryAttribute(.diagnosticSeverity, in: characterRange) else { return }
        
        self.enumerateTemporaryAttribute(.diagnosticSeverity, type: Int.self, in: characterRange) { rawValue, range, _ in
            guard
                let severity = LanguageServerDiagnostic.Severity(rawValue: rawValue),
                let range = range.intersection(characterRange)
            else { return }
            
            let font = self.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let descent = abs(font?.descender ?? 0)
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            
            severity.color.setFill()
            self.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, container, lineGlyphRange, _ in
                guard let markedRange = glyphRange.intersection(lineGlyphRange) else { return }
                
                let glyphsRect = self.boundingRect(forGlyphRange: markedRange, in: container)
                let baseline = lineRect.minY + self.location(forGlyphAt: markedRange.location).y
                let y = min(baseline + descent, lineRect.maxY - DiagnosticDots.diameter)
                
                for x in DiagnosticDots.positions(from: glyphsRect.minX, width: glyphsRect.width) {
                    NSBezierPath(ovalIn: NSRect(x: x + origin.x, y: y + origin.y,
                                                width: DiagnosticDots.diameter, height: DiagnosticDots.diameter)).fill()
                }
            }
        }
    }
}


/// The row of dots marking a diagnostic.
enum DiagnosticDots {
    
    static let diameter: CGFloat = 2
    private static let spacing: CGFloat = 3.5
    
    
    /// Returns the left sides of the dots to fill the given width, with at least two dots.
    ///
    /// - Parameters:
    ///   - minX: The left side of the marked text.
    ///   - width: The width of the marked text.
    /// - Returns: The horizontal positions of the dots.
    static func positions(from minX: CGFloat, width: CGFloat) -> [CGFloat] {
        
        let count = max(Int((width - self.diameter) / self.spacing) + 1, 2)
        
        return (0..<count).map { minX + CGFloat($0) * self.spacing }
    }
}


private extension NSLayoutManager {
    
    /// Replaces the diagnostic marks and tooltips.
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
                self.removeTemporaryAttribute(.toolTip, forCharacterRange: range)
            }
            
            // apply less severe ones first so that more severe ones win where they overlap
            for mark in marks.sorted(using: KeyPathComparator(\.diagnostic.severity.rawValue, order: .reverse)) {
                self.addTemporaryAttributes([
                    .diagnosticSeverity: mark.diagnostic.severity.rawValue,
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
