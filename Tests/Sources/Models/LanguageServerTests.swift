//
//  LanguageServerTests.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-10-27.
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

import AppKit
import Foundation
import Testing
@testable import CotEditor

struct LanguageServerMessageFramerTests {
    
    @Test func frame() {
        
        let data = LanguageServerMessageFramer.frame(Data("{}".utf8))
        
        #expect(String(bytes: data, encoding: .utf8) == "Content-Length: 2\r\n\r\n{}")
    }
    
    
    @Test func splitAndJoinedMessages() throws {
        
        let stream = LanguageServerMessageFramer.frame(Data(#"{"a":1}"#.utf8))
            + LanguageServerMessageFramer.frame(Data(#"{"b":"é"}"#.utf8))
        var framer = LanguageServerMessageFramer()
        
        // feed one byte at a time, as a pipe may deliver arbitrary chunks
        var bodies: [Data] = []
        for byte in stream {
            bodies += try framer.append(Data([byte]))
        }
        #expect(bodies.map { String(bytes: $0, encoding: .utf8) } == [#"{"a":1}"#, #"{"b":"é"}"#])
        
        // all at once
        var framer2 = LanguageServerMessageFramer()
        #expect(try framer2.append(stream).count == 2)
    }
    
    
    @Test func headerFields() throws {
        
        var framer = LanguageServerMessageFramer()
        let data = Data("content-length: 2\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n{}".utf8)
        
        #expect(try framer.append(data) == [Data("{}".utf8)])
    }
    
    
    @Test func missingContentLength() {
        
        var framer = LanguageServerMessageFramer()
        
        #expect(throws: LanguageServerMessageFramer.FramingError.missingContentLength) {
            try framer.append(Data("Content-Type: x\r\n\r\n{}".utf8))
        }
    }
}


struct LanguageServerCompletionTests {
    
    @Test func completionList() {
        
        let result: [String: Any] = [
            "isIncomplete": false,
            "items": [
                ["label": "total", "kind": 6, "sortText": "0000"],
                ["label": "trim", "kind": 3, "sortText": "0001"],
            ],
        ]
        
        #expect(LanguageServerCompletionItem.words(result: result) == ["total", "trim"])
    }
    
    
    @Test func itemArray() {
        
        let result: [Any] = [["label": "b"], ["label": "a"], ["kind": 1], "junk"]
        
        // without sort texts, items are sorted by label
        #expect(LanguageServerCompletionItem.words(result: result) == ["a", "b"])
        #expect(LanguageServerCompletionItem.words(result: nil).isEmpty)
        #expect(LanguageServerCompletionItem.words(result: NSNull()).isEmpty)
    }
    
    
    @Test func sortTextThenServerOrder() {
        
        let result: [Any] = [
            ["label": "c", "sortText": "1"],
            ["label": "b", "sortText": "0"],
            ["label": "a", "sortText": "1"],
        ]
        
        #expect(LanguageServerCompletionItem.words(result: result) == ["b", "c", "a"])
    }
    
    
    @Test func insertedText() {
        
        let item = LanguageServerCompletionItem(json: [
            "label": "print(x)",
            "insertText": "print",
            "textEdit": ["newText": "println", "range": [:]],
        ])
        
        #expect(item?.label == "print(x)")
        #expect(item?.text == "println")
        #expect(LanguageServerCompletionItem(json: ["label": "a", "insertText": "b"])?.text == "b")
    }
}


struct LanguageServerPositionConverterTests {
    
    private typealias Position = LanguageServerDiagnostic.Position
    
    
    @Test func location() {
        
        let converter = LanguageServerPositionConverter(string: "ab\ncd\r\nef\rgh")
        
        #expect(converter.location(of: Position(line: 0, character: 1)) == 1)
        #expect(converter.location(of: Position(line: 1, character: 0)) == 3)
        #expect(converter.location(of: Position(line: 2, character: 1)) == 8)
        #expect(converter.location(of: Position(line: 3, character: 2)) == 12)
        
        // beyond the line end clamps to the line end (before the line ending)
        #expect(converter.location(of: Position(line: 1, character: 99)) == 5)
        // beyond the last line clamps to the end
        #expect(converter.location(of: Position(line: 9, character: 0)) == 12)
    }
    
    
    @Test func utf16() {
        
        // "😀" is two UTF-16 code units, as the protocol counts by default
        let converter = LanguageServerPositionConverter(string: "😀x")
        
        #expect(converter.location(of: Position(line: 0, character: 2)) == 2)
        #expect(converter.position(at: 3) == Position(line: 0, character: 3))
    }
    
    
    @Test func position() {
        
        let converter = LanguageServerPositionConverter(string: "ab\ncd\r\nef\rgh")
        
        #expect(converter.position(at: 0) == Position(line: 0, character: 0))
        #expect(converter.position(at: 2) == Position(line: 0, character: 2))
        #expect(converter.position(at: 3) == Position(line: 1, character: 0))
        #expect(converter.position(at: 8) == Position(line: 2, character: 1))
        #expect(converter.position(at: 12) == Position(line: 3, character: 2))
        #expect(converter.position(at: 99) == Position(line: 3, character: 2))
        
        for location in [0, 1, 3, 4, 7, 8, 10, 12] {
            #expect(converter.location(of: converter.position(at: location)) == location)
        }
    }
    
    
    @Test func emptyRangeStaysVisible() {
        
        let converter = LanguageServerPositionConverter(string: "x = (\nend")
        
        func range(_ line: Int, _ character: Int) -> NSRange? {
            let position = Position(line: line, character: character)
            return converter.range(of: LanguageServerDiagnostic(start: position, end: position, severity: .error, message: ""))
        }
        
        #expect(range(0, 0) == NSRange(location: 0, length: 1))
        // at the line end, mark the last character instead of the line ending
        #expect(range(0, 5) == NSRange(location: 4, length: 1))
    }
    
    
    @Test func trailingWhitespaceMovesToVisibleCharacter() {
        
        let converter = LanguageServerPositionConverter(string: "x = (1 + \t\nend")
        
        func range(_ start: Int, _ end: Int) -> NSRange? {
            converter.range(of: LanguageServerDiagnostic(start: Position(line: 0, character: start), end: Position(line: 0, character: end), severity: .error, message: ""))
        }
        
        // at the line end and on trailing whitespace: mark the "+"
        #expect(range(10, 10) == NSRange(location: 7, length: 1))
        #expect(range(8, 10) == NSRange(location: 7, length: 1))
        // whitespace inside the line stays
        #expect(range(3, 4) == NSRange(location: 3, length: 1))
        // ranges reaching visible characters stay
        #expect(range(6, 10) == NSRange(location: 6, length: 4))
        
        #expect(LanguageServerPositionConverter(string: "").range(of: LanguageServerDiagnostic(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0), severity: .error, message: "")) == nil)
    }
    
    
    @Test func diagnosticFromJSON() throws {
        
        let json: [String: Any] = [
            "range": ["start": ["line": 2, "character": 10], "end": ["line": 2, "character": 11]],
            "severity": 2,
            "message": "expected an expression",
        ]
        let diagnostic = try #require(LanguageServerDiagnostic(json: json))
        
        #expect(diagnostic.start == Position(line: 2, character: 10))
        #expect(diagnostic.end == Position(line: 2, character: 11))
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.message == "expected an expression")
        
        // severity defaults to error
        #expect(LanguageServerDiagnostic(json: json.filter { $0.key != "severity" })?.severity == .error)
        #expect(LanguageServerDiagnostic(json: ["message": "no range"]) == nil)
    }
}


struct LanguageServerCommandTests {
    
    @Test func shellOutput() {
        
        let marker = ShellSearchPath.marker
        let output = "\u{1B}]7;file://host/Users/me\u{7}welcome!\n\(marker)\n/opt/bin:/usr/bin\n\(marker)\n"
        
        #expect(ShellSearchPath.directories(shellOutput: output) == ["/opt/bin", "/usr/bin"])
        #expect(ShellSearchPath.directories(shellOutput: "\(marker)\n\n\(marker)") == nil)
        #expect(ShellSearchPath.directories(shellOutput: "no path") == nil)
    }
    
    
    @Test func executableURL() {
        
        let command = LanguageServerCommand(name: "sh", arguments: ["-c"])
        
        #expect(command.executableURL(searchPath: ["/nonexistent", "/bin"]) == URL(filePath: "/bin/sh"))
        #expect(command.executableURL(searchPath: ["/nonexistent"]) == nil)
        #expect(LanguageServerCommand(name: "/bin/sh").executableURL(searchPath: []) == URL(filePath: "/bin/sh"))
        #expect(LanguageServerCommand(name: "/nonexistent/sh").executableURL(searchPath: ["/bin"]) == nil)
    }
    
    
    @Test func precedence() throws {
        
        let scriptsURL = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        let scriptURL = scriptsURL.appending(components: "_Language Servers", "Boreas.sh")
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptsURL) }
        
        func command(_ syntaxName: String = "Boreas", settings: [String: String] = [:], disabled: [String] = [], scripts: URL? = nil) -> LanguageServerCommand? {
            
            LanguageServerCommand.command(syntaxName: syntaxName, settings: settings, disabledSyntaxes: disabled, scriptsDirectoryURL: scripts)
        }
        
        // built-in
        #expect(command() == LanguageServerCommand(name: "boreas", arguments: ["lsp"]))
        #expect(command("Python") == nil)
        
        // a script overrides the built-in server
        #expect(command(scripts: scriptsURL)?.source == .script)
        #expect(command(scripts: scriptsURL)?.name == scriptURL.path)
        
        // the settings override both, and are run by the shell
        let custom = try #require(command(settings: ["Boreas": "  my-server --stdio "], scripts: scriptsURL))
        #expect(custom.source == .settings)
        #expect(custom.commandLine == "my-server --stdio")
        #expect(custom.name == "/bin/sh")
        #expect(custom.arguments == ["-c", "exec my-server --stdio"])
        #expect(command("Python", settings: ["Python": "pylsp"])?.commandLine == "pylsp")
        
        // an empty setting falls back to the default
        #expect(command(settings: ["Boreas": " "])?.source == .builtIn)
        #expect(command("Python", settings: ["Python": ""]) == nil)
        
        // turned off
        #expect(command(settings: ["Boreas": "my-server"], disabled: ["Boreas"], scripts: scriptsURL) == nil)
    }
    
    
    @Test func statusProblem() {
        
        #expect(LanguageServer.Status.notInstalled(command: "boreas").isProblem)
        #expect(LanguageServer.Status.failed(reason: "crashed").isProblem)
        #expect(!LanguageServer.Status.launching.isProblem)
        #expect(!LanguageServer.Status.running(URL(filePath: "/bin/sh")).isProblem)
    }
}


struct LanguageServerFormattingTests {
    
    private func edit(_ startLine: Int, _ startCharacter: Int, _ endLine: Int, _ endCharacter: Int, _ newText: String) -> [String: Any] {
        
        ["range": ["start": ["line": startLine, "character": startCharacter],
                   "end": ["line": endLine, "character": endCharacter]],
         "newText": newText]
    }
    
    
    @Test func noChanges() {
        
        #expect(LanguageServerTextEdit.edits(result: nil, in: "a") == [])
        #expect(LanguageServerTextEdit.edits(result: NSNull(), in: "a") == [])
        #expect(LanguageServerTextEdit.edits(result: [] as [Any], in: "a") == [])
    }
    
    
    @Test func editsAreSortedRanges() throws {
        
        // "record point\n    real :: x\nend record\n" reindented to 2 spaces, given out of order
        let string = "record point\n    real :: x\nend record\n" as NSString
        let edits = try #require(LanguageServerTextEdit.edits(result: [
            self.edit(2, 10, 2, 10, "\n"),
            self.edit(1, 0, 1, 4, "  "),
        ], in: string))
        
        #expect(edits == [
            LanguageServerTextEdit(range: NSRange(location: 13, length: 4), newText: "  "),
            LanguageServerTextEdit(range: NSRange(location: 37, length: 0), newText: "\n"),
        ])
    }
    
    
    @Test func invalidResults() {
        
        let string = "abc\ndef" as NSString
        
        #expect(LanguageServerTextEdit.edits(result: "text", in: string) == nil)
        #expect(LanguageServerTextEdit.edits(result: [["newText": "x"]], in: string) == nil)
        #expect(LanguageServerTextEdit.edits(result: [self.edit(1, 2, 0, 1, "x")], in: string) == nil)  // backward
        #expect(LanguageServerTextEdit.edits(result: [self.edit(0, 0, 0, 2, "x"), self.edit(0, 1, 0, 3, "y")], in: string) == nil)  // overlapping
    }
    
    
    @Test func locationAfterEdits() {
        
        // "    real" -> "  real": two characters fewer before the cursor
        let edits = [LanguageServerTextEdit(range: NSRange(location: 13, length: 4), newText: "  ")]
        
        #expect(LanguageServerTextEdit.location(5, after: edits) == 5)  // before the edit
        #expect(LanguageServerTextEdit.location(20, after: edits) == 18)  // after it
        #expect(LanguageServerTextEdit.location(15, after: edits) == 15)  // inside it: the end of the new text
    }
}


private final class MarkTestLayoutManager: NSLayoutManager, ValidationIgnorable {
    
    var ignoresDisplayValidation = false
}


struct LanguageServerDiagnosticMarkTests {
    
    /// Draws the text with a diagnostic on its fourth character, and counts the red pixels.
    @MainActor private func markedPixels(in text: String, font: NSFont) throws -> Int {
        
        let textStorage = NSTextStorage(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let layoutManager = MarkTestLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 300, height: 100))
        layoutManager.addTextContainer(container)
        
        let json: [String: Any] = [
            "range": ["start": ["line": 0, "character": 3], "end": ["line": 0, "character": 4]],
            "severity": 1,
            "message": "error",
        ]
        textStorage.apply(diagnostics: [try #require(LanguageServerDiagnostic(json: json))])
        
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 200,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = NSSize(width: 300, height: 100)
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 100).fill()
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: 100)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawDiagnosticMarks(forGlyphRange: glyphRange, at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7, color.greenComponent < 0.4, color.blueComponent < 0.4 {
                    count += 1
                }
            }
        }
        return count
    }
    
    
    @MainActor @Test(arguments: ["{", "}", "(", "[", "g", "y", "j", "p", "q", "@", ",", "+", "x"])
    func markIsVisibleOnAnyCharacter(character: String) throws {
        
        for font in [NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .systemFont(ofSize: 13), .systemFont(ofSize: 12)] {
            #expect(try self.markedPixels(in: "ab \(character) cd", font: font) >= 8, "\(font)")
        }
    }
    
    
    @Test func dotPositions() {
        
        #expect(DiagnosticDots.positions(from: 10, width: 0) == [10, 13.5])  // never a lone dot
        #expect(DiagnosticDots.positions(from: 10, width: 8).count == 2)
        #expect(DiagnosticDots.positions(from: 10, width: 72).count == 21)
    }
}


struct LanguageServerNavigationTests {
    
    @Test func capabilityIsTrueOrAnOptionsObject() {
        
        #expect(LanguageServer.isSupported(true))
        #expect(LanguageServer.isSupported(["workDoneProgress": false]))
        #expect(!LanguageServer.isSupported(false))
        #expect(!LanguageServer.isSupported(nil))
    }
    
    
    @Test func locationLocationLinkAndArrays() {
        
        let range: [String: Any] = ["start": ["line": 3, "character": 2], "end": ["line": 3, "character": 7]]
        let location: [String: Any] = ["uri": "file:///tmp/a%20b.bor", "range": range]
        let link: [String: Any] = ["targetUri": "file:///tmp/c.bor", "targetRange": ["start": ["line": 0, "character": 0], "end": ["line": 9, "character": 0]],
                                   "targetSelectionRange": range]
        
        let expected = LanguageServerLocation(fileURL: URL(filePath: "/tmp/a b.bor"), start: .init(line: 3, character: 2), end: .init(line: 3, character: 7))
        #expect(LanguageServerLocation.locations(result: location) == [expected])
        #expect(LanguageServerLocation.locations(result: [location]) == [expected])
        #expect(LanguageServerLocation.locations(result: [link]).first?.start == .init(line: 3, character: 2))  // the name, not the whole declaration
        #expect(LanguageServerLocation.locations(result: nil).isEmpty)
        #expect(LanguageServerLocation.locations(result: ["uri": "https://example.com", "range": range]).isEmpty)
    }
    
    
    @Test func hoverContents() throws {
        
        let string = "program t\n  real :: total\nend program\n" as NSString
        
        let markup = try #require(LanguageServerHover.hover(result: [
            "contents": ["kind": "markdown", "value": "```boreas\nreal :: total\n```"],
            "range": ["start": ["line": 1, "character": 10], "end": ["line": 1, "character": 15]],
        ], in: string))
        #expect(markup.isMarkdown)
        #expect(markup.range == NSRange(location: 20, length: 5))
        #expect(markup.parts.map(\.text) == ["real :: total"])
        #expect(markup.parts.map(\.isCode) == [true])
        
        let plain = try #require(LanguageServerHover.hover(result: ["contents": ["kind": "plaintext", "value": "a *b*"]], in: string))
        #expect(!plain.isMarkdown)
        #expect(plain.parts.map(\.text) == ["a *b*"])
        
        let marked = try #require(LanguageServerHover.hover(result: ["contents": [["language": "python", "value": "x = 1"], "A *note*."]], in: string))
        #expect(marked.parts.map(\.text) == ["x = 1", "A *note*."])
        #expect(marked.parts.map(\.isCode) == [true, false])
        
        #expect(LanguageServerHover.hover(result: ["contents": ""], in: string) == nil)
        #expect(LanguageServerHover.hover(result: nil, in: string) == nil)
    }
}
