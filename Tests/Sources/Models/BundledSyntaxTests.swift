//
//  BundledSyntaxTests.swift
//  Tests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-06-11.
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

import Foundation
import Testing
import SyntaxFormat
import SyntaxParsers
import TextEditing
import ValueRange
@testable import Graupel

actor BundledSyntaxTests {
    
    @Test func validateAllSyntaxes() throws {
        
        let syntaxes = try Self.loadSyntaxes()
        
        #expect(!syntaxes.isEmpty)
        
        for (name, syntax) in syntaxes {
            let errors = syntax.validate()
            
            #expect(errors.isEmpty)
            for error in errors {
                Issue.record("\(name): \(error)")
            }
        }
    }
    
    
    @Test func sanitize() throws {
        
        let syntaxes = try Self.loadSyntaxes()
        
        for (name, syntax) in syntaxes {
            let sanitized = syntax.sanitized
            
            #expect(syntax.kind == sanitized.kind)
            
            for type in SyntaxType.allCases {
                #expect(syntax.highlights[type] == sanitized.highlights[type],
                        ".\(type.rawValue) of “\(name)” is not sanitized in the latest manner")
            }
            
            #expect(syntax.outlines == sanitized.outlines,
                    ".outlines of “\(name)” is not sanitized in the latest manner")
            #expect(syntax.completions == sanitized.completions,
                    ".completions of “\(name)” is not sanitized in the latest manner")
            #expect(syntax.commentDelimiters == sanitized.commentDelimiters,
                    ".commentDelimiters of “\(name)” is not sanitized in the latest manner")
            #expect(syntax.fileMap.extensions == sanitized.fileMap.extensions,
                    ".extensions of “\(name)” is not sanitized in the latest manner")
            #expect(syntax.fileMap.filenames == sanitized.fileMap.filenames,
                    ".filenames of “\(name)” is not sanitized in the latest manner")
            #expect(syntax.fileMap.interpreters == sanitized.fileMap.interpreters,
                    ".interpreters of “\(name)” is not sanitized in the latest manner")
            #expect(syntax.metadata == sanitized.metadata,
                    ".metadata of “\(name)” is not sanitized in the latest manner")
        }
    }
    
    
    @Test func containHardcodedSyntaxes() throws {
        
        let syntaxNames = try Self.loadSyntaxes().keys
        
        // syntax names hardcoded for the automatic syntax detection
        #expect(syntaxNames.contains(SyntaxName.markdown))
        #expect(syntaxNames.contains(SyntaxName.json))
        #expect(syntaxNames.contains("XML"))  // used in SyntaxMappingTable.syntaxName(forContent:)
    }
    
    
    @Test func xmlSyntax() throws {
        
        let syntax = try Self.loadSyntax(named: "XML")
        
        #expect(syntax.highlightParser != nil)
        #expect(syntax.outlineParser == nil)
        #expect(syntax.commentDelimiters.inlines.isEmpty)
        #expect(syntax.commentDelimiters.blocks == [.init(begin: "<!--", end: "-->")])
    }
    
    
    @Test func parseOutline() async throws {
        
        let syntax = try Self.loadSyntax(named: "SVG")
        
        // load test file
        let bundle = Bundle(for: type(of: self))
        let sourceURL = try #require(bundle.url(forResource: "sample", withExtension: "svg"))
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        
        let parser = try #require(syntax.outlineParser)
        let outlineItems = try await parser.parseOutline(in: source)
        #expect(outlineItems.count == 3)
        
        let item = outlineItems[1]
        #expect(item.indent == .string(""))
        #expect(item.title == "#dogcow")
        #expect(item.range == NSRange(location: 164, length: 11))
        #expect(item.style.isEmpty)
    }
    
    
    // MARK: Private Methods
    
    /// Loads all bundled syntaxes.
    ///
    /// - Returns: The bundled syntaxes keyed by name.
    /// - Throws: A bundle loading error.
    private static func loadSyntaxes() throws -> [String: Syntax] {
        
        let urls = try #require(Bundle.main.urls(forResourcesWithExtension: "cotsyntax", subdirectory: "Syntaxes"))
        
        return urls.reduce(into: [:]) { dict, url in
            let name = url.deletingPathExtension().lastPathComponent
            
            #expect(throws: Never.self, "The bundled \(name) syntax is invalid.") {
                dict[name] = try Syntax(contentsOf: url)
            }
        }
    }
    
    
    /// Loads a bundled syntax.
    ///
    /// - Parameter name: The bundled syntax name.
    /// - Returns: The loaded syntax.
    /// - Throws: A bundle loading or syntax parsing error.
    /// Lines after which Return should, and should not, indent, by language.
    private static let indentCases: [String: (indents: [String], doesNotIndent: [String])] = [
        "Boreas": (
            ["program demo", "module geometry", "public record point", "function square(real :: x) -> real",
             "subroutine swap(inout real :: a)", "outer: do i = 1, 10", "DO I = 1, N", "select case (x)", "case 1, 3",
             "if x then ! note", "else", "else if y then"],
            ["case 1, 3 -> \"small\"", "case default -> 2", "end do", "end function", "! do this", "x = 1 ! then"]
        ),
        "Fortran": (
            ["program main", "module geometry", "subroutine swap(a, b)", "real function f(x)",
             "pure recursive function g(n) result(r)", "integer(kind=8) function h()", "character(len=*) function name(x)",
             "type :: point", "type, extends(shape) :: circle", "do i = 1, n", "outer: do i = 1, n", "do while (x < 3)",
             "select case (k)", "case (1)", "case default", "if (x > 0) then", "else", "else if (y) then",
             "where (a > 0)", "contains", "interface", "block", "named: block"],
            ["end do", "end subroutine swap", "end type point", "type(point) :: p", "module procedure foo",
             "call subroutine_x()", "real :: function_count", "x = 1", "where (a > 0) a = 1", "end", "! do this",
             "else if (x) y = 1", "if (x) y = 1", "doubled = 2", "block = 1"]
        ),
        "Julia": (
            ["function f(x)", "macro m(x)", "module M", "struct Point", "mutable struct P", "if x > 0", "for i in 1:n",
             "while true", "let a = 1", "@inline function f(x)", "map(xs) do x", "open(f) do io", "else", "elseif y",
             "catch e", "finally", "quote"],
            ["function f(x) x + 1 end", "if x y end", "end", "f(x) = x + 1", "x = 1", "abstract type Shape end",
             "# if x", "undo(x)"]
        ),
        "Ruby": (
            ["def foo(x)", "def self.bar", "class Foo < Bar", "module Baz", "if x", "if x == 1", "unless y", "while z",
             "case n", "begin", "items.each do |i|", "loop do", "else", "elsif x", "when 1", "rescue => e", "ensure",
             "in [x, y]"],
            ["def foo = 1", "def foo(x) = x * 2", "class Foo < Bar; end", "return if x", "x = 1", "end",
             "when 1 then :one", "# def foo", "include Comparable"]
        ),
        "MATLAB": (
            ["function y = f(x)", "if x > 0", "for i = 1:n", "while true", "switch k", "case 1", "otherwise", "else",
             "elseif y", "try", "catch err", "classdef Foo < handle"],
            ["if x, y = 1; end", "for i = 1:3, disp(i), end", "end", "x = 1;", "% if x"]
        ),
        "Erlang": (["foo(X) ->"], ["foo(X) -> X + 1."]),
        "Haskell": (["main = do", "case x of", "module Main where"], ["x = 1"]),
        "Shell Script": (["else", "case $x in"], ["echo hi"]),
        "Lua": (["else"], ["x = 1"]),
        "Ada": (["procedure Foo is", "else"], ["X := 1;"]),
        "VHDL": (["architecture rtl of top is", "gen: for i in 0 to 3 generate", "else"], ["a <= b;"]),
        "Pascal": (["case x of", "while x do", "else"], ["x := 1;"]),
    ]
    
    
    @Test(arguments: indentCases.keys.sorted()) func blockIndentation(name: String) throws {
        
        let syntax = try Self.loadSyntax(named: name)
        let tokens = syntax.indentation.blockDelimiters.compactMap {
            IndentToken(begin: $0.begin, end: $0.end, isRegularExpression: $0.isRegularExpression, ignoreCase: $0.ignoreCase)
        }
        #expect(tokens.count == syntax.indentation.blockDelimiters.count, "\(name) has an invalid block delimiter")
        
        let cases = try #require(Self.indentCases[name])
        for line in cases.indents {
            let string = line + "\n"
            let context = string.smartIndent(style: .space, indentWidth: 2, tokens: tokens, in: [NSRange(location: string.utf16.count, length: 0)])
            #expect(context?.strings == ["  "], "\(name): should indent after “\(line)”")
        }
        for line in cases.doesNotIndent {
            let string = line + "\n"
            let context = string.smartIndent(style: .space, indentWidth: 2, tokens: tokens, in: [NSRange(location: string.utf16.count, length: 0)])
            #expect(context == nil, "\(name): should not indent after “\(line)”")
        }
    }
    
    
    /// Boreas's `is` and `as` are keywords only in a type test, `select type`, and `record r is iface`;
    /// elsewhere they're ordinary names.
    @Test func boreasContextualKeywords() async throws {
        
        let parser = try #require(try Self.loadSyntax(named: "Boreas").highlightParser)
        
        // each line, and where an `is` or `as` highlighted as a keyword starts
        let cases: [(line: String, offsets: [Int])] = [
            ("if shapes[2] is rect as r then", [13, 21]),
            ("else if x is sized as s then", [10, 19]),
            ("IF x IS Rect AS r THEN", [5, 13]),
            ("if x is rect then", [5]),
            ("select type x as p", [14]),
            ("record square is shape, sized", [14]),
            ("if is > 0 then", []),
            ("if f(is) is rect then", [9]),
            ("integer :: is, as", []),
            ("x = is + as", []),
        ]
        for (line, offsets) in cases {
            let string = line as NSString
            let result = try await parser.parseHighlights(in: line, range: NSRange(location: 0, length: string.length))
            let found = (result?.highlights ?? [])
                .filter { $0.value == .keywords && ["is", "as"].contains(string.substring(with: $0.range).lowercased()) }
                .map(\.range.location)
            #expect(found == offsets, "\(line)")
        }
    }
    
    
    private static func loadSyntax(named name: String) throws -> Syntax {
        
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "cotsyntax", subdirectory: "Syntaxes"))
        
        return try Syntax(contentsOf: url)
    }
}
