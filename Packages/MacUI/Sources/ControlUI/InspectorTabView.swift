//
//  InspectorTabView.swift
//  InspectorTabView
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-05-31.
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

public import AppKit

public final class InspectorTabView: NSTabView {
    
    // MARK: Private Properties
    
    private let tabBar = FlatTabBar()
    
    
    // MARK: Public Properties
    
    /// The colors of the pane switcher, or `nil` to use the system colors.
    public var tabBarColors: FlatTabBar.Colors? {
        
        get { self.tabBar.colors }
        set { self.tabBar.colors = newValue }
    }
    
    
    // MARK: Lifecycle
    
    public override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.tabViewType = .noTabsNoBorder
        
        // setup the private tab control
        self.tabBar.selectionHandler = { [weak self] in self?.selectTabViewItem(at: $0) }
        
        // add control parts
        self.tabBar.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.tabBar)
        
        NSLayoutConstraint.activate([
            self.tabBar.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor),
            self.tabBar.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor),
            self.tabBar.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor),
        ])
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: Tab View Methods
    
    public override func accessibilityChildren() -> [Any]? {
        
        // a tab view without its own tabs leaves out the bar
        let children = super.accessibilityChildren() ?? []
        
        return children.contains { $0 as? NSView === self.tabBar } ? children : [self.tabBar] + children
    }
    
    public override var contentRect: NSRect {
        
        // take off control space
        let offset = self.safeAreaInsets.top + FlatTabBar.height
        var rect = self.bounds
        rect.origin.y = offset
        rect.size.height -= offset
        
        return rect
    }
    
    
    public override func layout() {
        
        super.layout()
        
        self.selectedTabViewItem?.view?.frame = self.contentRect
    }
    
    
    public override func selectTabViewItem(at index: Int) {
        
        super.selectTabViewItem(at: index)
        
        self.tabBar.selectedIndex = index
    }
    
    
    public override func insertTabViewItem(_ tabViewItem: NSTabViewItem, at index: Int) {
        
        super.insertTabViewItem(tabViewItem, at: index)
        
        self.rebuildSegmentedControl()
    }
    
    
    public override func removeTabViewItem(_ tabViewItem: NSTabViewItem) {
        
        super.removeTabViewItem(tabViewItem)
        
        self.rebuildSegmentedControl()
    }
    
    
    // MARK: Private Methods
    
    /// Updates the private control every time when the line-up of tab items changed.
    private func rebuildSegmentedControl() {
        
        self.tabBar.setItems(self.tabViewItems)
        
        if let item = self.selectedTabViewItem, let index = self.tabViewItems.firstIndex(of: item) {
            self.tabBar.selectedIndex = index
        }
    }
}
