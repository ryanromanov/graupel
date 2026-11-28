//
//  DefaultOptions.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2017-02-14.
//
//  ---------------------------------------------------------------------------
//
//  © 2017-2024 1024jp
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

import Foundation.NSObjCRuntime
import Defaults

enum NoDocumentOnLaunchOption: Int, CaseIterable {
    
    case untitledDocument
    case openPanel
    case none
}


enum DocumentConflictOption: Int, CaseIterable {
    
    case ignore
    case notify
    case revert
}


enum WritingDirection: Int, CaseIterable {
    
    case leftToRight
    case rightToLeft
    case vertical
}


/// How a folder window lays out its tabs.
enum TabRows: Int, CaseIterable {
    
    /// The tabs have a row of their own, under the buttons.
    case two
    /// The tabs share the top bar with the buttons.
    case one
}


/// What a tab strip does with tabs that don’t fit.
enum TabOverflow: Int, CaseIterable {
    
    case scroll
    case shrink
}


enum AppearanceMode: Int, CaseIterable {
    
    case `default`
    case light
    case dark
}


@objc enum PrintInfoType: Int, CaseIterable, DefaultInitializable {
    
    static let defaultValue: Self = .none
    
    case none
    case syntaxName
    case documentName
    case filePath
    case printDate
    case pageNumber
    case lastModifiedDate
}


@objc enum AlignmentType: Int, CaseIterable, DefaultInitializable {
    
    static let defaultValue: Self = .right
    
    case left
    case center
    case right
}
