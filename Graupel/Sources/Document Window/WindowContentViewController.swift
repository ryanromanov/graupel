//
//  WindowContentViewController.swift
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
import Combine
import ControlUI
import Defaults

final class WindowContentViewController: NSSplitViewController {
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument() } }
    /// The chrome of the window, drawn from the editor theme.
    let chrome = WindowChrome()
    var documentViewController: DocumentViewController?  { self.contentViewController.hostedViewController as? DocumentViewController }
    
    
    // MARK: Private Properties
    
    private let directoryDocument: DirectoryDocument?
    
    private var sidebarStateCache: Bool?
    private let statusBarModel: StatusBar.Model
    
    private var sidebarViewItem: NSSplitViewItem?
    @ViewLoading private var contentViewItem: NSSplitViewItem
    @ViewLoading private var inspectorViewItem: NSSplitViewItem
    
    private var versionBrowserObservers: [any NSObjectProtocol] = []
    
    private var defaultsObserver: AnyCancellable?
    private var chromeObserver: Task<Void, Never>?
    
    private let topBar = TopBar()
    @ViewLoading private var topBarWindowedConstraint: NSLayoutConstraint
    @ViewLoading private var topBarFullScreenConstraint: NSLayoutConstraint
    private var topBarObservers: Set<AnyCancellable> = []
    private var runObserver: Task<Void, Never>?
    
    /// The tabs of a folder window, shown in their own row or in the top bar.
    private let tabStrip = TabStrip()
    private let tabRow = NSView()
    private var tabRowController: NSSplitViewItemAccessoryViewController?
    private var tabSettingObservers: Set<AnyCancellable> = []
    
    
    // MARK: Split View Controller Methods
    
    init(document: DataDocument?, directoryDocument: DirectoryDocument?) {
        
        assert(document != nil || directoryDocument != nil)
        
        self.document = document
        self.directoryDocument = directoryDocument
        self.statusBarModel = .init(document: document)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        self.versionBrowserObservers.forEach(NotificationCenter.default.removeObserver)
        self.chromeObserver?.cancel()
        self.runObserver?.cancel()
    }
    
    
    override func loadView() {
        
        self.view = HoleContentView<BidiScrollView>()
        self.view.frame.size = NSSize(width: 640, height: 720)
        
        self.splitView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.splitView)
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        if let directoryDocument {
            let viewController = SidebarViewController(document: directoryDocument)
            let sidebarViewItem = NSSplitViewItem(sidebarWithViewController: viewController)
            sidebarViewItem.addTopAlignedAccessoryViewController(viewController.makeAccessoryViewController())
            self.addSplitViewItem(sidebarViewItem)
            self.sidebarViewItem = sidebarViewItem
        }
        
        let contentViewController = ContentViewController(document: self.document)
        self.contentViewItem = NSSplitViewItem(viewController: contentViewController)
        let statusBarController = NSSplitViewItemAccessoryViewController()
        statusBarController.view = NSHostingView(rootView: StatusBar(model: self.statusBarModel, chrome: self.chrome))
        statusBarController.isHidden = !UserDefaults.standard[.showStatusBar]
        if #unavailable(macOS 27) {
            statusBarController.automaticallyAppliesContentInsets = false
        } else {
            // a custom window style must color the whole bar, so the status bar then insets itself
            self.chromeObserver = Task { [chrome, weak statusBarController] in
                for await _ in Observations({ chrome.revision }) {
                    statusBarController?.automaticallyAppliesContentInsets = !chrome.isActive
                }
            }
        }
        self.contentViewItem.addBottomAlignedAccessoryViewController(statusBarController)
        self.addSplitViewItem(self.contentViewItem)
        
        if self.directoryDocument != nil {
            contentViewController.view.setAccessibilityElement(true)
            contentViewController.view.setAccessibilityRole(.group)
            contentViewController.view.setAccessibilityLabel(self.document?.displayName ?? "")
        }
        
        let inspectorViewController = InspectorViewController(document: self.document)
        self.inspectorViewItem = NSSplitViewItem(inspectorWithViewController: inspectorViewController)
        self.inspectorViewItem.minimumThickness = 200
        self.inspectorViewItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
        self.inspectorViewItem.isCollapsed = true
        self.inspectorViewItem.titlebarSeparatorStyle = .none
        self.addSplitViewItem(self.inspectorViewItem)
        
        self.setUpTopBar()
        
        if let directoryDocument {
            self.setUpTabs(for: directoryDocument)
        }
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        // -> Set the `autosaveName` first after the view is placed in the window.
        //    Otherwise, the last state won’t be applied (2025-07, macOS 26).
        // -> Need to set *both* identifier and autosaveName to make autosaving work.
        let autosaveName = (self.directoryDocument == nil) ? "WindowContentSplitView" : "DirectoryWindowContentSplitView"
        self.splitView.identifier = NSUserInterfaceItemIdentifier(autosaveName)
        let hasSavedWidths = (UserDefaults.standard.object(forKey: "NSSplitView Subview Frames \(autosaveName)") != nil)
        self.splitView.autosaveName = autosaveName
        
        // without widths to restore, the sidebar would take much of the window
        if !hasSavedWidths, self.sidebarViewItem != nil {
            self.splitView.setPosition(220, ofDividerAt: 0)
        }
        
        // keep open sidebar at the beginning
        self.sidebarViewItem?.isCollapsed = false
        
        // forcibly collapse sidebar while version browse
        self.versionBrowserObservers.forEach(NotificationCenter.default.removeObserver)
        self.versionBrowserObservers = if self.sidebarViewItem != nil, let window = self.view.window {
            [
                NotificationCenter.default.addObserver(forName: NSWindow.willEnterVersionBrowserNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard
                            let self,
                            let sidebarViewItem = self.sidebarViewItem
                        else { return }
                        
                        self.sidebarStateCache = sidebarViewItem.isCollapsed
                        sidebarViewItem.isCollapsed = true
                    }
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didExitVersionBrowserNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard
                            let self,
                            let sidebarViewItem = self.sidebarViewItem,
                            let sidebarStateCache = self.sidebarStateCache
                        else { return }
                        
                        sidebarViewItem.isCollapsed = sidebarStateCache
                        self.sidebarStateCache = nil
                    }
                },
            ]
        } else {
            []
        }
        
        self.observeTopBarState()
        
        // move focus to the editor
        // -> The editor doesn’t automatically receive focus
        //    when keyboard navigation is enabled in system settings. (2025-11, macOS 26)
        self.focusEditor()
        
        // observe user defaults for status bar
        let statusBarController = self.contentViewItem.bottomAlignedAccessoryViewControllers.first
        self.defaultsObserver = UserDefaults.standard.publisher(for: .showStatusBar)
            .sink { statusBarController?.animator().isHidden = !$0 }
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.versionBrowserObservers.forEach(NotificationCenter.default.removeObserver)
        self.versionBrowserObservers.removeAll()
        
        if let sidebarStateCache {
            self.sidebarViewItem?.isCollapsed = sidebarStateCache
            self.sidebarStateCache = nil
        }
        
        self.defaultsObserver?.cancel()
        self.defaultsObserver = nil
        self.topBarObservers.removeAll()
        self.runObserver?.cancel()
        self.runObserver = nil
    }
    
    
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        
        super.splitViewDidResizeSubviews(notification)
        
        self.topBar.needsLayout = true
    }
    
    
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        
        // reel responders from the ideal first responder in the content view
        // for when the actual first responder is on the sidebar/inspector
        if let endResponder = self.documentViewController?.focusedTextView,
           let responder = sequence(first: endResponder, next: \.nextResponder).first(where: { $0.responds(to: action) }) {
            return responder
        } else {
            return super.supplementalTarget(forAction: action, sender: sender)
        }
    }
    
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        switch item.action {
            case #selector(toggleSidebar):
                // The menu item is not validated when the responder has no sidebar (2025-03, macOS 15).
                (item as? NSMenuItem)?.title = self.sidebarViewItem?.isCollapsed == false
                    ? String(localized: "Hide Sidebar", table: "MainMenu", comment: "verb; menu item")
                    : String(localized: "Show Sidebar", table: "MainMenu", comment: "verb; menu item")
                (item as? NSMenuItem)?.toolTip = self.sidebarAvailabilityHint
                return self.canToggleSidebar
                
            case #selector(showFileBrowser):
                (item as? NSMenuItem)?.state = self.isSidebarShown(pane: .fileBrowser) ? .on : .off
                (item as? NSMenuItem)?.toolTip = self.sidebarAvailabilityHint
                return self.canToggleSidebar
                
            case #selector(showFolderFinder):
                (item as? NSMenuItem)?.state = self.isSidebarShown(pane: .find) ? .on : .off
                (item as? NSMenuItem)?.toolTip = self.sidebarAvailabilityHint
                return self.canToggleSidebar
                
            case #selector(toggleInspector):
                (item as? NSMenuItem)?.title = self.inspectorViewItem.isCollapsed == false
                    ? String(localized: "Hide Inspector", table: "MainMenu", comment: "verb; menu item")
                    : String(localized: "Show Inspector", table: "MainMenu", comment: "verb; menu item")
                
            case #selector(showDocumentInspector):
                (item as? NSMenuItem)?.state = self.isInspectorShown(pane: .document) ? .on : .off
                
            case #selector(showOutlineInspector):
                (item as? NSMenuItem)?.state = self.isInspectorShown(pane: .outline) ? .on : .off
                
            case #selector(showWarningsInspector):
                (item as? NSMenuItem)?.state = self.isInspectorShown(pane: .warnings) ? .on : .off
                
            case #selector(toggleStatusBar):
                (item as? NSMenuItem)?.title = UserDefaults.standard[.showStatusBar]
                    ? String(localized: "Hide Status Bar", table: "MainMenu", comment: "verb; menu item")
                    : String(localized: "Show Status Bar", table: "MainMenu", comment: "verb; menu item")
                
            default: break
        }
        
        return super.validateUserInterfaceItem(item)
    }
    
    
    // MARK: Public Methods
    
    /// Opens the desired sidebar pane.
    ///
    /// - Parameter pane: The sidebar pane to open.
    private func showSidebar(pane: SidebarPane) {
        
        guard
            let sidebarViewItem,
            let tabViewController = sidebarViewItem.viewController as? NSTabViewController
        else { return assertionFailure() }
        
        sidebarViewItem.animator().isCollapsed = false
        tabViewController.selectedTabViewItemIndex = pane.rawValue
        
        // move focus
        if let paneView = tabViewController.tabViewItems[tabViewController.selectedTabViewItemIndex].viewController?.view,
           let window = self.view.window
        {
            window.discardMarkedTextIfNeeded()
            window.selectKeyView(following: paneView)
        }
    }
    
    
    /// Opens the desired inspector pane.
    ///
    /// - Parameter pane: The inspector pane to open.
    func showInspector(pane: InspectorPane) {
        
        self.inspectorViewItem.animator().isCollapsed = false
        self.inspectorViewController.selectedTabViewItemIndex = pane.rawValue
    }
    
    
    /// Lays out the window for full screen, where there is no title bar to hold the top bar.
    ///
    /// - Parameter isFullScreen: Whether the window is in full screen.
    func setFullScreen(_ isFullScreen: Bool) {
        
        // keep the columns below the bar, as the title bar does otherwise
        self.splitView.additionalSafeAreaInsets.top = isFullScreen ? TopBar.height : 0
        
        // below the tab bar if there is one in full screen
        self.topBarWindowedConstraint.isActive = false
        self.topBarFullScreenConstraint.isActive = false
        (isFullScreen ? self.topBarFullScreenConstraint : self.topBarWindowedConstraint).isActive = true
        
        self.topBar.needsLayout = true
    }
    
    
    /// Updates the contents of the top bar.
    func updateTopBar() {
        
        guard self.isViewLoaded else { return }
        
        let window = self.view.window
        let isInspectorShown = !self.inspectorViewItem.isCollapsed
        let sidebar: TopBar.State.Toggle? = self.sidebarViewItem.map { item in
            .init(isOn: !item.isCollapsed,
                  isEnabled: self.canToggleSidebar,
                  toolTip: item.isCollapsed
                      ? String(localized: "Show Sidebar", table: "MainMenu", comment: "verb; menu item")
                      : String(localized: "Hide Sidebar", table: "MainMenu", comment: "verb; menu item"))
        }
        let history = self.directoryDocument.map { document in
            (back: document.documentHistory.canNavigate(forward: false),
             forward: document.documentHistory.canNavigate(forward: true))
        }
        let inspector = TopBar.State.Toggle(isOn: isInspectorShown, isEnabled: true,
                                            toolTip: isInspectorShown
                                                ? String(localized: "Hide Inspector", table: "MainMenu", comment: "verb; menu item")
                                                : String(localized: "Show Inspector", table: "MainMenu", comment: "verb; menu item"))
        
        self.topBar.apply(.init(sidebar: sidebar,
                                history: history,
                                isRunning: self.contentViewController.runController.isRunning,
                                canRun: self.document is TextDocument,
                                inspector: inspector,
                                title: window?.title ?? "",
                                subtitle: window?.subtitle ?? "",
                                // the tabs of a folder window mark their own changes
                                isEdited: self.directoryDocument == nil && (window?.isDocumentEdited ?? false)))
    }
    
    
    // MARK: Action Messages
    
    /// Moves the focus to the editor.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func focusNextEditor(_ sender: Any?) {
        
        self.focusEditor()
    }
    
    
    /// Moves the focus to the editor.
    ///
    /// - Note: The selector name should be the same as one in `DocumentViewController`.
    @IBAction func focusPreviousEditor(_ sender: Any?) {
        
        self.focusEditor()
    }
    
    
    /// Moves the focus to the file browser.
    @IBAction func showFileBrowser(_ sender: Any?) {
        
        self.showSidebar(pane: .fileBrowser)
    }
    
    
    /// Moves the focus to the folder finder.
    @IBAction func showFolderFinder(_ sender: Any?) {
        
        self.showSidebar(pane: .find)
    }
    
    
    /// Shows the document inspector pane.
    @IBAction func showDocumentInspector(_ sender: Any?) {
        
        self.showInspector(pane: .document)
    }
    
    
    /// Shows the outline pane.
    @IBAction func showOutlineInspector(_ sender: Any?) {
        
        self.showInspector(pane: .outline)
    }
    
    
    /// Shows the warnings pane.
    @IBAction func showWarningsInspector(_ sender: Any?) {
        
        self.showInspector(pane: .warnings)
    }
    
    
    /// Toggles the visibility of status bar with fancy animation (sync all documents).
    @IBAction func toggleStatusBar(_ sender: Any?) {
        
        UserDefaults.standard[.showStatusBar].toggle()
    }
    
    
    // MARK: Private Methods
    
    /// Adds the top bar over the title bar area.
    private func setUpTopBar() {
        
        let topBar = self.topBar
        topBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(topBar)
        
        self.topBarWindowedConstraint = topBar.topAnchor.constraint(equalTo: self.view.topAnchor)
        self.topBarFullScreenConstraint = topBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            self.topBarWindowedConstraint,
            topBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: TopBar.height),
        ])
        
        topBar.columnProvider = { [weak self] in
            self?.columnWidths ?? .init(leading: 0, trailing: 0)
        }
        
        topBar.sidebarCell.target = self
        topBar.sidebarCell.action = #selector(toggleSidebar)
        topBar.inspectorCell.target = self
        topBar.inspectorCell.action = #selector(toggleInspector)
        topBar.runCell.target = self.contentViewController
        topBar.runCell.action = #selector(ContentViewController.toggleRun)
        
        if let directoryDocument {
            directoryDocument.documentHistoryDidChange = { [weak self] in self?.updateTopBar() }
            topBar.backCell.target = directoryDocument
            topBar.backCell.action = #selector(DirectoryDocument.navigateBackDocumentHistory)
            topBar.forwardCell.target = directoryDocument
            topBar.forwardCell.action = #selector(DirectoryDocument.navigateForwardDocumentHistory)
            topBar.backCell.menu = self.historyMenu(identifier: .backDocumentHistoryMenu)
            topBar.forwardCell.menu = self.historyMenu(identifier: .forwardDocumentHistoryMenu)
        }
    }
    
    
    /// Adds the tabs of a folder window.
    private func setUpTabs(for directoryDocument: DirectoryDocument) {
        
        let accessory = NSSplitViewItemAccessoryViewController()
        self.tabRow.frame.size.height = TabStrip.height
        self.tabRow.heightAnchor.constraint(equalToConstant: TabStrip.height).isActive = true
        accessory.view = self.tabRow
        accessory.automaticallyAppliesContentInsets = false
        accessory.isHidden = true
        self.contentViewItem.addTopAlignedAccessoryViewController(accessory)
        self.tabRowController = accessory
        
        self.tabStrip.perform = { [weak self] command, id in
            self?.perform(command, onTabWith: id)
        }
        directoryDocument.tabsDidChange = { [weak self] in self?.updateTabs() }
        
        self.tabSettingObservers = [
            UserDefaults.standard.publisher(for: .tabRows)
                .sink { [weak self] _ in self?.updateTabs() },
            UserDefaults.standard.publisher(for: .tabOverflow)
                .sink { [weak self] _ in self?.updateTabs() },
        ]
        self.updateTabs()
    }
    
    
    /// Shows the tabs of the folder window where the settings put them.
    private func updateTabs() {
        
        guard let directoryDocument else { return }
        
        let tabs = directoryDocument.tabs
        let names = tabs.items.map { $0.fileURL?.lastPathComponent ?? $0.displayName ?? "" }
        let rootPath = directoryDocument.fileURL?.path(percentEncoded: false) ?? ""
        let items = zip(tabs.items, names).map { document, name in
            let isAmbiguous = names.count(where: { $0 == name }) > 1
            let path = document.fileURL?.path(percentEncoded: false)
            
            return TabStrip.Item(id: ObjectIdentifier(document),
                                 title: name,
                                 detail: isAmbiguous ? document.fileURL?.deletingLastPathComponent().lastPathComponent : nil,
                                 toolTip: path.map { $0.hasPrefix(rootPath) ? String($0.dropFirst(rootPath.count)).trimmingPrefix("/").description : $0 },
                                 isSelected: document == tabs.selection,
                                 isPreview: document == tabs.preview,
                                 isEdited: document.isDocumentEdited)
        }
        
        self.tabStrip.overflow = UserDefaults.standard[.tabOverflow]
        self.tabStrip.apply(items)
        self.contentViewController.discardEditors(except: tabs.items)
        
        // place the strip; without tabs, there is no tab row
        let rows = UserDefaults.standard[.tabRows]
        if rows == .one, !items.isEmpty {
            self.topBar.tabStrip = self.tabStrip
        } else {
            self.topBar.tabStrip = nil
            if self.tabStrip.superview !== self.tabRow {
                self.tabStrip.frame = self.tabRow.bounds
                self.tabStrip.autoresizingMask = [.width, .height]
                self.tabRow.addSubview(self.tabStrip)
            }
        }
        self.tabRowController?.isHidden = (rows != .two || items.isEmpty)
        
        self.updateTopBar()
    }
    
    
    /// Does what the user asked of a tab.
    private func perform(_ command: TabStrip.Command, onTabWith id: ObjectIdentifier) {
        
        guard
            let directoryDocument,
            let document = directoryDocument.tabs.items.first(where: { ObjectIdentifier($0) == id })
        else { return }
        
        switch command {
            case .select:
                if document != directoryDocument.currentDocument {
                    directoryDocument.show(document)
                }
                self.focusEditor()
            case .keep:
                directoryDocument.keepTab(of: document)
            case .close:
                Task { await directoryDocument.closeTab(of: document) }
            case .closeOthers:
                Task { await directoryDocument.closeTabs(except: document) }
            case .openInNewWindow:
                if let fileURL = document.fileURL {
                    directoryDocument.openInNewWindow(fileURL: fileURL)
                }
            case .reveal:
                if let fileURL = document.fileURL {
                    directoryDocument.revealInFileBrowser(fileURL: fileURL)
                }
            case .move(let index):
                directoryDocument.moveTab(of: document, to: index)
        }
    }
    
    
    /// Updates the top bar when what it shows changes.
    private func observeTopBarState() {
        
        self.topBarObservers.removeAll()
        
        for item in [self.sidebarViewItem, self.inspectorViewItem].compactMap(\.self) {
            item.publisher(for: \.isCollapsed)
                .sink { [weak self] _ in self?.updateTopBar() }
                .store(in: &self.topBarObservers)
        }
        if let window = self.view.window {
            window.publisher(for: \.title)
                .sink { [weak self] _ in self?.updateTopBar() }
                .store(in: &self.topBarObservers)
            window.publisher(for: \.subtitle)
                .sink { [weak self] _ in self?.updateTopBar() }
                .store(in: &self.topBarObservers)
        }
        
        // a run starts and ends without a user event
        let runController = self.contentViewController.runController
        self.runObserver?.cancel()
        self.runObserver = Task { [weak self] in
            for await _ in Observations({ runController.isRunning }) {
                self?.updateTopBar()
            }
        }
    }
    
    
    /// How much of the window the sidebar and the inspector take up now, including while they open and close.
    private var columnWidths: TopBar.Columns {
        
        let width = self.view.bounds.width
        let isRightToLeft = (self.view.userInterfaceLayoutDirection == .rightToLeft)
        
        // the frame of a column measured from the leading edge, if it is on screen
        func frame(_ item: NSSplitViewItem?) -> NSRect? {
            guard
                let view = item?.viewController.viewIfLoaded,
                view.window != nil,
                !view.isHiddenOrHasHiddenAncestor
            else { return nil }
            
            var frame = self.view.convert(view.bounds, from: view)
            if isRightToLeft {
                frame.origin.x = width - frame.maxX
            }
            return frame
        }
        
        let leading = frame(self.sidebarViewItem).map { min(max($0.maxX, 0), width) } ?? 0
        let trailing = frame(self.inspectorViewItem).map { min(max(width - $0.minX, 0), width) } ?? 0
        
        return .init(leading: leading.rounded(), trailing: trailing.rounded())
    }
    
    
    /// Creates a menu that lists the document history in one direction.
    private func historyMenu(identifier: NSUserInterfaceItemIdentifier) -> NSMenu {
        
        let menu = NSMenu()
        menu.identifier = identifier
        menu.delegate = self
        
        return menu
    }
    
    
    /// Whether the sidebar can currently be toggled.
    private var canToggleSidebar: Bool {
        
        self.sidebarViewItem != nil && self.sidebarStateCache == nil
    }
    
    
    /// The localized tooltip to show when sidebar commands are unavailable.
    private var sidebarAvailabilityHint: String? {
        
        (self.sidebarViewItem == nil)
            ? String(localized: "The sidebar is only available when a folder is opened as a document.",
                     table: "MainMenu", comment: "tooltip for the “Show Sidebar” menu item")
            : nil
    }
    
    
    /// The view controller for the content view.
    private var contentViewController: ContentViewController {
        
        self.contentViewItem.viewController as! ContentViewController
    }
    
    
    /// The view controller for the sidebar.
    private var sidebarViewController: SidebarViewController? {
        
        self.sidebarViewItem?.viewController as? SidebarViewController
    }
    
    
    /// The view controller for the inspector.
    private var inspectorViewController: InspectorViewController {
        
        self.inspectorViewItem.viewController as! InspectorViewController
    }
    
    
    /// Returns whether the given pane in the sidebar is currently shown.
    ///
    /// - Parameter pane: The sidebar pane to check.
    /// - Returns: `true` when the pane is currently visible.
    private func isSidebarShown(pane: SidebarPane) -> Bool {
        
        self.sidebarViewItem?.isCollapsed != true && (self.sidebarViewController?.selectedPane == pane)
    }
    
    
    /// Returns whether the given pane in the inspector is currently shown.
    ///
    /// - Parameter pane: The inspector pane to check.
    /// - Returns: `true` when the pane is currently visible.
    private func isInspectorShown(pane: InspectorPane) -> Bool {
        
        !self.inspectorViewItem.isCollapsed && (self.inspectorViewController.selectedPane == pane)
    }
    
    
    /// Moves the focus to the editor.
    private func focusEditor() {
        
        guard
            let window = self.viewIfLoaded?.window,
            let textView = self.documentViewController?.focusedTextView
        else { return }
        
        window.makeFirstResponderDiscardingMarkedText(textView)
    }
    
    
    /// Updates the document in children.
    private func updateDocument() {
        
        self.contentViewController.document = self.document
        self.inspectorViewController.document = self.document
        self.statusBarModel.document = self.document
        
        if self.directoryDocument != nil {
            self.contentViewController.view.setAccessibilityLabel(self.document?.displayName ?? "")
        }
        
        self.updateTopBar()
    }
}


extension WindowContentViewController: NSMenuDelegate {
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        
        guard let directoryDocument else { return assertionFailure() }
        
        let forward = (menu.identifier == .forwardDocumentHistoryMenu)
        
        menu.items = directoryDocument.documentHistory.menuItems(forward: forward)
            .map { item in
                let menuItem = NSMenuItem(title: item.url.lastPathComponent,
                                          action: #selector(DirectoryDocument.jumpDocumentHistory),
                                          keyEquivalent: "")
                menuItem.target = directoryDocument
                menuItem.representedObject = item.index
                menuItem.image = item.icon
                menuItem.image?.size = NSSize(width: 16, height: 16)
                
                guard #available(macOS 27, *) else { return menuItem }
                
                menuItem.preferredImageVisibility = .visible
                
                return menuItem
            }
    }
}


private extension NSUserInterfaceItemIdentifier {
    
    static let backDocumentHistoryMenu = Self(rawValue: "backDocumentHistoryMenu")
    static let forwardDocumentHistoryMenu = Self(rawValue: "forwardDocumentHistoryMenu")
}


private extension DocumentHistory.Item {
    
    /// The document icon.
    var icon: NSImage {
        
        if let type = self.entry.fileType {
            NSWorkspace.shared.icon(for: type)
        } else {
            NSWorkspace.shared.icon(forFile: self.url.path)
        }
    }
}
