//
//  HighlightSortingTests.swift
//  SyntaxParsersTests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-02-01.
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

import Testing
import Foundation
import ValueRange
import SyntaxFormat
@testable import SyntaxParsers

struct HighlightSortingTests {
    
    @Test func emptyDictionary() throws {
        
        let result = try Highlight.highlights(dictionary: [:])
        
        #expect(result.isEmpty)
    }
    
    
    @Test func basicSorting() throws {
        
        // non-overlapping ranges for different types
        let dict: [SyntaxType: [NSRange]] = [
            .keywords: [NSRange(location: 10, length: 2)],
            .strings: [NSRange(location: 0, length: 3)],
            .comments: [NSRange(location: 5, length: 2)],
        ]
        let result = try Highlight.highlights(dictionary: dict)
        
        #expect(result.count == 3)
        #expect(result[0] == Highlight(value: .strings, range: NSRange(location: 0, length: 3)))
        #expect(result[1] == Highlight(value: .comments, range: NSRange(location: 5, length: 2)))
        #expect(result[2] == Highlight(value: .keywords, range: NSRange(location: 10, length: 2)))
    }
    
    
    @Test func overlapResolutionByPriority() throws {
        
        // overlapping ranges across different types
        let dict: [SyntaxType: [NSRange]] = [
            .strings: [NSRange(location: 0, length: 10)],
            .comments: [NSRange(location: 3, length: 4)],
            .keywords: [NSRange(location: 5, length: 4)],
        ]
        let result = try Highlight.highlights(dictionary: dict)
        
        // no overlaps among output
        for (index, range) in result.map(\.range).enumerated() {
            for nextRange in result[(index + 1)...].map(\.range) {
                #expect(!(range.lowerBound < nextRange.upperBound && nextRange.lowerBound < range.upperBound))
            }
        }
        
        // coverage equals union of inputs
        #expect(result.map(\.range).union == dict.flatMap(\.value).union)
        
        // deterministic order by location
        let sortedByLocation = result.sorted(using: KeyPathComparator(\.range.location))
        #expect(result == sortedByLocation)
        
        // sanity check that some portion near 5..9 is attributed to exactly one type
        let coveredAt6 = result.filter { $0.range.contains(6) }
        #expect(coveredAt6.count == 1)
    }
    
    
    @Test func subtractOverlapsProducesHoles() throws {
        
        let inner = NSRange(location: 3, length: 4)
        let outer = NSRange(location: 0, length: 10)
        let dict: [SyntaxType: [NSRange]] = [
            .values: [inner],
            .keywords: [outer],
        ]
        
        let result = try Highlight.highlights(dictionary: dict)
        
        #expect(result.count == 3)
        #expect(result[0] == Highlight(value: .keywords, range: NSRange(location: 0, length: 3)))
        #expect(result[1] == Highlight(value: .values, range: NSRange(location: 3, length: 4)))
        #expect(result[2] == Highlight(value: .keywords, range: NSRange(location: 7, length: 3)))
    }
    
    
    @Test func subtractOverlapsWinsHigherPriorityKey() throws {
        
        let inner = NSRange(location: 3, length: 4)
        let outer = NSRange(location: 0, length: 10)
        let dict: [SyntaxType: [NSRange]] = [
            .values: [outer],
            .keywords: [inner],
        ]
        
        let result = try Highlight.highlights(dictionary: dict)
        
        #expect(result.count == 1)
        #expect(result[0] == Highlight(value: .values, range: outer))
    }
    
    
    @Test func adjacentRangesOfOneTypeJoin() throws {
        
        let dict: [SyntaxType: [NSRange]] = [
            .keywords: [NSRange(location: 3, length: 2), NSRange(location: 0, length: 3), NSRange(location: 8, length: 0)],
        ]
        
        let result = try Highlight.highlights(dictionary: dict)
        
        #expect(result == [Highlight(value: .keywords, range: NSRange(location: 0, length: 5))])
    }
    
    
    @Test(arguments: 0..<20)
    func matchesCharacterByCharacterResolution(seed: UInt64) throws {
        
        var generator = SeededGenerator(seed: seed)
        let length = 300
        var dict: [SyntaxType: [NSRange]] = [:]
        for type in SyntaxType.allCases where Bool.random(using: &generator) {
            dict[type] = (0..<Int.random(in: 0...40, using: &generator)).map { _ in
                let location = Int.random(in: 0..<length, using: &generator)
                return NSRange(location: location, length: Int.random(in: 0...min(20, length - location), using: &generator))
            }
        }
        
        // reference: for each character, the covering type that comes last in `allCases`
        var owners = [SyntaxType?](repeating: nil, count: length)
        for type in SyntaxType.allCases {
            for range in dict[type] ?? [] {
                for location in range.lowerBound..<range.upperBound {
                    owners[location] = type
                }
            }
        }
        var expected: [Highlight] = []
        var location = 0
        while location < length {
            guard let owner = owners[location] else { location += 1; continue }
            var end = location
            while end < length, owners[end] == owner { end += 1 }
            expected.append(Highlight(value: owner, range: NSRange(location: location, length: end - location)))
            location = end
        }
        
        #expect(try Highlight.highlights(dictionary: dict) == expected)
    }
    
    
    @Test(.timeLimit(.minutes(1)))
    func manyInterleavedRanges() throws {
        
        // 2 million separate short ranges, those of each type falling between those of the others,
        // as in a large source file
        var dict: [SyntaxType: [NSRange]] = [:]
        for (offset, type) in SyntaxType.allCases.enumerated() {
            dict[type] = stride(from: offset * 10, to: 40_000_000, by: 200).map { NSRange(location: $0, length: 4) }
        }
        
        let result = try Highlight.highlights(dictionary: dict)
        
        #expect(result.count == 2_000_000)
    }
    
    
    @Test func cancellation() async throws {
        
        let dict: [SyntaxType: [NSRange]] = [
            .strings: [NSRange(location: 0, length: 1000)],
            .comments: [NSRange(location: 0, length: 1000)],
            .keywords: [NSRange(location: 0, length: 1000)],
        ]
        
        let task = Task<[Highlight], any Error> {
            try Task.checkCancellation()
            return try ValueRange<SyntaxType>.highlights(dictionary: dict)
        }
        task.cancel()
        
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}


// MARK: -

private extension [NSRange] {
    
    var union: IndexSet {
        
        self.reduce(into: IndexSet()) { $0.insert(integersIn: $1.lowerBound..<$1.upperBound) }
    }
}


private struct SeededGenerator: RandomNumberGenerator {
    
    var state: UInt64
    
    init(seed: UInt64) {
        
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }
    
    mutating func next() -> UInt64 {
        
        // SplitMix64
        self.state &+= 0x9E37_79B9_7F4A_7C15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
