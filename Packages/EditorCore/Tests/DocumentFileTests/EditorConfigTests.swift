//
//  EditorConfigTests.swift
//  DocumentFileTests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-11-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 CotEditor Project
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

import Foundation
import Testing
@testable import DocumentFile

struct EditorConfigTests {

    // MARK: Globs (cases from editorconfig-core-test's glob tests)

    private func matches(_ glob: String, _ path: String) -> Bool {

        EditorConfig.glob(glob, directory: "/p").matches("/p/" + path)
    }


    @Test func star() {

        #expect(self.matches("a*e.c", "ace.c"))
        #expect(self.matches("a*e.c", "ae.c"))
        #expect(self.matches("a*e.c", "abcde.c"))
        #expect(!self.matches("a*e.c", "a/e.c"))
        #expect(self.matches("*.bor", "records.bor"))
        #expect(self.matches("*.bor", "deep/in/records.bor"))  // no slash: any depth
        #expect(!self.matches("*.bor", "records.bor.txt"))
    }


    @Test func doubleStar() {

        #expect(self.matches("a**z.c", "a/z.c"))
        #expect(self.matches("a**z.c", "amnz.c"))
        #expect(self.matches("a**z.c", "am/nz.c"))
        #expect(self.matches("a**z.c", "a/mn/z.c"))
        #expect(self.matches("src/**/*.c", "src/a.c"))
        #expect(self.matches("src/**/*.c", "src/x/y/a.c"))
        #expect(!self.matches("src/**/*.c", "lib/a.c"))
    }


    @Test func questionMark() {

        #expect(self.matches("a?c.c", "abc.c"))
        #expect(!self.matches("a?c.c", "ac.c"))
        #expect(!self.matches("a?c.c", "a/c.c"))
    }


    @Test func brackets() {

        #expect(self.matches("[ab].a", "a.a"))
        #expect(self.matches("[ab].a", "b.a"))
        #expect(!self.matches("[ab].a", "c.a"))
        #expect(self.matches("[!ab].b", "c.b"))
        #expect(!self.matches("[!ab].b", "a.b"))
        #expect(self.matches("[d-g].c", "f.c"))
        #expect(!self.matches("[d-g].c", "h.c"))
        #expect(self.matches("[[]", "["))  // an unclosed bracket is literal
    }


    @Test func braces() {

        #expect(self.matches("*.{py,js}", "a.py"))
        #expect(self.matches("*.{py,js}", "b.js"))
        #expect(!self.matches("*.{py,js}", "c.rb"))
        #expect(self.matches("{single}.b", "{single}.b"))  // no comma: literal
        #expect(self.matches("{}.c", "{}.c"))
        #expect(self.matches("{.c", "{.c"))  // unclosed: literal
        #expect(self.matches("a{b,c{d,e}}f", "acdf"))  // nested
        #expect(self.matches("{word,}.c", ".c"))  // empty alternative
    }


    @Test func numericRange() {

        #expect(self.matches("{3..120}", "3"))
        #expect(self.matches("{3..120}", "15"))
        #expect(self.matches("{3..120}", "120"))
        #expect(!self.matches("{3..120}", "1"))
        #expect(!self.matches("{3..120}", "121"))
        #expect(!self.matches("{3..120}", "060a"))
        #expect(self.matches("file{-3..3}.c", "file-2.c"))
    }


    @Test func pathsAndEscapes() {

        #expect(self.matches("/top.c", "top.c"))
        #expect(!self.matches("/top.c", "sub/top.c"))
        #expect(self.matches("sub/*.c", "sub/a.c"))
        #expect(!self.matches("sub/*.c", "other/sub/a.c"))
        #expect(self.matches("a\\*b", "a*b"))
        #expect(!self.matches("a\\*b", "axb"))
    }


    // MARK: Properties (cases from editorconfig-core-test's property tests)

    @Test func indentProperties() {

        #expect(EditorConfig(properties: [:]).isEmpty)
        #expect(EditorConfig(properties: ["indent_style": "space", "indent_size": "2"]) == EditorConfig(expandsTab: true, width: 2))
        #expect(EditorConfig(properties: ["indent_style": "tab"]) == EditorConfig(expandsTab: false))
        #expect(EditorConfig(properties: ["indent_style": "tab", "tab_width": "8"]) == EditorConfig(expandsTab: false, width: 8))
        #expect(EditorConfig(properties: ["indent_style": "tab", "indent_size": "4"]) == EditorConfig(expandsTab: false, width: 4))  // tab_width defaults to indent_size
        #expect(EditorConfig(properties: ["indent_size": "tab", "tab_width": "3"]) == EditorConfig(width: 3))
        #expect(EditorConfig(properties: ["indent_size": "3"]) == EditorConfig(width: 3))
        #expect(EditorConfig(properties: ["indent_style": "space", "indent_size": "unset"]) == EditorConfig(expandsTab: true))
        #expect(EditorConfig(properties: ["indent_style": "unset"]).isEmpty)
        #expect(EditorConfig(properties: ["indent_style": "bogus", "indent_size": "x"]).isEmpty)
    }


    @Test func sections() {

        let source = """
            root = true

            # every file
            [*]
            indent_style = tab

            ; Boreas files
            [*.bor]
            indent_style = SPACE
            indent_size = 2

            [*.bor]
            indent_size = 4
            """

        #expect(EditorConfig.isRoot(source))
        #expect(!EditorConfig.isRoot("[*]\nroot = true"))  // only before the first section counts

        let bor = EditorConfig.properties(in: source, directory: "/p", filePath: "/p/a/records.bor")
        #expect(bor["indent_style"] == "space")  // values are case-insensitive
        #expect(bor["indent_size"] == "4")  // later sections win

        let other = EditorConfig.properties(in: source, directory: "/p", filePath: "/p/notes.txt")
        #expect(other == ["indent_style": "tab"])
    }


    @Test func nestedFiles() throws {

        let root = URL.temporaryDirectory.appending(path: "EditorConfigTests-\(UUID().uuidString)")
        let sub = root.appending(path: "sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "root = true\n[*]\nindent_style = space\nindent_size = 4\n".write(to: root.appending(path: ".editorconfig"), atomically: true, encoding: .utf8)
        try "[*.bor]\nindent_size = 2\n".write(to: sub.appending(path: ".editorconfig"), atomically: true, encoding: .utf8)

        // the closest file wins, on top of the root's
        #expect(EditorConfig(for: sub.appending(path: "a.bor")) == EditorConfig(expandsTab: true, width: 2))
        #expect(EditorConfig(for: sub.appending(path: "a.txt")) == EditorConfig(expandsTab: true, width: 4))
        #expect(EditorConfig(for: root.appending(path: "a.bor")) == EditorConfig(expandsTab: true, width: 4))
    }
    
    
    @Test func pathUnderPrivate() throws {
        
        // `/private/tmp/...` and `/tmp/...` are the same folder
        let root = URL(filePath: "/private/tmp/EditorConfigTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "root = true\n[*.bor]\nindent_style = space\nindent_size = 3\n".write(to: root.appending(path: ".editorconfig"), atomically: true, encoding: .utf8)
        
        #expect(EditorConfig(for: root.appending(path: "new.bor")) == EditorConfig(expandsTab: true, width: 3))
    }
    
    
    @Test func searchStopsAtTheTopOfTheDisk() {
        
        // no `root = true` anywhere: the search must end at `/`
        _ = EditorConfig(for: URL(filePath: "/no-such-folder/sub/a.bor"))
        _ = EditorConfig(for: URL(filePath: "/a.bor"))
    }
}
