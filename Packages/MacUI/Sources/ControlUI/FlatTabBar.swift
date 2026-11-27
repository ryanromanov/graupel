//
//  FlatTabBar.swift
//  ControlUI
//
//  Graupel
//  https://github.com/ryanromanov/graupel
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

public import AppKit

/// A row of icon tabs that marks the selected one with a solid block.
public final class FlatTabBar: NSView {
    
    /// The colors of a tab bar.
    public nonisolated struct Colors {
        
        /// The fill of the selected tab.
        public var selection: NSColor
        
        /// The icon on the selected tab.
        public var onSelection: NSColor
        
        /// The icons of the other tabs.
        public var icon: NSColor
        
        /// The lines above and below the bar.
        public var border: NSColor
        
        
        public init(selection: NSColor, onSelection: NSColor, icon: NSColor, border: NSColor) {
            
            self.selection = selection
            self.onSelection = onSelection
            self.icon = icon
            self.border = border
        }
        
        
        /// The colors to use when none are given.
        static var system: Self {
            
            Self(selection: .controlAccentColor, onSelection: .alternateSelectedControlTextColor,
                 icon: .secondaryLabelColor, border: .separatorColor)
        }
    }
    
    
    // MARK: Public Properties
    
    public static let height: CGFloat = 32
    
    /// The colors to draw with, or `nil` to use the system colors.
    public var colors: Colors?  { didSet { self.update() } }
    
    public var selectedIndex: Int = 0  { didSet { self.update() } }
    
    /// Called when the user chooses a tab.
    public var selectionHandler: ((Int) -> Void)?
    
    
    // MARK: Private Properties
    
    private let stackView = NSStackView()
    private var buttons: [FlatTabButton]  { self.stackView.arrangedSubviews.compactMap { $0 as? FlatTabButton } }
    
    
    // MARK: Lifecycle
    
    public override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        
        self.stackView.distribution = .fillEqually
        self.stackView.spacing = 0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.stackView)
        
        // leave room for the lines above and below
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: Self.height),
            self.stackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 1),
            self.stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -1),
            self.stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
        
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.radioGroup)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: View Methods
    
    public override func draw(_ dirtyRect: NSRect) {
        
        super.draw(dirtyRect)
        
        (self.colors ?? .system).border.setFill()
        NSRect(x: 0, y: 0, width: self.bounds.width, height: 1).fill()
        NSRect(x: 0, y: self.bounds.height - 1, width: self.bounds.width, height: 1).fill()
    }
    
    
    // MARK: Public Methods
    
    /// Sets the tabs to show.
    ///
    /// - Parameter items: The tab view items whose images and labels the tabs show.
    public func setItems(_ items: [NSTabViewItem]) {
        
        self.buttons.forEach { $0.removeFromSuperview() }
        
        // a tab without an image isn't one the user can choose
        for (index, item) in items.enumerated() where item.image != nil {
            let button = FlatTabButton()
            button.image = item.image
            button.toolTip = item.label
            button.cell?.setAccessibilityLabel(item.label)
            button.tag = index
            button.target = self
            button.action = #selector(didChooseTab)
            button.moveHandler = { [weak self] in self?.select(index: index + $0) }
            self.stackView.addArrangedSubview(button)
            button.heightAnchor.constraint(equalTo: self.stackView.heightAnchor).isActive = true
        }
        
        self.update()
    }
    
    
    // MARK: Private Methods
    
    @objc private func didChooseTab(_ sender: NSButton) {
        
        self.select(index: sender.tag)
    }
    
    
    /// Selects a tab on the user's behalf.
    private func select(index: Int) {
        
        guard self.buttons.indices.contains(index) else { return }
        
        self.selectedIndex = index
        self.selectionHandler?(index)
    }
    
    
    /// Applies the selection and the colors to the tabs.
    private func update() {
        
        let colors = self.colors ?? .system
        
        for button in self.buttons {
            let isSelected = (button.tag == self.selectedIndex)
            button.fillColor = isSelected ? colors.selection : nil
            button.contentTintColor = isSelected ? colors.onSelection : colors.icon
            // a button’s accessibility element is its cell
            button.cell?.setAccessibilityValue(isSelected ? 1 : 0)
        }
        
        self.needsDisplay = true
    }
}


private final class FlatTabButton: NSButton {
    
    var fillColor: NSColor?  { didSet { self.needsDisplay = true } }
    
    /// Called with the direction when the user presses an arrow key.
    var moveHandler: ((Int) -> Void)?
    
    
    init() {
        
        super.init(frame: .zero)
        
        self.isBordered = false
        self.imagePosition = .imageOnly
        self.setButtonType(.momentaryChange)
        self.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.cell?.setAccessibilityRole(.radioButton)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // the button’s usual margins would make the fill spill over the lines around the bar
    override var alignmentRectInsets: NSEdgeInsets  { NSEdgeInsets() }
    
    
    override func draw(_ dirtyRect: NSRect) {
        
        if let fillColor {
            fillColor.setFill()
            self.bounds.fill()
        }
        
        super.draw(dirtyRect)
    }
    
    
    override func moveLeft(_ sender: Any?) {
        
        self.moveHandler?(self.userInterfaceLayoutDirection == .rightToLeft ? 1 : -1)
    }
    
    
    override func moveRight(_ sender: Any?) {
        
        self.moveHandler?(self.userInterfaceLayoutDirection == .rightToLeft ? -1 : 1)
    }
    
    
    override func keyDown(with event: NSEvent) {
        
        switch event.specialKey {
            case .leftArrow: self.moveLeft(self)
            case .rightArrow: self.moveRight(self)
            default: super.keyDown(with: event)
        }
    }
}
