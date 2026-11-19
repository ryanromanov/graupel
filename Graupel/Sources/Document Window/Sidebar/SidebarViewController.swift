//
//  SidebarViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-05-14.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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
import ControlUI

enum SidebarPane: Int, CaseIterable {
    
    case fileBrowser
    case find
}


final class SidebarViewController: SidebarTabViewController {
    
    // MARK: Public Properties
    
    var document: DirectoryDocument
    var selectedPane: SidebarPane  { SidebarPane(rawValue: self.selectedTabViewItemIndex) ?? .fileBrowser }
    
    
    // MARK: Private Properties
    
    private let chromeBackgroundView = NSView()
    private var chromeObserver: Task<Void, Never>?
    
    
    // MARK: Lifecycle
    
    init(document: DirectoryDocument) {
        
        self.document = document
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // set identifier for pane restoration
        self.tabView.identifier = NSUserInterfaceItemIdentifier("SidebarTabView")
        
        self.tabViewItems = SidebarPane.allCases.map { pane in
            let item = NSTabViewItem(viewController: pane.viewController(document: self.document))
            item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.label)
            item.label = pane.label
            return item
        }
        
        // prepare the background that is drawn in the theme's color when the window has a custom style
        self.chromeBackgroundView.wantsLayer = true
        self.chromeBackgroundView.isHidden = true
        self.chromeBackgroundView.frame = self.view.bounds
        self.chromeBackgroundView.autoresizingMask = [.width, .height]
        self.view.addSubview(self.chromeBackgroundView, positioned: .below, relativeTo: nil)
        
        // set accessibility
        self.view.setAccessibilityElement(true)
        self.view.setAccessibilityRole(.group)
        self.view.setAccessibilityLabel(String(localized: "Sidebar", table: "Document", comment: "accessibility label"))
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        guard let chrome = (self.view.window as? DocumentWindow)?.chrome else { return }
        
        self.applyChrome(chrome.style)
        self.chromeObserver?.cancel()
        self.chromeObserver = Task { [weak self] in
            for await _ in Observations({ chrome.revision }) {
                self?.applyChrome(chrome.style)
            }
        }
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.chromeObserver?.cancel()
        self.chromeObserver = nil
    }
}


extension SidebarPane {
    
    var label: String {
        
        switch self {
            case .fileBrowser:
                String(localized: "SidebarPane.fileBrowser.label",
                       defaultValue: "File Browser", table: "Document")
            case .find:
                String(localized: "SidebarPane.find.label",
                       defaultValue: "Folder Find", table: "Document",
                       comment: "noun; feature searching for text in documents within a folder")
        }
    }
}


private extension SidebarPane {
    
    var systemImage: String {
        
        switch self {
            case .fileBrowser: "folder"
            case .find: "magnifyingglass"
        }
    }
    
    
    @MainActor func viewController(document: DirectoryDocument) -> sending NSViewController {
        
        switch self {
            case .fileBrowser:
                FileBrowserViewController(document: document)
            case .find:
                NSHostingController(rootView: FolderFindView(model: FolderFinder(document: document)))
        }
    }
}


private extension SidebarViewController {
    
    /// Draws the sidebar in the color of the window chrome, or leaves it to the system when there's no custom style.
    ///
    /// - Parameter style: The style of the chrome, or `nil` for the system style.
    func applyChrome(_ style: ChromeStyle?) {
        
        self.chromeBackgroundView.isHidden = (style == nil)
        self.chromeBackgroundView.layer?.backgroundColor = style?.sidebar.cgColor
    }
}
