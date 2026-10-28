//
//  LanguageServerMessageFramer.swift
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

import Foundation

/// Splits a byte stream into Language Server Protocol messages framed with the `Content-Length` header.
struct LanguageServerMessageFramer {

    enum FramingError: Error, Equatable {

        case missingContentLength
    }


    // MARK: Private Properties

    private static let separator = Data("\r\n\r\n".utf8)

    private var buffer = Data()


    // MARK: Public Methods

    /// Wraps a message body with the header.
    ///
    /// - Parameter body: The JSON-encoded message.
    /// - Returns: The data to write to the stream.
    static func frame(_ body: Data) -> Data {

        Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    }


    /// Appends received bytes and returns the bodies of all messages completed by them.
    ///
    /// A message may arrive split across several chunks, and a chunk may hold several messages.
    ///
    /// - Parameter data: The received bytes.
    /// - Returns: The message bodies in the received order.
    /// - Throws: `FramingError` if a header lacks `Content-Length`. The buffer is discarded in that case.
    mutating func append(_ data: Data) throws(FramingError) -> [Data] {

        self.buffer.append(data)

        var bodies: [Data] = []
        while let headerEnd = self.buffer.range(of: Self.separator) {
            let header = String(bytes: self.buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""

            guard let length = Self.contentLength(in: header) else {
                self.buffer.removeAll()
                throw .missingContentLength
            }

            let bodyStart = headerEnd.upperBound
            guard self.buffer.distance(from: bodyStart, to: self.buffer.endIndex) >= length else { break }

            let bodyEnd = self.buffer.index(bodyStart, offsetBy: length)
            bodies.append(Data(self.buffer[bodyStart..<bodyEnd]))
            self.buffer = Data(self.buffer[bodyEnd...])
        }

        return bodies
    }


    // MARK: Private Methods

    /// Finds the `Content-Length` field value in a header (field names are case-insensitive).
    private static func contentLength(in header: String) -> Int? {

        header
            .split(separator: "\r\n")
            .lazy
            .compactMap { line -> Int? in
                let field = line.split(separator: ":", maxSplits: 1)
                guard field.count == 2, field[0].lowercased() == "content-length" else { return nil }
                return Int(field[1].trimmingCharacters(in: .whitespaces))
            }
            .first
    }
}
