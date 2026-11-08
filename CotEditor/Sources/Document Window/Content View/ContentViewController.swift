//
//  ContentViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-05-04.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2026 1024jp
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

final class ContentViewController: NSViewController {
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument(from: oldValue) } }
    
    private(set) var hostedViewController: NSViewController
    
    /// The window's runs, which the Run panel shows. They outlive the hosted view controller, which is replaced
    /// when a folder window shows another document.
    let runController = RunController()
    
    
    // MARK: Private Properties
    
    /// The editor above and the Run panel below.
    private let splitViewController = NSSplitViewController()
    private let editorViewController = NSViewController()
    private var runPanelItem: NSSplitViewItem?
    
    private var windowCloseObserver: (any NSObjectProtocol)?
    
    
    // MARK: Lifecycle
    
    init(document: DataDocument?) {
        
        self.document = document
        self.hostedViewController = Self.viewController(document: document)
        
        super.init(nibName: nil, bundle: nil)
        
        self.editorViewController.addChild(self.hostedViewController)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }
    
    
    override func loadView() {
        
        let editorView = NSView()
        editorView.embedSubview(self.hostedViewController.view)
        self.editorViewController.view = editorView
        
        let runPanel = RunPanel(controller: self.runController,
                                run: { [weak self] in self?.runDocument(nil) },
                                hide: { [weak self] in self?.setRunPanelShown(false) })
        let runPanelController = NSHostingController(rootView: runPanel)
        runPanelController.sizingOptions = []
        
        let editorItem = NSSplitViewItem(viewController: self.editorViewController)
        let runPanelItem = NSSplitViewItem(viewController: runPanelController)
        runPanelItem.canCollapse = true
        runPanelItem.isCollapsed = true
        runPanelItem.minimumThickness = 90
        runPanelItem.holdingPriority = .init(251)  // above the editor’s, to keep its height when the window resizes
        self.runPanelItem = runPanelItem
        
        self.splitViewController.splitView.isVertical = false
        self.splitViewController.splitView.dividerStyle = .thin
        self.splitViewController.addSplitViewItem(editorItem)
        self.splitViewController.addSplitViewItem(runPanelItem)
        self.addChild(self.splitViewController)
        
        let view = NSView()
        view.embedSubview(self.splitViewController.view)
        
        self.view = view
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        // remember the Run panel's height and whether it's shown, for new windows
        // -> Set the `autosaveName` after the view is placed in the window, as WindowContentViewController does.
        let splitView = self.splitViewController.splitView
        if splitView.autosaveName == nil {
            splitView.identifier = NSUserInterfaceItemIdentifier("RunPanelSplitView")
            splitView.autosaveName = "RunPanelSplitView"
        }
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        // stop the window's runs when it closes
        if self.windowCloseObserver == nil, let window = self.view.window {
            self.windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.runController.stopAll()
                }
            }
        }
    }
    
    
    // MARK: Actions
    
    /// Saves the document and runs it.
    @IBAction func runDocument(_ sender: Any?) {
        
        guard let document = self.document as? TextDocument else { return }
        
        self.setRunPanelShown(true)
        
        if let fileURL = document.fileURL, !document.isDocumentEdited {
            self.run(document: document, fileURL: fileURL)
        } else {
            // an untitled document gets a Save panel; nothing runs if the user cancels it or the save fails
            document.save(withDelegate: self, didSave: #selector(document(_:didSave:contextInfo:)), contextInfo: nil)
        }
    }
    
    
    /// Stops the program that's running.
    @IBAction func stopRun(_ sender: Any?) {
        
        self.runController.stop()
    }
    
    
    /// Shows or hides the Run panel.
    @IBAction func toggleRunPanel(_ sender: Any?) {
        
        self.setRunPanelShown(self.runPanelItem?.isCollapsed == true)
    }
    
    
    // MARK: Private Methods
    
    /// Runs the saved document after `runDocument(_:)` saved it.
    @objc private func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        
        guard didSave, let document = document as? TextDocument, let fileURL = document.fileURL else { return }
        
        self.run(document: document, fileURL: fileURL)
    }
    
    
    /// Runs the saved file with the command for the document's syntax.
    private func run(document: TextDocument, fileURL: URL) {
        
        guard let command = RunCommand.command(syntaxName: document.syntaxName) else {
            let syntaxName = (document.syntaxName == SyntaxName.none)
                ? String(localized: "this document", table: "Run", comment: "used in place of the syntax name when the document has none")
                : document.syntaxName
            self.runController.show(notice: String(localized: "Graupel doesn’t know how to run \(syntaxName). Set a run command in Settings > Language Servers.", table: "Run"))
            return
        }
        
        Task {
            await self.runController.run(fileURL: fileURL, command: command)
        }
    }
    
    
    /// Shows or hides the Run panel.
    private func setRunPanelShown(_ isShown: Bool) {
        
        guard let runPanelItem = self.runPanelItem, runPanelItem.isCollapsed == isShown else { return }
        
        runPanelItem.animator().isCollapsed = !isShown
    }
    
    
    // MARK: Private Methods
    
    /// Updates the hosted view controller when the document changes.
    ///
    /// - Parameter oldDocument: The previous document.
    private func updateDocument(from oldDocument: DataDocument?) {
        
        guard oldDocument != self.document else { return }
        
        // remove only the hosted view controller to preserve accessories such as the status bar
        // -> Split view item accessory controllers can be attached as children (2026-05, macOS 26).
        self.hostedViewController.viewIfLoaded?.removeFromSuperview()
        self.hostedViewController.removeFromParent()
        
        self.hostedViewController = Self.viewController(document: self.document)
        self.editorViewController.addChild(self.hostedViewController)
        self.editorViewController.viewIfLoaded?.embedSubview(self.hostedViewController.view)
    }
    
    
    /// Creates a new view controller with the passed-in document.
    ///
    /// - Parameter document: The represented document.
    /// - Returns: A view controller.
    private static func viewController(document: DataDocument?) -> sending NSViewController {
        
        switch document {
            case let document as TextDocument:
                DocumentViewController(document: document)
            case let document as PreviewDocument:
                Self.hostingController(rootView: FilePreviewView(item: document))
            case .none:
                Self.hostingController(rootView: NoDocumentView())
            default:
                preconditionFailure()
        }
    }
    
    
    /// Creates a hosting controller that doesn’t propagate the SwiftUI content’s ideal size to the split view pane layout.
    ///
    /// - Parameter rootView: The SwiftUI view to host.
    /// - Returns: A hosting controller.
    private static func hostingController(rootView: some View) -> sending NSViewController {
        
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        
        return controller
    }
}


extension ContentViewController: NSMenuItemValidation {
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        switch menuItem.action {
            case #selector(runDocument):
                return self.document is TextDocument
            case #selector(stopRun):
                return self.runController.isRunning
            case #selector(toggleRunPanel):
                menuItem.title = (self.runPanelItem?.isCollapsed == false)
                    ? String(localized: "Hide Run Panel", table: "MainMenu", comment: "verb; menu item")
                    : String(localized: "Show Run Panel", table: "MainMenu", comment: "verb; menu item")
                return self.document is TextDocument
            default:
                return true
        }
    }
}


private extension NSView {
    
    /// Adds a subview constrained to fill the receiver.
    ///
    /// - Parameter subview: The subview to embed.
    func embedSubview(_ subview: NSView) {
        
        subview.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(subview)
        
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            subview.topAnchor.constraint(equalTo: self.topAnchor),
            subview.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }
}
