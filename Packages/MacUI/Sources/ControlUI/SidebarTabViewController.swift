//
//  SidebarTabViewController.swift
//  ControlUI
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-07-19.
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

public import AppKit

open class SidebarTabViewController: NSTabViewController {
    
    // MARK: Private Properties
    
    private lazy var tabBar = FlatTabBar()
    
    
    // MARK: Public Properties
    
    /// The colors of the pane switcher, or `nil` to use the system colors.
    public var tabBarColors: FlatTabBar.Colors? {
        
        get { self.tabBar.colors }
        set { self.tabBar.colors = newValue }
    }
    
    
    // MARK: Tab View Controller Methods
    
    open override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.tabStyle = .unspecified
        
        self.tabBar.selectionHandler = { [weak self] in self?.tabView.selectTabViewItem(at: $0) }
    }
    
    
    open override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.tabBar.setItems(self.tabViewItems)
        self.tabBar.selectedIndex = self.selectedTabViewItemIndex
    }
    
    
    open override var selectedTabViewItemIndex: Int {
        
        didSet {
            self.tabBar.selectedIndex = selectedTabViewItemIndex
        }
    }
    
    
    // MARK: Public Methods
    
    /// Creates an accessory view controller for switching panes.
    ///
    /// - Returns: An accessory view controller that displays the pane selection control.
    public func makeAccessoryViewController() -> NSSplitViewItemAccessoryViewController {
        
        let view = self.tabBar
        let containerView = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 6),
        ])
        
        // present the pane selector inside the tab view controller's accessibility group
        containerView.setAccessibilityChildren([])
        view.setAccessibilityParent(self.view)
        // -> The tabs don’t exist yet, so list the bar rather than its children.
        self.view.setAccessibilityChildren([view, self.tabView])
        
        let viewController = NSSplitViewItemAccessoryViewController()
        viewController.view = containerView
        viewController.automaticallyAppliesContentInsets = false
        if #available(macOS 26.1, *) {
            viewController.preferredScrollEdgeEffectStyle = .soft
        }
        
        return viewController
    }
}
