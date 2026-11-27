//
//  InspectorViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-06-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2016-2026 1024jp
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
import Defaults
import ControlUI

enum InspectorPane: Int, CaseIterable {
    
    case document
    case outline
    case warnings
}


final class InspectorViewController: NSTabViewController {
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument() } }
    var selectedPane: InspectorPane  { InspectorPane(rawValue: self.selectedTabViewItemIndex) ?? .document }
    
    
    // MARK: Private Properties
    
    private let chromeBackgroundView = NSView()
    private var chromeObserver: Task<Void, Never>?
    
    
    // MARK: Lifecycle
    
    convenience init(document: DataDocument?) {
        
        self.init(nibName: nil, bundle: nil)
        
        self.document = document
    }
    
    
    override func loadView() {
        
        let tabView = InspectorTabView()
        let view = NSView()
        
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)
        
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: tabView.topAnchor),
            view.bottomAnchor.constraint(equalTo: tabView.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: tabView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: tabView.trailingAnchor),
        ])
        
        self.tabView = tabView
        self.view = view
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // set identifier for pane restoration
        self.tabView.identifier = NSUserInterfaceItemIdentifier("InspectorTabView")
        
        self.tabViewItems = InspectorPane.allCases.map { pane in
            let item = NSTabViewItem(viewController: pane.viewController(document: self.document))
            item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.label)
            item.label = pane.label
            return item
        }
        
        // select last used pane
        if let pane = InspectorPane(rawValue: UserDefaults.standard[.selectedInspectorPaneIndex]) {
            self.selectedTabViewItemIndex = pane.rawValue
        }
        
        // prepare the background that is drawn in the theme’s color
        self.chromeBackgroundView.wantsLayer = true
        self.chromeBackgroundView.isHidden = true
        self.chromeBackgroundView.frame = self.view.bounds
        self.chromeBackgroundView.autoresizingMask = [.width, .height]
        self.view.addSubview(self.chromeBackgroundView, positioned: .below, relativeTo: nil)
        
        // set accessibility
        self.view.setAccessibilityElement(true)
        self.view.setAccessibilityRole(.group)
        self.view.setAccessibilityLabel(String(localized: "Inspector", table: "Document", comment: "accessibility label"))
    }
    
    
    // MARK: Tab View Controller Methods
    
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
    
    
    override var selectedTabViewItemIndex: Int {
        
        didSet {
            // ignore initial setting that select 0
            guard oldValue != -1 else { return }
            
            UserDefaults.standard[.selectedInspectorPaneIndex] = selectedTabViewItemIndex
        }
    }
    
    
    // MARK: Private Methods
    
    /// Draws the inspector in the color of the window chrome.
    ///
    /// - Parameter style: The style of the chrome, or `nil` for the system style.
    private func applyChrome(_ style: ChromeStyle?) {
        
        self.chromeBackgroundView.isHidden = (style == nil)
        self.chromeBackgroundView.layer?.backgroundColor = style?.sidebar.cgColor
        (self.tabView as? InspectorTabView)?.tabBarColors = style?.tabBarColors
    }
    
    
    /// Updates the document in children.
    private func updateDocument() {
        
        for case let viewController as any InspectorPaneHosting in self.tabViewItems.map(\.viewController) {
            viewController.document = self.document
        }
    }
}


private extension InspectorPane {
    
    /// The localized label for the pane.
    var label: String {
        
        switch self {
            case .document:
                String(localized: "InspectorPane.document.label",
                       defaultValue: "Document Inspector", table: "Document")
            case .outline:
                String(localized: "InspectorPane.outline.label",
                       defaultValue: "Outline", table: "Document")
            case .warnings:
                String(localized: "InspectorPane.warnings.label",
                       defaultValue: "Warnings", table: "Document")
        }
    }
    
    
    /// The system image name for the pane.
    var systemImage: String {
        
        switch self {
            case .document: "document"
            case .outline: "list.bullet.indent"
            case .warnings: "exclamationmark.triangle"
        }
    }
    
    
    /// Creates a view controller for the pane.
    ///
    /// - Parameter document: The document to inspect.
    /// - Returns: A view controller for the pane.
    @MainActor func viewController(document: DataDocument?) -> sending any NSViewController & InspectorPaneHosting {
        
        switch self {
            case .document:
                InspectorPaneHostingController(rootView: DocumentInspectorView(document: document))
            case .outline:
                InspectorPaneHostingController(rootView: OutlineInspectorView(document: document))
            case .warnings:
                InspectorPaneHostingController(rootView: WarningInspectorView(document: document))
        }
    }
}
