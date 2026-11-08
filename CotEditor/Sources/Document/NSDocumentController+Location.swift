//
//  NSDocumentController+Location.swift
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

extension NSDocumentController {
    
    /// Opens a file, or brings its window forward if it's open, and selects a range in its text.
    ///
    /// - Parameters:
    ///   - fileURL: The file to open.
    ///   - range: Finds the range to select in the document's text, or returns `nil` to leave the selection.
    @MainActor func openTextDocument(at fileURL: URL, selecting range: @escaping (NSString) -> NSRange?) {
        
        Task {
            guard
                let (document, _) = try? await self.openDocument(withContentsOf: fileURL, display: true),
                let document = document as? TextDocument,
                let textView = document.windowControllers
                    .compactMap({ ($0.window?.contentViewController as? WindowContentViewController)?.documentViewController })
                    .first(where: { $0.document == document })?.focusedTextView
            else { return }
            
            textView.window?.makeKeyAndOrderFront(nil)
            textView.window?.makeFirstResponder(textView)
            
            if let range = range(textView.string as NSString) {
                textView.select(range: range)
            }
        }
    }
}
