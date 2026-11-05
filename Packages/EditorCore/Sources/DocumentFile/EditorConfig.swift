//
//  EditorConfig.swift
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

public import Foundation

/// The indentation an `.editorconfig` file sets for a file, following https://spec.editorconfig.org.
///
/// Only `indent_style`, `indent_size`, and `tab_width` are read.
public struct EditorConfig: Equatable, Sendable {

    /// Whether to indent with spaces (`indent_style = space`) or tabs (`tab`), or `nil` if not set.
    public var expandsTab: Bool?

    /// The indent width: `indent_size` for spaces, `tab_width` for tabs. `nil` if not set.
    public var width: Int?

    public var isEmpty: Bool { self.expandsTab == nil && self.width == nil }


    public init(expandsTab: Bool? = nil, width: Int? = nil) {

        self.expandsTab = expandsTab
        self.width = width
    }


    /// Reads the `.editorconfig` files that apply to the file at the given URL.
    ///
    /// - Parameter fileURL: The file URL of the document.
    public init(for fileURL: URL) {

        // collect files from the file's folder up to the first `root = true`, or the top of the disk
        // -> Walk the path components: the parent of `/` is `/..`, not `/`.
        // -> Use one form of the path for both the folders and the file, as `standardizedFileURL` can drop
        //    a leading `/private`.
        let fileURL = fileURL.standardizedFileURL
        var files: [(directory: String, source: String)] = []
        var components = fileURL.deletingLastPathComponent().pathComponents
        while !components.isEmpty {
            let directory = NSString.path(withComponents: components)
            let configURL = URL(filePath: directory, directoryHint: .isDirectory).appending(path: ".editorconfig", directoryHint: .notDirectory)
            if let source = try? String(contentsOf: configURL, encoding: .utf8) {
                files.append((directory, source))
                if Self.isRoot(source) { break }
            }
            components.removeLast()
        }

        // the closest file wins: apply from the root down
        var properties: [String: String] = [:]
        for file in files.reversed() {
            properties.merge(Self.properties(in: file.source, directory: file.directory, filePath: fileURL.path(percentEncoded: false))) { $1 }
        }

        self.init(properties: properties)
    }


    /// Creates from the raw properties that apply to a file.
    ///
    /// - Parameter properties: The properties, with lowercase keys.
    init(properties: [String: String]) {

        let properties = properties.filter { $0.value != "unset" }
        let style = properties["indent_style"]
        var indentSize = properties["indent_size"]
        var tabWidth = properties["tab_width"].flatMap(Int.init)

        // the defaults the specification defines between the three properties
        if style == "tab", indentSize == nil {
            indentSize = "tab"
        }
        if tabWidth == nil, let size = indentSize.flatMap(Int.init) {
            tabWidth = size
        }
        let indentWidth = (indentSize == "tab") ? tabWidth : indentSize.flatMap(Int.init)

        self.expandsTab = switch style {
            case "space": true
            case "tab": false
            default: nil
        }
        self.width = switch style {
            case "tab": tabWidth ?? indentWidth
            default: indentWidth
        }
        if let width = self.width, width < 1 {
            self.width = nil
        }
    }
}


extension EditorConfig {

    /// Whether the file says `root = true` before its first section.
    static func isRoot(_ source: String) -> Bool {

        for line in Self.lines(in: source) {
            switch line {
                case .section: return false
                case .property(let key, let value) where key == "root": return value == "true"
                case .property: continue
            }
        }
        return false
    }


    /// The properties of the sections in the file that match the given file, later sections winning.
    ///
    /// - Parameters:
    ///   - source: The contents of an `.editorconfig` file.
    ///   - directory: The path of the folder the `.editorconfig` file is in.
    ///   - filePath: The path of the file to find properties for.
    /// - Returns: The properties, with lowercase keys and, for known properties, lowercase values.
    static func properties(in source: String, directory: String, filePath: String) -> [String: String] {

        var properties: [String: String] = [:]
        var matches = false
        for line in Self.lines(in: source) {
            switch line {
                case .section(let glob):
                    matches = Self.glob(glob, directory: directory).matches(filePath)
                case .property(let key, let value) where matches:
                    properties[key] = value
                case .property:
                    continue
            }
        }
        return properties
    }


    private enum Line {

        case section(String)
        case property(key: String, value: String)
    }


    private static func lines(in source: String) -> [Line] {

        source.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { return nil }

            if line.hasPrefix("["), line.hasSuffix("]") {
                return .section(String(line.dropFirst().dropLast()))
            }
            guard let separator = line.firstIndex(of: "=") else { return nil }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if ["root", "indent_style", "indent_size", "tab_width"].contains(key) || value.lowercased() == "unset" {
                value = value.lowercased()
            }
            guard !key.isEmpty else { return nil }

            return .property(key: key, value: value)
        }
    }
}


// MARK: - Glob

extension EditorConfig {

    /// A section name compiled to match file paths.
    struct Glob {

        var regex: NSRegularExpression?
        var numericRanges: [ClosedRange<Int>]


        func matches(_ path: String) -> Bool {

            guard
                let regex,
                let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path))
            else { return false }

            // check the numbers matched by `{n1..n2}`
            for (index, range) in self.numericRanges.enumerated() {
                guard
                    let groupRange = Range(match.range(at: index + 1), in: path),
                    let number = Int(path[groupRange]),
                    range.contains(number)
                else { return false }
            }
            return true
        }
    }


    /// Compiles a section name of the `.editorconfig` file in the given folder.
    ///
    /// - Parameters:
    ///   - glob: The section name, such as `*.bor` or `src/**/*.{js,ts}`.
    ///   - directory: The path of the folder that holds the `.editorconfig` file.
    static func glob(_ glob: String, directory: String) -> Glob {

        // a glob without a slash matches at any depth; one with a slash is relative to the folder
        var glob = glob
        if !Self.containsSlash(glob) {
            glob = "**/" + glob
        } else if glob.hasPrefix("/") {
            glob.removeFirst()
        }
        let base = directory.hasSuffix("/") ? directory : directory + "/"

        var ranges: [ClosedRange<Int>] = []
        let pattern = NSRegularExpression.escapedPattern(for: base) + Self.regexPattern(Array(glob), ranges: &ranges)

        return Glob(regex: try? NSRegularExpression(pattern: "^" + pattern + "$"), numericRanges: ranges)
    }


    /// Whether the glob has a `/` outside brackets.
    private static func containsSlash(_ glob: String) -> Bool {

        var inBracket = false
        var escaped = false
        for character in glob {
            if escaped { escaped = false; continue }
            switch character {
                case "\\": escaped = true
                case "[": inBracket = true
                case "]": inBracket = false
                case "/" where !inBracket: return true
                default: break
            }
        }
        return false
    }


    private static func regexPattern(_ glob: [Character], ranges: inout [ClosedRange<Int>]) -> String {

        var pattern = ""
        var index = 0

        while index < glob.count {
            let character = glob[index]
            switch character {
                case "\\" where index + 1 < glob.count:
                    pattern += NSRegularExpression.escapedPattern(for: String(glob[index + 1]))
                    index += 2
                    continue

                case "*":
                    if index + 1 < glob.count, glob[index + 1] == "*" {
                        // `**/` also matches no folder at all
                        if index + 2 < glob.count, glob[index + 2] == "/" {
                            pattern += "(?:.*/)?"
                            index += 3
                        } else {
                            pattern += ".*"
                            index += 2
                        }
                        continue
                    }
                    pattern += "[^/]*"

                case "?":
                    pattern += "[^/]"

                case "[":
                    if let close = glob[(index + 1)...].firstIndex(of: "]"), close > index + 1 {
                        var content = String(glob[(index + 1)..<close])
                        let negated = content.hasPrefix("!") || content.hasPrefix("^")
                        if negated { content.removeFirst() }
                        let escaped = content
                            .replacing("\\", with: "\\\\")
                            .replacing("[", with: "\\[")
                            .replacing("^", with: "\\^")
                        pattern += negated ? "[^/" + escaped + "]" : "[" + escaped + "]"
                        index = close + 1
                        continue
                    }
                    pattern += "\\["

                case "{":
                    if let close = Self.matchingBrace(in: glob, from: index) {
                        let content = String(glob[(index + 1)..<close])
                        if let match = content.wholeMatch(of: /(-?\d+)\.\.(-?\d+)/),
                           let lower = Int(match.1), let upper = Int(match.2)
                        {
                            ranges.append(min(lower, upper)...max(lower, upper))
                            pattern += "([+-]?\\d+)"
                        } else if let alternatives = Self.splitAlternatives(Array(content)), alternatives.count > 1 {
                            pattern += "(?:" + alternatives.map { Self.regexPattern($0, ranges: &ranges) }.joined(separator: "|") + ")"
                        } else {
                            pattern += NSRegularExpression.escapedPattern(for: "{" + content + "}")
                        }
                        index = close + 1
                        continue
                    }
                    pattern += "\\{"

                default:
                    pattern += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        return pattern
    }


    /// The index of the `}` that closes the `{` at the given index.
    private static func matchingBrace(in glob: [Character], from start: Int) -> Int? {

        var depth = 0
        var index = start
        while index < glob.count {
            switch glob[index] {
                case "\\": index += 1
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 { return index }
                default: break
            }
            index += 1
        }
        return nil
    }


    /// Splits brace content at top-level commas, or returns `nil` if there are none.
    private static func splitAlternatives(_ content: [Character]) -> [[Character]]? {

        var parts: [[Character]] = [[]]
        var depth = 0
        var index = 0
        while index < content.count {
            let character = content[index]
            switch character {
                case "\\" where index + 1 < content.count:
                    parts[parts.count - 1] += [character, content[index + 1]]
                    index += 2
                    continue
                case "{": depth += 1
                case "}": depth -= 1
                case "," where depth == 0:
                    parts.append([])
                    index += 1
                    continue
                default: break
            }
            parts[parts.count - 1].append(character)
            index += 1
        }
        return parts.count > 1 ? parts : nil
    }
}
