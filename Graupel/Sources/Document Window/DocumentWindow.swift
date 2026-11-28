//
//  DocumentWindow.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-10-31.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2026 1024jp
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
import Defaults
import Shortcut
import ControlUI

final class DocumentWindow: NSWindow {
    
    // MARK: Public Properties
    
    /// The chrome of the window, drawn from the editor theme.
    var chrome: WindowChrome?  { (self.contentViewController as? WindowContentViewController)?.chrome }
    
    var contentBackgroundColor: NSColor = .controlBackgroundColor {
        
        didSet {
            guard
                !self.isOpaque,
                contentBackgroundColor != oldValue
            else { return }
            
            self.applyBackgroundOpacity()
        }
    }
    
    /// The background color of the window when it is drawn with a custom style.
    var chromeBackgroundColor: NSColor? {
        
        didSet {
            guard chromeBackgroundColor != oldValue else { return }
            
            self.applyBackgroundOpacity()
        }
    }
    
    private weak var closeMenuItem: NSMenuItem?
    /// The title of the Close command as the menu has it.
    private static var closeTitle: String?
    
    @objc dynamic var backgroundAlpha: Double = 1.0 {
        
        didSet {
            backgroundAlpha.clamp(to: 0.2...1.0)
            
            guard
                !self.styleMask.contains(.fullScreen),
                backgroundAlpha != oldValue
            else { return }
            
            self.applyBackgroundOpacity()
        }
    }
    
    
    // MARK: Public Methods
    
    /// Applies the theme of the editor to the window.
    ///
    /// - Parameter theme: The theme to apply.
    func apply(theme: Theme) {
        
        self.contentBackgroundColor = theme.background.color
    }
    
    
    /// Applies the current background opacity to the window.
    func applyBackgroundOpacity() {
        
        let shouldBeOpaque = (self.backgroundAlpha == 1.0)
        
        if self.isOpaque != shouldBeOpaque {
            self.isOpaque = shouldBeOpaque
        }
        self.backgroundColor = shouldBeOpaque ? self.chromeBackgroundColor : self.contentBackgroundColor.withAlphaComponent(self.backgroundAlpha)
        
        self.invalidateShadow()
        self.contentView?.needsDisplay = true
    }
    
    
    /// Gives the title bar the height of the top bar, with an empty toolbar.
    func installTitleBarSpacer() {
        
        guard self.toolbar == nil else { return }
        
        self.toolbar = NSToolbar(identifier: "TitleBarSpacer")
        self.toolbarStyle = .unifiedCompact
    }
    
    
    // MARK: Window Methods
    
    override func performClose(_ sender: Any?) {
        
        // in a folder window, the Close command closes the tab, while the close button closes the window
        if sender is NSMenuItem,
           let directoryDocument = self.tabbedDocument,
           let document = directoryDocument.currentDocument
        {
            Task { await directoryDocument.closeTab(of: document) }
            return
        }
        
        super.performClose(sender)
    }
    
    
    override func selectNextTab(_ sender: Any?) {
        
        guard self.tabbedDocument != nil else { return super.selectNextTab(sender) }
        
        self.selectDocumentTab(offset: 1)
    }
    
    
    override func selectPreviousTab(_ sender: Any?) {
        
        guard self.tabbedDocument != nil else { return super.selectPreviousTab(sender) }
        
        self.selectDocumentTab(offset: -1)
    }
    
    
    override func resignKey() {
        
        super.resignKey()
        
        // other windows don’t retitle the Close command
        if let title = Self.closeTitle {
            self.closeMenuItem?.title = title
        }
    }
    
    
    override func sendEvent(_ event: NSEvent) {
        
        // macOS doesn’t act on a double-click on the top bar, so follow the user’s setting here
        if event.type == .leftMouseUp,
           event.clickCount == 2,
           !self.styleMask.contains(.fullScreen),
           self.contentView?.superview?.hitTest(event.locationInWindow) is TopBar
        {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": self.miniaturize(nil)
                case "None": break
                default: self.zoom(nil)
            }
            return
        }
        
        super.sendEvent(event)
    }
    
    
    override static var restorableStateKeyPaths: [String] {
        
        super.restorableStateKeyPaths + [#keyPath(backgroundAlpha), #keyPath(level)]
    }
    
    
    override static func allowedClasses(forRestorableStateKeyPath keyPath: String) -> [AnyClass] {
        
        switch keyPath {
            case #keyPath(backgroundAlpha), #keyPath(level):
                [NSNumber.self]
            default:
                super.allowedClasses(forRestorableStateKeyPath: keyPath)
        }
    }
    
    
    override var isOpaque: Bool {
        
        willSet { self.willChangeValue(for: \.isOpaque) }
        didSet { self.didChangeValue(for: \.isOpaque) }
    }
    
    
    // MARK: Actions
    
    /// Closes the window, with all its tabs.
    @IBAction func performCloseWindow(_ sender: Any?) {
        
        super.performClose(nil)
    }
    
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        switch item.action {
            case #selector(toggleKeepOnTop):
                (item as? any StatableItem)?.state = self.isFloating ? .on : .off
                
            case #selector(performClose(_:)):
                if let menuItem = item as? NSMenuItem {
                    let isValid = super.validateUserInterfaceItem(item)
                    self.closeMenuItem = menuItem
                    let title = Self.closeTitle ?? menuItem.title
                    Self.closeTitle = title
                    menuItem.title = (self.tabbedDocument?.currentDocument != nil)
                        ? String(localized: "Close Tab", table: "Document", comment: "menu item")
                        : title
                    return isValid
                }
                
            case #selector(performCloseWindow):
                (item as? NSMenuItem)?.isHidden = (self.tabbedDocument?.currentDocument == nil)
                return self.styleMask.contains(.closable)
                
            case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
                if let directoryDocument = self.tabbedDocument {
                    return directoryDocument.tabs.items.count > 1
                }
                
            default:
                break
        }
        
        return super.validateUserInterfaceItem(item)
    }
    
    
    /// Toggle the window level between normal and floating.
    @IBAction func toggleKeepOnTop(_ sender: Any?) {
        
        self.isFloating.toggle()
    }
    
    
    // MARK: Private Methods
    
    /// The folder whose documents the window shows in tabs, if it’s a folder window.
    private var tabbedDocument: DirectoryDocument? {
        
        (self.windowController as? DocumentWindowController)?.directoryDocument
    }
    
    
    /// Selects the tab the given number of places after the selected one.
    private func selectDocumentTab(offset: Int) {
        
        guard
            let directoryDocument = self.tabbedDocument,
            let document = directoryDocument.tabs.item(offsetFromSelection: offset),
            document != directoryDocument.currentDocument
        else { return }
        
        directoryDocument.show(document)
    }
    
    
    /// Selects a tab of a folder window with a keyboard shortcut.
    ///
    /// - Parameter event: The key down event.
    /// - Returns: `true` if the event selects a tab.
    private func selectDocumentTab(with event: NSEvent) -> Bool {
        
        guard
            let directoryDocument = self.tabbedDocument,
            !directoryDocument.tabs.items.isEmpty
        else { return false }
        
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers ?? ""
        let tabKeyCode: UInt16 = 48
        
        let offset: Int? = switch (modifiers, key) {
            case ([.command, .shift], "{"), ([.command, .shift], "["): -1
            case ([.command, .shift], "}"), ([.command, .shift], "]"): 1
            case ([.control], _) where event.keyCode == tabKeyCode: 1
            case ([.control, .shift], _) where event.keyCode == tabKeyCode: -1
            default: nil
        }
        // ⌘1–⌘8 select a tab by its position, and ⌘9 the last one
        let number = (modifiers == [.command] && key.count == 1) ? Int(key).flatMap { (1...9).contains($0) ? $0 : nil } : nil
        
        guard offset != nil || number != nil else { return false }
        
        // prefer a shortcut that the user might have defined
        guard NSApp.mainMenu?.performKeyEquivalent(with: event) != true else { return true }
        
        if let offset {
            self.selectDocumentTab(offset: offset)
        } else if let number {
            let items = directoryDocument.tabs.items
            if let document = (number == 9) ? items.last : items[safe: number - 1], document != directoryDocument.currentDocument {
                directoryDocument.show(document)
            }
        }
        
        return true
    }
    
    
    /// Whether the window level is floating.
    private var isFloating: Bool {
        
        get { self.level == .floating }
        set { self.level = newValue ? .floating : .normal }
    }
}


// MARK: Window Tabbing

extension DocumentWindow {
    
    /// The temporal tabbing preference (remember to set it to `nil` after use).
    static var tabbingPreference: NSWindow.UserTabbingPreference?
    
    
    // MARK: Window Methods
    
    override class var userTabbingPreference: NSWindow.UserTabbingPreference {
        
        if let tabbingPreference = self.tabbingPreference {
            return tabbingPreference
        }
        
        if let tabbingPreference = NSWindow.UserTabbingPreference(rawValue: UserDefaults.standard[.windowTabbing]), tabbingPreference.rawValue >= 0 {  // -1 obeys system setting
            return tabbingPreference
        }
        
        return super.userTabbingPreference
    }
    
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        
        guard !super.performKeyEquivalent(with: event) else { return true }
        
        if self.selectDocumentTab(with: event) { return true }
        
        // select tabbed window with `⌘-number` (`⌘9` for the last tab)
        if
            self.tabbingMode != .disallowed,
            let shortcut = Shortcut(keyDownEvent: event),
            shortcut.modifiers == [.command],
            shortcut.keyEquivalent.count == 1,
            let number = Int(shortcut.keyEquivalent), number > 0,
            let group = self.tabGroup,
            let window = (number == 9) ? group.windows.last : group.windows[safe: number - 1]  // 1-based to 0-based
        {
            // prefer existing shortcut that user might define
            guard NSApp.mainMenu?.performKeyEquivalent(with: event) != true else { return true }
            
            group.selectedWindow = window
            return true
        }
        
        return false
    }
}
