//
//  DirectoryDocument.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-05-01.
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
import UniformTypeIdentifiers
import Defaults
import DocumentFile
import SyntaxFormat
import URLUtils

final class DirectoryDocument: NSDocument {
    
    private enum SerializationKey {
        
        static let currentDocument = "currentDocument"
        static let tabs = "tabs"
        static let tabsAsPlainText = "tabsAsPlainText"
        static let previewTab = "previewTab"
    }
    
    
    // MARK: Public Properties
    
    private(set) var fileNode: FileNode?
    /// The documents open in the window, each in a tab.
    private(set) var tabs = DocumentTabs<DataDocument>()  { didSet { self.invalidateTabs() } }
    /// Called when the tabs or what they show change, to update the window.
    var tabsDidChange: (() -> Void)?
    /// The document of the selected tab.
    var currentDocument: DataDocument?  { self.tabs.selection }
    var documentHistory = DocumentHistory()  { didSet { self.documentHistoryDidChange?() } }
    /// Called when the history changes, to update the window’s Back and Forward buttons.
    var documentHistoryDidChange: (() -> Void)?
    
    weak var fileBrowserViewController: FileBrowserViewController?
    
    
    // MARK: Private Properties
    
    private weak var windowController: DocumentWindowController?
    
    private var documentObservers: [NotificationCenter.ObservationToken] = []
    
    
    // MARK: Document Methods
    
    override nonisolated static var autosavesInPlace: Bool {
        
        true  // for moving location from the proxy icon
    }
    
    
    override nonisolated var fileURL: URL? {
        
        didSet {
            Task { @MainActor in
                NotificationCenter.default.post(NSDocument.DidChangeFileURLMessage(), subject: self)
            }
        }
    }
    
    
    override func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) {
        
        var bookmarks: [NSData] = []
        var asPlainText: [NSNumber] = []
        for document in self.tabs.items {
            guard
                let fileURL = document.fileURL,
                let bookmarkData = try? fileURL.bookmarkData(options: .withSecurityScope)
            else { continue }
            
            if document == self.tabs.selection {
                coder.encode(bookmarkData, forKey: SerializationKey.currentDocument)
            }
            if document == self.tabs.preview {
                coder.encode(bookmarks.count, forKey: SerializationKey.previewTab)
            }
            bookmarks.append(bookmarkData as NSData)
            asPlainText.append(NSNumber(value: self.opensAsPlainText(document)))
        }
        coder.encode(bookmarks as NSArray, forKey: SerializationKey.tabs)
        coder.encode(asPlainText as NSArray, forKey: SerializationKey.tabsAsPlainText)
        
        // -> Call this last, since it goes on writing to the coder in the background queue.
        super.encodeRestorableState(with: coder, backgroundQueue: queue)
    }
    
    
    override func restoreState(with coder: NSCoder) {
        
        super.restoreState(with: coder)
        
        guard let fileURL else { return }
        
        func resolve(_ bookmarkData: NSData) -> URL? {
            var isStale = false
            guard
                let url = try? URL(resolvingBookmarkData: bookmarkData as Data, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
                fileURL.isAncestor(of: url),
                url.isReachable
            else { return nil }
            
            return url
        }
        
        // restore the tabs, and then show the one that was selected
        let selectedURL = coder.decodeObject(of: NSData.self, forKey: SerializationKey.currentDocument).flatMap(resolve)
        let bookmarks = coder.decodeArrayOfObjects(ofClass: NSData.self, forKey: SerializationKey.tabs) ?? []
        let asPlainText = coder.decodeArrayOfObjects(ofClass: NSNumber.self, forKey: SerializationKey.tabsAsPlainText) ?? []
        let previewIndex = coder.containsValue(forKey: SerializationKey.previewTab)
            ? coder.decodeInteger(forKey: SerializationKey.previewTab)
            : nil
        let entries = bookmarks.enumerated().compactMap { index, bookmark in
            resolve(bookmark).map { url in
                (url: url,
                 asPlainText: asPlainText.indices.contains(index) && asPlainText[index].boolValue,
                 isPreview: index == previewIndex)
            }
        }
        
        Task {
            for entry in entries {
                await self.openDocument(at: entry.url, asPlainText: entry.asPlainText, keeps: !entry.isPreview,
                                        recordsHistory: false)
            }
            // -> Only the selected document was saved before the window had tabs.
            if let selectedURL {
                await self.openDocument(at: selectedURL)
            }
            self.fileBrowserViewController?.selectCurrentDocument()
        }
    }
    
    
    override func makeWindowControllers() {
        
        let windowController = DocumentWindowController(directoryDocument: self)
        self.windowController = windowController
        self.addWindowController(windowController)
        
        NotificationCenter.default.post(DidMakeWindowMessage(), subject: self)
        
        // observe document updates for the tabs and the edited marker in the close button
        if self.documentObservers.isEmpty {
            self.documentObservers = [
                NotificationCenter.default.addObserver(for: TextDocument.DidUpdateChangeMessage.self) { [weak self] _ in
                    self?.documentsDidUpdate()
                },
                NotificationCenter.default.addObserver(for: NSDocument.DidChangeFileURLMessage.self) { [weak self] _ in
                    self?.tabsDidChange?()
                },
            ]
        }
    }
    
    
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        
        assert(url == self.fileURL)
        
        let file = try File(at: url)
        
        MainActor.assumeIsolated {
            self.fileNode = FileNode(file: file)
            self.windowController?.synchronizeWindowTitleWithDocumentName()
        }
    }
    
    
    @available(*, unavailable)
    override func data(ofType typeName: String) throws -> Data {
        
        fatalError("\(self.className) is readonly")
    }
    
    
    override func move(to url: URL) async throws {
        
        try await super.move(to: url)
        
        // remake node tree
        self.fileNode?.move(to: url)
        self.notifyNodeUpdate(at: self.fileNode)
    }
    
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        
        try super.revert(toContentsOf: url, ofType: typeName)
        
        self.notifyNodeUpdate(at: self.fileNode)
    }
    
    
    override func shouldCloseWindowController(_ windowController: NSWindowController, delegate: Any?, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        
        Task {
            // save unsaved changes in the file documents before closing
            var canClose = true
            for document in self.tabs.items where document.isDocumentEdited {
                // ask to the user one-by-one
                guard await self.confirmClosing(document) else {
                    canClose = false
                    break
                }
            }
            
            DelegateContext(delegate: delegate, selector: shouldCloseSelector, contextInfo: contextInfo).perform(from: self, flag: canClose)
        }
    }
    
    
    override func close() {
        
        super.close()
        
        for document in self.tabs.items {
            document.windowController = nil
            document.close()
        }
        
        self.documentObservers.removeAll()
    }
    
    
    // MARK: File Presenter Methods
    
    override nonisolated func presentedSubitemDidChange(at url: URL) {
        
        // the following APIs are not called correctly:
        // - subitem moved (presentedSubitem(at:didMoveTo:))
        // - new subitem added (presentedSubitemDidAppear(at:))
        
        // remake node tree if needed
        Task { @MainActor in
            guard let node = self.fileNode?.invalidateChildren(at: url) else { return }
            
            self.notifyNodeUpdate(at: node)
        }
    }
    
    
    override nonisolated func presentedItemDidMove(to newURL: URL) {
        
        super.presentedItemDidMove(to: newURL)
        
        // remake fileURLs with the new location
        Task { @MainActor in
            self.fileNode?.move(to: newURL)
            self.notifyNodeUpdate(at: self.fileNode)
        }
    }
    
    
    // MARK: Action Messages
    
    /// Opens the selected file as plain text, bypassing type detection.
    @IBAction func openDocumentAsPlainText(_ sender: NSMenuItem) {
        
        guard let fileURL = sender.representedObject as? URL else { return }
        
        Task {
            await self.openDocument(at: fileURL, asPlainText: true, keeps: true)
        }
    }
    
    
    /// Opens the link destination of selected file as plain text.
    @IBAction func openOriginalDocumentAsPlainText(_ sender: NSMenuItem) {
        
        guard let fileURL = sender.representedObject as? URL else { return }
        
        assert((try? fileURL.isDirectory) != true)
        
        var resolvedURL: URL
        do {
            resolvedURL = try URL(resolvingAliasFileAt: fileURL)
            try resolvedURL.grantAccess()
        } catch is CancellationError {
            return
        } catch {
            return self.presentErrorAsSheet(error)
        }
        
        Task {
            await self.openDocument(at: resolvedURL, asPlainText: true, keeps: true)
        }
    }
    
    
    // MARK: Public Methods
    
    /// Returns the opened document at the given file node.
    ///
    /// - Parameter node: The file node to find.
    /// - Returns: A document if found.
    func openedDocument(at node: FileNode) -> DataDocument? {
        
        self.tabs.items.first { $0.fileURL == node.file.fileURL }
    }
    
    
    /// Opens a document as a member, in a tab.
    ///
    /// This method opens the alias destination instead, only if the URL already has permission.
    ///
    /// - Parameters:
    ///   - fileURL: The file URL of the document to open.
    ///   - asPlainText: If `true`, the document is forcibly opened as a plain text file.
    ///   - prefersOriginal: If `true`, opens the alias destination only if the URL already has permission. Otherwise, opens the original file.
    ///   - keeps: If `true`, the tab stays open. Otherwise, a new tab is a preview that the next one replaces.
    ///   - recordsHistory: If `true`, records the opened document in the document history.
    /// - Returns: Return `true` if the document of the given file did successfully open.
    @discardableResult func openDocument(at fileURL: URL, asPlainText: Bool = false, prefersOriginal: Bool = false, keeps: Bool = false, recordsHistory: Bool = true) async -> Bool {
        
        // open alias target if the URL already has permission
        var fileURL = fileURL
        if prefersOriginal,
           let resolvedURL = try? URL(resolvingAliasFileAt: fileURL),
           (try? resolvedURL.isReadable) == true
        {
            fileURL = resolvedURL
        }
        
        // already open in a tab
        let openedDocument = self.tabs.items.first { $0.fileURL == fileURL }
        if let openedDocument, !asPlainText || openedDocument is TextDocument {
            if keeps {
                self.keepTab(of: openedDocument)
            }
            if openedDocument != self.currentDocument {
                self.show(openedDocument, recordsHistory: recordsHistory)
            }
            return true
        }
        
        // open in another window
        if openedDocument == nil, let document = NSDocumentController.shared.document(for: fileURL) as? TextDocument {
            return await withCheckedContinuation { continuation in
                self.presentErrorAsSheet(DirectoryDocumentError.alreadyOpen(fileURL)) { _ in
                    document.showWindows()
                    continuation.resume(returning: false)
                }
            }
        }
        
        let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        
        // make document
        let newDocument: NSDocument
        do {
            newDocument = (asPlainText || Self.shouldOpen(url: fileURL, ofType: contentType))
                ? try NSDocumentController.shared.makeDocument(withContentsOf: fileURL, ofType: contentType.identifier)
                : try PreviewDocument(contentsOf: fileURL, ofType: contentType.identifier)
        } catch {
            self.presentErrorAsSheet(error)
            return false
        }
        
        guard let document = newDocument as? DataDocument else { return false }
        
        document.hostWindowController = self.windowController
        NSDocumentController.shared.addDocument(document)
        
        let replacedDocument: DataDocument?
        if let openedDocument {
            // a preview of the file gives way to its text
            self.tabs.replace(openedDocument, with: document)
            self.tabs.select(document)
            replacedDocument = openedDocument
        } else {
            // never replace a preview that has changes
            if let preview = self.tabs.preview, preview.hasChanges {
                self.keepTab(of: preview)
            }
            replacedDocument = self.tabs.open(document, asPreview: !keeps)
        }
        self.show(document, recordsHistory: recordsHistory)
        replacedDocument.map(self.discard)
        
        return true
    }
    
    
    /// Shows the document of a tab.
    ///
    /// - Parameters:
    ///   - document: The document to show.
    ///   - recordsHistory: If `true`, records the document in the document history.
    func show(_ document: DataDocument, recordsHistory: Bool = true) {
        
        guard self.tabs.items.contains(document) else { return assertionFailure() }
        
        self.tabs.select(document)
        self.displaySelectedDocument()
        
        if recordsHistory {
            self.recordDocumentHistory(document: document, opensAsPlainText: self.opensAsPlainText(document))
        }
    }
    
    
    /// Makes the preview tab of the document stay open.
    func keepTab(of document: DataDocument) {
        
        guard self.tabs.preview == document else { return }
        
        self.tabs.keep(document)
    }
    
    
    /// Moves the tab of the document.
    func moveTab(of document: DataDocument, to index: Int) {
        
        self.tabs.move(document, to: index)
    }
    
    
    /// Closes the tab of the document, saving its changes or asking about them first.
    ///
    /// - Returns: `false` if the user canceled.
    @discardableResult func closeTab(of document: DataDocument) async -> Bool {
        
        guard self.tabs.items.contains(document) else { return true }
        
        if document.hasChanges {
            guard await self.confirmClosing(document) else { return false }
        }
        
        // -> The tab may have gone while the user was asked.
        guard self.tabs.items.contains(document) else { return true }
        
        self.removeTab(of: document)
        self.discard(document)
        self.documentsDidUpdate()
        
        return true
    }
    
    
    /// Closes all the tabs but that of the document, until the user cancels.
    func closeTabs(except document: DataDocument) async {
        
        for other in self.tabs.items where other != document {
            guard await self.closeTab(of: other) else { return }
        }
    }
    
    
    /// Creates an empty file in the given file node.
    ///
    /// - Parameter parentNode: The file node where creates a new file.
    /// - Returns: The file node created.
    @discardableResult func addFile(at parentNode: FileNode) throws -> FileNode {
        
        assert(parentNode.file.isDirectory)
        
        let name = String(localized: "Untitled", comment: "default name")
        let pathExtension = (try? SyntaxManager.shared.setting(name: UserDefaults.standard[.syntax]))?.fileMap.extensions?.first
        let fileURL = parentNode.file.fileURL.appending(component: name).appendingPathExtension(pathExtension ?? "").appendingUniqueNumber()
        
        var coordinationError: NSError?
        var writingError: any Error?
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: fileURL, error: &coordinationError) { newURL in
            do {
                try Data().write(to: newURL, options: .withoutOverwriting)
            } catch {
                writingError = error
            }
        }
        
        if let error = coordinationError ?? writingError {
            throw error
        }
        
        let file = File(at: fileURL, isDirectory: false)
        let node = FileNode(file: file, parent: parentNode)
        parentNode.addNode(node)
        
        return node
    }
    
    
    /// Creates a folder at the same level in the given file node.
    ///
    /// - Parameter parentNode: The file node where creates a new file.
    /// - Returns: The file node created.
    @discardableResult func addFolder(at parentNode: FileNode) throws -> FileNode {
        
        assert(parentNode.file.isDirectory)
        
        let name = String(localized: "untitled folder", comment: "default folder name for new creation")
        let folderURL = parentNode.file.fileURL.appending(component: name).appendingUniqueNumber()
        
        var coordinationError: NSError?
        var writingError: any Error?
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: folderURL, error: &coordinationError) { newURL in
            do {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
            } catch {
                writingError = error
            }
        }
        
        if let error = coordinationError ?? writingError {
            throw error
        }
        
        let file = File(at: folderURL, isDirectory: true)
        let node = FileNode(file: file, parent: parentNode)
        parentNode.addNode(node)
        
        return node
    }
    
    
    /// Renames the file at the given `fileURL` with a new name.
    ///
    /// - Parameters:
    ///   - node: The file node to rename.
    ///   - name: The new filename.
    func renameItem(at node: FileNode, with name: String) throws {
        
        // validate new name
        guard name.utf8.count <= Int(NAME_MAX) else {
            throw InvalidNameError.tooLong
        }
        guard !name.isEmpty else {
            throw InvalidNameError.empty
        }
        guard !name.contains("/") else {
            throw InvalidNameError.invalidCharacter("/")
        }
        guard !name.contains(":") else {
            throw InvalidNameError.invalidCharacter(":")
        }
        guard !name.contains(where: \.isNewline) else {
            throw InvalidNameError.newLine
        }
        
        let openedDocument = self.openedDocument(at: node)
        let newURL = node.file.fileURL.deletingLastPathComponent().appending(component: name)
        
        do {
            try self.moveFile(from: node.file.fileURL, to: newURL)
        } catch let error as CocoaError where error.errorCode == CocoaError.fileWriteFileExists.rawValue {
            throw InvalidNameError.duplicated(name: name)
        } catch {
            throw error
        }
        
        if let document = openedDocument as? TextDocument {
            // -> At this point, the document hasn’t updated its fileURL yet.
            document.invalidateSyntax(filename: name)
        }
        
        node.rename(with: name)
    }
    
    
    /// Moves the file node to another file node.
    ///
    /// - Parameters:
    ///   - node: The node to move.
    ///   - destinationNode: The new parent node.
    func moveItem(at node: FileNode, to destinationNode: FileNode) throws {
        
        assert(destinationNode.file.isDirectory)
        
        let destinationURL = destinationNode.file.fileURL.appending(component: node.file.name)
            .appendingUniqueNumber()
        try self.moveFile(from: node.file.fileURL, to: destinationURL)
        
        node.move(to: destinationNode, fileURL: destinationURL)
    }
    
    
    /// Copies the file at the given `fileURL` to the given node.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of the source file.
    ///   - destinationNode: The destination parent node.
    /// - Returns: The file node created.
    func copyItem(at fileURL: URL, to destinationNode: FileNode) throws -> FileNode {
        
        assert(destinationNode.file.isDirectory)
        
        let destinationURL = destinationNode.file.fileURL.appending(component: fileURL.lastPathComponent)
            .appendingUniqueNumber()
        
        try self.copyFile(from: fileURL, to: destinationURL)
        
        let file = try File(at: destinationURL)
        let node = FileNode(file: file, parent: destinationNode)
        destinationNode.addNode(node)
        
        return node
    }
    
    
    /// Duplicates the file/folder at the given `fileURL`.
    ///
    /// - Parameters:
    ///   - node: The file node to duplicate.
    /// - Returns: The file node created.
    func duplicateItem(at node: FileNode) throws -> FileNode {
        
        let format = NumberingFormat { base in
            String(localized: "FileCopyFormat.single", defaultValue: "\(base) copy",
                   comment: "duplicated form of filename")
        } numbered: { base, count in
            String(localized: "FileCopyFormat.numbered", defaultValue: "\(base) copy \(count)",
                   comment: "duplicated form of filename with number")
        }
        let duplicatedURL = node.file.fileURL.appendingUniqueNumber(format: format)
        
        try self.copyFile(from: node.file.fileURL, to: duplicatedURL)
        
        let file = try File(at: duplicatedURL)
        let duplicatedNode = FileNode(file: file, parent: node.parent)
        node.parent?.addNode(duplicatedNode)
        
        return duplicatedNode
    }
    
    
    /// Properly moves the item to the trash.
    ///
    /// - Parameters:
    ///   - node: The file node to move to the Trash.
    func trashItem(_ node: FileNode) throws {
        
        let documentsToClose = self.tabs.items.filter { document in
            guard let fileURL = document.fileURL else { return false }
            
            return fileURL == node.file.fileURL || node.file.fileURL.isAncestor(of: fileURL)
        }
        
        var trashedURL: NSURL?
        var coordinationError: NSError?
        var trashError: any Error?
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: node.file.fileURL, options: .forDeleting, error: &coordinationError) { newURL in
            do {
                try FileManager.default.trashItem(at: newURL, resultingItemURL: &trashedURL)
            } catch {
                trashError = error
            }
        }
        
        if let error = coordinationError ?? trashError {
            throw error
        }
        
        guard trashedURL != nil else {
            assertionFailure("This guard should success.")
            throw CocoaError(.fileWriteUnknown)
        }
        
        for document in documentsToClose {
            self.removeTab(of: document)
            self.discard(document)
        }
        
        node.removeFromParent()
        
        if !documentsToClose.isEmpty {
            self.documentsDidUpdate()
        }
    }
    
    
    /// Reveals a file in the file browser.
    ///
    /// - Parameter fileURL: The file URL to reveal.
    func revealInFileBrowser(fileURL: URL) {
        
        guard let fileBrowserViewController else { return assertionFailure() }
        
        (self.windowController?.contentViewController as? WindowContentViewController)?.showFileBrowser(nil)
        
        guard fileBrowserViewController.revealFile(at: fileURL) else {
            return self.presentErrorAsSheet(CocoaError.error(.fileNoSuchFile, url: fileURL))
        }
    }
    
    
    /// Opens the document at a given file URL in a new window.
    ///
    /// - Parameter fileURL: The file URL to open.
    func openInNewWindow(fileURL: URL) {
        
        guard let node = self.fileNode?.node(at: fileURL) else {
            NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { [weak self] _, _, error in
                if let error {
                    self?.presentError(error)
                }
            }
            return
        }
        
        self.openInWindow(at: node)
    }
    
    
    /// Open the document at a given fileURL in a new window.
    ///
    /// If the file is an alias, this method tries to open the linked URL instead.
    ///
    /// - Parameter node: The file node to open.
    func openInWindow(at node: FileNode) {
        
        var fileURL = node.file.fileURL
        
        if node.file.isAlias {
            do {
                fileURL = try URL(resolvingAliasFileAt: fileURL)
                try fileURL.grantAccess(isDirectory: node.file.isFolder)
            } catch is CancellationError {
                return
            } catch {
                // let NSDocumentController handle the error
            }
        }
        
        if let document = self.tabs.items.first(where: { $0.fileURL == fileURL }) {
            // detach the document from the receiver
            self.removeTab(of: document)
            self.documentsDidUpdate()
            
            if let document = document as? TextDocument {
                // create a new window for the document
                document.hostWindowController = nil
                document.makeWindowControllers()
                document.showWindows()
                return
            }
            
            // reopen the file as a normal document
            // -> A PreviewDocument cannot create its own window.
            document.close()
        }
        
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { [weak self] _, _, error in
            if let error {
                self?.presentError(error)
            }
        }
    }
    
    
    /// Opens the item in the document history.
    ///
    /// - Parameter item: The history item to open.
    func openDocumentHistoryItem(_ item: DocumentHistory.Item) async {
        
        let didOpen = await self.openDocument(at: item.url, asPlainText: item.entry.opensAsPlainText, recordsHistory: false)
        
        guard didOpen else { return }
        
        self.documentHistory.select(item)
        self.fileBrowserViewController?.selectCurrentDocument()
    }
    
    
    // MARK: Private Methods
    
    /// Returns whether the receiver should open a file at the given URL as a text-plain file.
    ///
    /// - Parameters:
    ///   - url: The file URL.
    ///   - type: The file's content type.
    /// - Returns: `true` if the file should be opened as a plain-text.
    private static func shouldOpen(url: URL, ofType type: UTType) -> Bool {
        
        if type.conforms(to: .text) { return true }
        
        // symbolic link and alias file
        if type.conforms(to: .resolvable) { return false }
        
        if type.conforms(to: .unixExecutable) { return false }
        
        if type.conforms(to: .propertyList) {
            // detect binary property list from the magic number
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return true }
            
            return !data.starts(with: "bplist".utf8)
        }
        
        // check the default app for the file is CotEditor
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
           let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier,
           bundleIdentifier == Bundle.main.bundleIdentifier
        {
            return true
        }
        
        if SyntaxManager.shared.settingName(documentName: url.lastPathComponent) != nil { return true }
        
        return url.pathExtension.isEmpty
    }
    
    
    /// Notifies file node update to the UI.
    ///
    /// - Parameter node: The node whose children were changed.
    private func notifyNodeUpdate(at node: FileNode?) {
        
        guard let node else { return }
        
        self.fileBrowserViewController?.didUpdateNode(at: node)
    }
    
    
    /// Puts the document of the selected tab in the window.
    private func displaySelectedDocument() {
        
        // -> Without a window, a document would make one of its own.
        guard let windowController else { return }
        
        let document = self.currentDocument
        
        // remove window controller from the document shown until now
        if let shownDocument = windowController.fileDocument, shownDocument != document {
            shownDocument.windowController = nil
        }
        
        document?.windowController = windowController
        windowController.fileDocument = document
        document?.makeWindowControllers()
        
        self.fileBrowserViewController?.selectCurrentDocument()
    }
    
    
    /// Takes the tab of the document out of the window, without closing the document.
    private func removeTab(of document: DataDocument) {
        
        self.tabs.close(document)
        self.displaySelectedDocument()
        document.windowController = nil
    }
    
    
    /// Closes a document that has no tab anymore.
    private func discard(_ document: DataDocument) {
        
        assert(!self.tabs.items.contains(document))
        
        document.windowController = nil
        document.close()
    }
    
    
    /// Saves the changes of the document or asks the user about them.
    ///
    /// - Returns: `true` if the document can be closed.
    private func confirmClosing(_ document: DataDocument) async -> Bool {
        
        // show the document the question is about
        // -> A document that saves itself doesn’t ask in the usual case.
        if !type(of: document).autosavesInPlace {
            self.show(document, recordsHistory: false)
        }
        
        return await document.canClose()
    }
    
    
    /// Keeps the tabs and the window in step with the documents.
    private func documentsDidUpdate() {
        
        // a preview stays open once it's edited
        if let preview = self.tabs.preview, preview.isDocumentEdited {
            self.keepTab(of: preview)
        }
        
        self.windowController?.setDocumentEdited(self.tabs.items.contains(where: \.isDocumentEdited))
        self.tabsDidChange?()
    }
    
    
    private func invalidateTabs() {
        
        self.invalidateRestorableState()
        self.tabsDidChange?()
    }
    
    
    /// Whether the document shows as text a file that would otherwise open as a preview.
    private func opensAsPlainText(_ document: DataDocument) -> Bool {
        
        guard
            document is TextDocument,
            let fileURL = document.fileURL
        else { return false }
        
        let contentType = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        
        return !Self.shouldOpen(url: fileURL, ofType: contentType)
    }
    
    
    /// Records the document in the document history.
    ///
    /// - Parameters:
    ///   - document: The document to record.
    ///   - opensAsPlainText: Whether the document should be opened as plain text when navigating back to it.
    private func recordDocumentHistory(document: DataDocument, opensAsPlainText: Bool) {
        
        guard let fileURL = document.fileURL else { return }
        
        self.documentHistory.record(fileURL: fileURL, opensAsPlainText: opensAsPlainText, fileType: document.fileType.flatMap(UTType.init))
    }
    
    
    /// Copies the file to a new destination inside the directory.
    ///
    /// - Note: This method doesn't update the file node.
    ///
    /// - Parameters:
    ///   - sourceURL: The source file URL.
    ///   - destinationURL: The destination.
    /// - Throws: A file coordination or copying error.
    private func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        
        var coordinationError: NSError?
        var copyingError: any Error?
        NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: sourceURL, options: .withoutChanges, writingItemAt: destinationURL, error: &coordinationError) { newSourceURL, newDestinationURL in
            do {
                try FileManager.default.copyItem(at: newSourceURL, to: newDestinationURL)
            } catch {
                copyingError = error
            }
        }
        
        if let error = coordinationError ?? copyingError {
            throw error
        }
    }
    
    
    /// Moves the file to a new destination inside the directory.
    ///
    /// - Note: This method doesn't update the file node.
    ///
    /// - Parameters:
    ///   - sourceURL: The current file URL.
    ///   - destinationURL: The destination.
    private func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        
        var coordinationError: NSError?
        var movingError: any Error?
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: sourceURL, options: .forMoving, writingItemAt: destinationURL, options: .forMoving, error: &coordinationError) { newSourceURL, newDestinationURL in
            do {
                try FileManager.default.moveItem(at: newSourceURL, to: newDestinationURL)
            } catch {
                movingError = error
            }
        }
        
        if let error = coordinationError ?? movingError {
            throw error
        }
    }
}


private extension DataDocument {
    
    /// Whether closing the document would lose something without saving it first.
    var hasChanges: Bool {
        
        self.isDocumentEdited || self.hasUnautosavedChanges
    }
}


private enum DirectoryDocumentError: LocalizedError {
    
    case alreadyOpen(URL)
    
    
    var errorDescription: String? {
        
        switch self {
            case .alreadyOpen(let fileURL):
                String(localized: "DirectoryDocumentError.alreadyOpen.description",
                       defaultValue: "The file “\(fileURL.lastPathComponent)” is already open in another window.")
        }
    }
    
    
    var recoverySuggestion: String? {
        
        switch self {
            case .alreadyOpen:
                String(localized: "DirectoryDocumentError.alreadyOpen.recoverySuggestion",
                       defaultValue: "To open it in this window, close the existing window first.",
                       comment: "“it” is the file in description.")
        }
    }
}
