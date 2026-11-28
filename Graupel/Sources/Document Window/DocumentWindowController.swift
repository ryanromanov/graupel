//
//  DocumentWindowController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2004-12-13.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2013-2026 1024jp
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
import Combine
import SwiftUI
import Defaults
import ControlUI
import URLUtils

final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: Public Properties
    
    var isWhitePaper = false {
        
        didSet {
            guard isWhitePaper || oldValue else { return }
            
            self.setDocumentEdited(!isWhitePaper)
        }
    }
    
    
    @objc dynamic weak var fileDocument: DataDocument? {
        
        didSet {
            if fileDocument != oldValue {
                self.updateDocument(fileDocument)
            }
        }
    }
    
    
    /// The folder the window shows, if it’s a folder window.
    private(set) weak var directoryDocument: DirectoryDocument?
    
    
    // MARK: Private Properties
    
    private let isDirectoryDocument: Bool
    
    private let windowAutosaveName: NSWindow.FrameAutosaveName
    private var needsManualOnAppear = false
    private var uniqueDirectory: String?
    
    private lazy var editedIndicator: NSView = NSHostingView(rootView: EditedIndicator())
    
    private var opacityObserver: AnyCancellable?
    private var fileDocumentNameObserver: AnyCancellable?
    private var documentObservers: [NotificationCenter.ObservationToken] = []
    
    private var chromeObserver: Task<Void, Never>?
    
    
    // MARK: Lifecycle
    
    required init(document: DataDocument? = nil, directoryDocument: DirectoryDocument? = nil) {
        
        assert(document != nil || directoryDocument != nil)
        
        self.fileDocument = document
        self.directoryDocument = directoryDocument
        self.isDirectoryDocument = (directoryDocument != nil)
        
        // store own autosave name
        // -> `NSWindowController.windowFrameAutosaveName` doesn't work
        //    if multiple window instances have the same name (2024-10, macOS 15).
        self.windowAutosaveName = self.isDirectoryDocument ? "DirectoryDocument" : "Document"
        
        let viewController = WindowContentViewController(document: document, directoryDocument: directoryDocument)
        let window = DocumentWindow(contentViewController: viewController)
        window.styleMask.update(with: .fullSizeContentView)
        window.animationBehavior = .documentWindow
        window.setFrameAutosaveName(self.windowAutosaveName)
        window.setFrameUsingName(self.windowAutosaveName)
        
        if self.isDirectoryDocument {
            window.tabbingMode = .disallowed
        }
        
        // set window size
        if let frameSize = Self.userFrameSize(for: window) {
            window.setFrame(NSRect(origin: window.frame.origin, size: frameSize), display: false)
        }
        
        // cascade window position
        // -> Don't use `NSApp.mainWindow` since it returns `nil` when the app is inactive. (2025-04)
        if let lastWindow = NSApp.orderedDocuments.lazy
            .compactMap(\.windowControllers.first?.window)
            .first(where: \.isVisible)
        {
            let referenceFrame = lastWindow.cascadingReferenceFrame
            let cascadingPoint = window.cascadeTopLeft(from: referenceFrame.topLeft)
            window.cascadeTopLeft(from: cascadingPoint)
        }
        
        super.init(window: window)
        
        self.updateDocument(document)
        
        window.delegate = self
        
        // the top bar stands in for the title and the toolbar
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.installTitleBarSpacer()
        
        // observe opacity setting change
        // -> Keep opaque when the window was created as a browsing window (the right side ones in the browsing mode).
        if document?.isInViewingMode != true {
            self.opacityObserver = UserDefaults.standard.publisher(for: .windowAlpha, initial: true)
                .assign(to: \.backgroundAlpha, on: window)
        }
        
        // observe the window theme to restyle the window
        if let chrome = (window.contentViewController as? WindowContentViewController)?.chrome {
            self.chromeObserver = Task { [weak self] in
                for await _ in Observations({ chrome.revision }) {
                    self?.applyChrome(chrome.style)
                }
            }
        }
        
        // observe documents to update window title
        self.documentObservers = [
            NotificationCenter.default.addObserver(for: NSDocument.DidChangeFileURLMessage.self) { [weak self] _ in self?.invalidateUniqueDirectory() },
            NotificationCenter.default.addObserver(for: NSDocument.DidMakeWindowMessage.self) { [weak self] _ in self?.invalidateUniqueDirectory() },
        ]
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        self.chromeObserver?.cancel()
    }
    
    
    // MARK: Window Controller Methods
    
    override unowned(unsafe) var document: AnyObject? {
        
        didSet {
            if let document = document as? DataDocument {
                self.fileDocument = document
            }
        }
    }
    
    
    override func setDocumentEdited(_ dirtyFlag: Bool) {
        
        self.window?.tab.accessoryView = dirtyFlag ? self.editedIndicator : nil
        
        super.setDocumentEdited(self.isWhitePaper ? false : dirtyFlag)
        
        self.updateTopBar()
    }
    
    
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        
        if let uniqueDirectory {
            displayName + " \u{2014} " + uniqueDirectory  // EM DASH
        } else {
            displayName
        }
    }
    
    
    override func synchronizeWindowTitleWithDocumentName() {
        
        super.synchronizeWindowTitleWithDocumentName()
        
        if self.isDirectoryDocument {
            // display current document title as window subtitle
            self.window?.subtitle = self.fileDocument?.fileURL?.lastPathComponent
                ?? self.fileDocument?.displayName
                ?? ""
        }
    }
    
    
    // MARK: Window Delegate
    
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        
        guard let frameSize = Self.userFrameSize(for: window) else { return newFrame }
        
        var frame = window.frame
        if frameSize.width != frame.width {
            frame.size.width = frameSize.width
        }
        
        if frameSize.height != frame.height {
            frame.origin.y = frame.minY - (frameSize.height - frame.height)
            frame.size.height = frameSize.height
        }
        
        return (frame.size != newFrame.size) ? frame : newFrame
    }
    
    
    func windowDidResize(_ notification: Notification) {
        
        self.saveWindowFrame()
    }
    
    
    func windowDidMove(_ notification: Notification) {
        
        self.saveWindowFrame()
    }
    
    
    func windowWillMiniaturize(_ notification: Notification) {
        
        // Workaround issue `viewWillAppear()` and `viewDidAppear()` are not invoked
        // on de-miniaturization when the window was initially miniaturized (2024-10, macOS 15, FB15331763)
        if self.window?.isVisible == false {
            self.needsManualOnAppear = true
        }
    }
    
    
    func windowDidDeminiaturize(_ notification: Notification) {
        
        if self.needsManualOnAppear {
            self.contentViewController?.performOnAppearProcedure()
            self.needsManualOnAppear = false
        }
    }
    
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        
        self.window?.isOpaque = true
        
        // in full screen, even an empty toolbar covers the top of the window
        self.window?.toolbar = nil
        (self.contentViewController as? WindowContentViewController)?.setFullScreen(true)
    }
    
    
    func windowDidExitFullScreen(_ notification: Notification) {
        
        self.restoreTitleBar()
    }
    
    
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        
        self.restoreTitleBar()
        self.restoreWindowOpacity()
    }
    
    
    func windowWillEnterVersionBrowser(_ notification: Notification) {
        
        self.window?.isOpaque = true
    }
    
    
    func windowWillExitFullScreen(_ notification: Notification) {
        
        self.restoreWindowOpacity()
    }
    
    
    func windowWillExitVersionBrowser(_ notification: Notification) {
        
        self.restoreWindowOpacity()
    }
    
    
    // MARK: Public Methods
    
    /// Updates the contents of the top bar.
    func updateTopBar() {
        
        (self.contentViewController as? WindowContentViewController)?.updateTopBar()
    }
    
    
    // MARK: Private Methods
    
    /// Restores the title bar after full screen.
    private func restoreTitleBar() {
        
        (self.window as? DocumentWindow)?.installTitleBarSpacer()
        (self.contentViewController as? WindowContentViewController)?.setFullScreen(false)
    }
    
    
    /// Returns the user-defined frame size for the given window, if set.
    ///
    /// - Parameter window: The window to calculate the user-defined frame size for.
    /// - Returns: The user-defined frame size, or `nil` if no size is set.
    private static func userFrameSize(for window: NSWindow) -> NSSize? {
        
        let minSize = NSSize(width: max(window.minSize.width, 1),
                             height: max(window.minSize.height, 1))
        
        let width = UserDefaults.standard[.windowWidth]
            .flatMap { $0 > 0 ? max($0, minSize.width) : nil }
        let height = UserDefaults.standard[.windowHeight]
            .flatMap { $0 > 0 ? max($0, minSize.height) : nil }
        
        guard width != nil || height != nil else { return nil }
        
        return NSSize(width: width ?? window.frame.width,
                      height: height ?? window.frame.height)
    }
    
    
    /// Updates document by passing it to the content view controller and updating the observation.
    ///
    /// - Parameter document: The new document.
    private func updateDocument(_ document: DataDocument?) {
        
        if let viewController = self.contentViewController as? WindowContentViewController, viewController.document != document {
            viewController.document = document
        }
        
        self.fileDocumentNameObserver = nil
        if self.isDirectoryDocument {
            self.fileDocumentNameObserver = document?.publisher(for: \.fileURL, options: .initial)
                .sink { [weak self] _ in self?.synchronizeWindowTitleWithDocumentName() }
        }
        
        // update the window title for the new document
        // -> NSWindowController synchronizes the title before `fileDocument` is updated.
        self.synchronizeWindowTitleWithDocumentName()
    }
    
    
    /// Saves the current window frame.
    ///
    /// Workaround the issue that window frame is not saved automatically.
    private func saveWindowFrame() {
        
        assert(self.isWindowLoaded)
        
        self.window?.saveFrame(usingName: self.windowAutosaveName)
    }
    
    
    /// Restores the window opacity.
    private func restoreWindowOpacity() {
        
        (self.window as? DocumentWindow)?.applyBackgroundOpacity()
    }
    
    
    /// Updates `uniqueDirectory`.
    private func invalidateUniqueDirectory() {
        
        // apply unique folder name to the window title
        let fileURLs = NSApp.windows
            .compactMap(\.windowController)
            .compactMap { $0.document as? NSDocument }
            .compactMap(\.fileURL)
        
        let uniqueDirectory = (self.document as? NSDocument)?.fileURL?
            .firstUniqueDirectoryURL(in: fileURLs)
            .map { FileManager.default.displayName(atPath: $0.path(percentEncoded: false)) }
        
        guard uniqueDirectory != self.uniqueDirectory else { return }
        
        self.uniqueDirectory = uniqueDirectory
        self.synchronizeWindowTitleWithDocumentName()
    }
}


private extension NSViewController {
    
    /// Recursively invokes `viewWillAppear()` and `viewDidAppear()`.
    ///
    /// Workaround the issue `viewWillAppear()` and `viewDidAppear()` are not invoked
    /// on de-miniaturization when the window was initially miniaturized (2024-10, macOS 15, FB15331763).
    func performOnAppearProcedure() {
        
        // proceed only when the view is shown
        guard self.viewIfLoaded?.isHiddenOrHasHiddenAncestor == false else { return }
        
        self.viewWillAppear()
        self.viewDidAppear()
        
        for child in self.children {
            child.performOnAppearProcedure()
        }
    }
}


// MARK: - Chrome

private extension DocumentWindowController {
    
    /// Restyles the window to match the window theme.
    ///
    /// - Parameter style: The style of the chrome, or `nil` for the system style.
    func applyChrome(_ style: ChromeStyle?) {
        
        guard let window = self.window as? DocumentWindow else { return }
        
        window.chromeBackgroundColor = style?.background
        self.updateWindowAppearance()
        // update the views that read the chrome colors themselves
        window.contentView?.updateChromeColorsInSubtree()
    }
    
    
    /// Sets the window’s appearance, which draws the text of the bars and panes.
    ///
    /// The window is painted in the window theme’s colors, so the appearance has to match how dark the theme is.
    func updateWindowAppearance() {
        
        guard let window = self.window as? DocumentWindow else { return }
        
        let themeAppearance = window.chrome?.style.flatMap { NSAppearance(named: $0.isDark ? .darkAqua : .aqua) }
        
        window.appearance = themeAppearance
    }
}


// MARK: - Views

private struct EditedIndicator: View {
    
    var body: some View {
        
        Circle()
            .fill(.tertiary)
            .frame(width: 4, height: 4)
            .padding(8)
            .help(.init("Document has unsaved changes",
                        table: "Document",
                        comment: "tooltip for the “edited” indicator in the window tab"))
    }
}


/// A view that sets colors from the window chrome on its subviews, so redrawing it isn’t enough.
protocol ChromeColoring: NSView {
    
    func updateChromeColors()
}


private extension NSView {
    
    /// Updates the chrome colors of the view and all its subviews, and redraws them.
    func updateChromeColorsInSubtree() {
        
        (self as? any ChromeColoring)?.updateChromeColors()
        self.needsDisplay = true
        self.subviews.forEach { $0.updateChromeColorsInSubtree() }
    }
}
