//
//  LanguageServerCompletion.swift
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

/// A suggestion from a language server for completing the word at the cursor.
struct LanguageServerCompletionItem: Equatable, Sendable {
    
    var label: String
    
    /// The text that replaces the partial word.
    var text: String
    
    /// The text to sort the items by.
    var sortText: String
    
    
    /// Creates an item from the JSON object of a `CompletionItem`.
    ///
    /// - Parameter json: The decoded `CompletionItem` object.
    init?(json: Any?) {
        
        guard
            let json = json as? [String: Any],
            let label = json["label"] as? String
        else { return nil }
        
        let textEdit = json["textEdit"] as? [String: Any]
        
        self.label = label
        self.text = textEdit?["newText"] as? String ?? json["insertText"] as? String ?? label
        self.sortText = json["sortText"] as? String ?? label
    }
    
    
    /// Returns the words to suggest from the result of a `textDocument/completion` request.
    ///
    /// - Parameter result: The result, which is a `CompletionList`, an array of `CompletionItem`, or `null`.
    /// - Returns: The texts of the items, in the order the server sorts them.
    static func words(result: Any?) -> [String] {
        
        let items = (result as? [String: Any])?["items"] ?? result
        
        return ((items as? [Any]) ?? [])
            .compactMap(Self.init(json:))
            .enumerated()
            // keep the server's order for items with the same sort text
            .sorted { ($0.element.sortText, $0.offset) < ($1.element.sortText, $1.offset) }
            .map(\.element.text)
    }
}
