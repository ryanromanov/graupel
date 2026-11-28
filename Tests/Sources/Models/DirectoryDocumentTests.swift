//
//  DirectoryDocumentTests.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-04-12.
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
import Testing
import DocumentFile
import URLUtils
@testable import Graupel

struct DirectoryDocumentTests {
    
    @Test @MainActor func movingFolderToDestinationWithExistingNameUsesActualDestinationURL() throws {
        
        let urls = try self.makeMoveConflictTree()
        defer { try? FileManager.default.removeItem(at: urls.rootURL) }
        
        let document = DirectoryDocument()
        document.fileURL = urls.rootURL
        try document.read(from: urls.rootURL, ofType: "public.folder")
        
        let rootNode = try #require(document.fileNode)
        let movingNode = try #require(rootNode.node(at: urls.folderURL))
        let destinationNode = try #require(rootNode.node(at: urls.destinationURL))
        let leafNode = try #require(rootNode.node(at: urls.leafURL))
        let expectedURL = urls.destinationURL.appending(component: movingNode.file.name).appendingUniqueNumber().standardizedFileURL
        
        try document.moveItem(at: movingNode, to: destinationNode)
        
        #expect(movingNode.parent === destinationNode)
        #expect(self.path(of: movingNode.file.fileURL) == self.path(of: expectedURL))
        #expect(self.path(of: leafNode.file.fileURL) == self.path(of: expectedURL.appending(path: "child/leaf.txt", directoryHint: .notDirectory)))
        #expect(FileManager.default.fileExists(atPath: expectedURL.path(percentEncoded: false)))
    }
    
    
    @Test @MainActor func filesOpenInTabs() async throws {
        
        let (document, urls) = try self.makeFolder(files: ["a.txt", "b.txt", "c.txt"])
        defer {
            document.close()
            try? FileManager.default.removeItem(at: document.fileURL!)
        }
        
        #expect(await document.openDocument(at: urls[0], keeps: true))
        #expect(await document.openDocument(at: urls[1]))
        #expect(await document.openDocument(at: urls[2]))
        
        // the second preview took the place of the first, whose document closed
        #expect(document.tabs.items.compactMap(\.fileURL?.lastPathComponent) == ["a.txt", "c.txt"])
        #expect(document.tabs.preview === document.currentDocument)
        #expect(NSDocumentController.shared.document(for: urls[1]) == nil)
        
        // opening an open file selects its tab
        let first = document.tabs.items[0]
        #expect(await document.openDocument(at: urls[0]))
        #expect(document.currentDocument === first)
        #expect(document.tabs.items.count == 2)
        
        #expect(await document.closeTab(of: first))
        #expect(document.currentDocument?.fileURL?.lastPathComponent == "c.txt")
        #expect(NSDocumentController.shared.document(for: urls[0]) == nil)
    }
    
    
    @Test @MainActor func editedPreviewIsKept() async throws {
        
        let (document, urls) = try self.makeFolder(files: ["a.txt", "b.txt"])
        defer {
            document.close()
            try? FileManager.default.removeItem(at: document.fileURL!)
        }
        
        #expect(await document.openDocument(at: urls[0]))
        let edited = try #require(document.currentDocument as? TextDocument)
        edited.updateChangeCount(.changeDone)
        #expect(await document.openDocument(at: urls[1]))
        
        #expect(document.tabs.items.count == 2)
        #expect(document.tabs.items.first === edited)
        
        edited.updateChangeCount(.changeCleared)
    }
    
    
    @Test @MainActor func tabsAreRestored() async throws {
        
        let (document, urls) = try self.makeFolder(files: ["a.txt", "b.txt", "c.txt"])
        defer { try? FileManager.default.removeItem(at: document.fileURL!) }
        
        #expect(await document.openDocument(at: urls[0], keeps: true))
        #expect(await document.openDocument(at: urls[1], keeps: true))
        #expect(await document.openDocument(at: urls[2]))
        #expect(await document.openDocument(at: urls[0]))
        
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        document.encodeRestorableState(with: archiver, backgroundQueue: queue)
        await withCheckedContinuation { continuation in  // AppKit encodes part of the state there
            queue.addBarrierBlock { continuation.resume() }
        }
        archiver.finishEncoding()
        document.close()
        
        let restored = DirectoryDocument()
        restored.fileURL = document.fileURL
        try restored.read(from: document.fileURL!, ofType: "public.folder")
        defer { restored.close() }
        restored.restoreState(with: try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData))
        
        for _ in 0..<100 where restored.currentDocument?.fileURL?.lastPathComponent != "a.txt" {
            try await Task.sleep(for: .milliseconds(20))
        }
        
        #expect(restored.tabs.items.compactMap(\.fileURL?.lastPathComponent) == ["a.txt", "b.txt", "c.txt"])
        #expect(restored.currentDocument?.fileURL?.lastPathComponent == "a.txt")
        #expect(restored.tabs.preview?.fileURL?.lastPathComponent == "c.txt")
    }
    
    
    // MARK: Private Methods
    
    /// Makes a folder document with empty files in a temporary folder.
    @MainActor private func makeFolder(files: [String]) throws -> (DirectoryDocument, [URL]) {
        
        let rootURL = try FileManager.default.makeTemporaryDirectory().resolvingSymlinksInPath()
        let urls = files.map { rootURL.appending(path: $0, directoryHint: .notDirectory) }
        for url in urls {
            try Data("text\n".utf8).write(to: url)
        }
        
        let document = DirectoryDocument()
        document.fileURL = rootURL
        try document.read(from: rootURL, ofType: "public.folder")
        
        return (document, urls)
    }
    
    private struct MoveConflictTreeURLs {
        
        let rootURL: URL
        let folderURL: URL
        let destinationURL: URL
        let leafURL: URL
    }
    
    
    private func makeMoveConflictTree() throws -> MoveConflictTreeURLs {
        
        let rootURL = try FileManager.default.makeTemporaryDirectory()
        let folderURL = rootURL.appending(path: "folder", directoryHint: .isDirectory)
        let childFolderURL = folderURL.appending(path: "child", directoryHint: .isDirectory)
        let leafURL = childFolderURL.appending(path: "leaf.txt", directoryHint: .notDirectory)
        let destinationURL = rootURL.appending(path: "destination", directoryHint: .isDirectory)
        let conflictingURL = destinationURL.appending(path: "folder", directoryHint: .isDirectory)
        
        try FileManager.default.createDirectory(at: childFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conflictingURL, withIntermediateDirectories: true)
        try Data().write(to: leafURL)
        
        return MoveConflictTreeURLs(rootURL: rootURL, folderURL: folderURL, destinationURL: destinationURL, leafURL: leafURL)
    }
    
    
    private func path(of url: URL) -> String {
        
        NSString(string: url.standardizedFileURL.path(percentEncoded: false)).standardizingPath
    }
}
