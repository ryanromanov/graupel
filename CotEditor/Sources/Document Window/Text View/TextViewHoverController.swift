//
//  TextViewHoverController.swift
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

import AppKit
import SwiftUI

/// Shows what a language server says about the name under the pointer, in a popover, once the pointer has rested
/// on the name for a moment.
@MainActor final class TextViewHoverController {
    
    /// How long the pointer has to rest on a name.
    static let delay: Duration = .milliseconds(500)
    
    private weak var textView: EditorTextView?
    private var trackingArea: NSTrackingArea?
    private var pendingTask: Task<Void, Never>?
    private var popover: NSPopover?
    
    /// The text the popover is about; moving the pointer within it keeps the popover.
    private var shownRange: NSRange?
    
    /// Counts the requests, so that an answer arriving after the pointer moved on is dropped.
    private var requestCount = 0
    
    
    init(textView: EditorTextView) {
        
        self.textView = textView
    }
    
    
    /// Keeps the text view telling about pointer moves; call when it updates its tracking areas.
    func updateTrackingArea() {
        
        guard let textView = self.textView else { return }
        
        if let trackingArea = self.trackingArea {
            textView.removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                          owner: textView, userInfo: nil)
        textView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }
    
    
    /// The pointer moved to a point in the text view.
    func mouseMoved(to point: NSPoint) {
        
        let index = self.characterIndex(at: point)
        
        if self.popover != nil {
            if let index, let shownRange = self.shownRange, NSLocationInRange(index, shownRange) || index == shownRange.upperBound {
                return
            }
            self.close()
        }
        
        self.pendingTask?.cancel()
        self.requestCount += 1
        
        guard let index, self.textView?.hoverProvider != nil else { return }
        
        let request = self.requestCount
        self.pendingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.requestHover(at: index, request: request)
        }
    }
    
    
    /// The pointer left the text view.
    func mouseExited() {
        
        self.close()
    }
    
    
    /// Closes the popover and forgets a pending request.
    func close() {
        
        self.pendingTask?.cancel()
        self.requestCount += 1
        self.popover?.close()
        self.popover = nil
        self.shownRange = nil
    }
    
    
    // MARK: Private Methods
    
    /// The index of the character under a point, or `nil` if the point isn't on a character of a name.
    private func characterIndex(at point: NSPoint) -> Int? {
        
        guard
            let textView = self.textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            textView.string.isEmpty == false
        else { return nil }
        
        let containerPoint = NSPoint(x: point.x - textView.textContainerOrigin.x, y: point.y - textView.textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        
        guard glyphRect.contains(containerPoint) else { return nil }
        
        let index = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let string = textView.string as NSString
        
        guard index < string.length else { return nil }
        
        // only names: letters, digits, and underscores
        let character = string.character(at: index)
        guard let scalar = Unicode.Scalar(character),
              CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        else { return nil }
        
        // a problem's underline has its own tooltip
        if layoutManager.temporaryAttribute(.toolTip, atCharacterIndex: index, effectiveRange: nil) != nil {
            return nil
        }
        
        return index
    }
    
    
    private func requestHover(at index: Int, request: Int) {
        
        guard let textView = self.textView, let hoverProvider = textView.hoverProvider else { return }
        
        _ = hoverProvider(index) { [weak self] hover in
            guard let self, request == self.requestCount, let hover else { return }
            
            self.show(hover, at: index)
        }
    }
    
    
    private func show(_ hover: LanguageServerHover, at index: Int) {
        
        guard
            let textView = self.textView,
            textView.window?.isKeyWindow == true,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }
        
        let range = hover.range.flatMap { NSLocationInRange(index, $0) || index == $0.upperBound ? $0 : nil }
            ?? textView.selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: .selectByWord)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = false
        let controller = NSHostingController(rootView: HoverView(parts: hover.parts))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
        
        self.popover = popover
        self.shownRange = range
    }
}


/// The contents of the hover popover: prose, and code in a monospaced font.
private struct HoverView: View {
    
    var parts: [(text: String, isCode: Bool)]
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(self.parts.enumerated()), id: \.offset) { _, part in
                if part.isCode {
                    Text(part.text)
                        .font(.body.monospaced())
                } else {
                    Text((try? AttributedString(markdown: part.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                         ?? AttributedString(part.text))
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 480, alignment: .leading)
        .padding(12)
    }
}
