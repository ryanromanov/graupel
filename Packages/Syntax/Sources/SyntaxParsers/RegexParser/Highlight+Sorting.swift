//
//  Highlight.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-07-11.
//
//  ---------------------------------------------------------------------------
//
//  © 2022-2026 1024jp
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
import SyntaxFormat
import StringUtils
import ValueRange

extension ValueRange<SyntaxType> {
    
    /// Converts a syntax highlight dictionary to sorted Highlights.
    ///
    /// Where ranges of different types overlap, the type that comes later in `SyntaxType.allCases` wins.
    ///
    /// - Note: This sanitization significantly reduces the performance time of attribute application.
    ///
    /// - Parameter dictionary: The syntax highlight dictionary.
    /// - Returns: An array of sorted Highlight structs.
    /// - Throws: `CancellationError`.
    static func highlights(dictionary: [SyntaxType: [NSRange]]) throws -> [ValueRange<SyntaxType>] {
        
        // The ranges are kept as sorted arrays and combined in one pass each.
        // `IndexSet.formUnion` inserts range by range and gets quadratic with millions of interleaved ranges.
        var occupied: [Range<Int>] = []
        var highlights: [ValueRange<SyntaxType>] = []
        
        for type in SyntaxType.allCases.reversed() {
            guard let ranges = dictionary[type] else { continue }
            
            try Task.checkCancellation()
            
            let merged = ranges.compactMap(Range.init).merged()
            
            highlights += merged.subtracting(occupied).map { ValueRange(value: type, range: NSRange($0)) }
            occupied = occupied.union(merged)
        }
        
        return highlights.sorted(using: KeyPathComparator(\.range.location))
    }
}


private extension [Range<Int>] {
    
    /// Returns the ranges sorted, with empty ranges removed and overlapping or adjacent ranges joined.
    func merged() -> [Range<Int>] {
        
        var result: [Range<Int>] = []
        
        for range in self.filter({ !$0.isEmpty }).sorted(using: KeyPathComparator(\.lowerBound)) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.endIndex - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        
        return result
    }
    
    
    /// Returns the parts of the ranges that `other` doesn't cover.
    ///
    /// Both arrays must be in the form `merged()` returns.
    func subtracting(_ other: [Range<Int>]) -> [Range<Int>] {
        
        var result: [Range<Int>] = []
        var index = other.startIndex
        
        for range in self {
            var lowerBound = range.lowerBound
            
            while index < other.endIndex, other[index].upperBound <= lowerBound {
                index += 1
            }
            while index < other.endIndex, other[index].lowerBound < range.upperBound {
                if other[index].lowerBound > lowerBound {
                    result.append(lowerBound..<other[index].lowerBound)
                }
                lowerBound = other[index].upperBound
                if other[index].upperBound >= range.upperBound { break }
                index += 1
            }
            if lowerBound < range.upperBound {
                result.append(lowerBound..<range.upperBound)
            }
        }
        
        return result
    }
    
    
    /// Returns the ranges covered by either array, in the form `merged()` returns.
    ///
    /// Both arrays must be in the form `merged()` returns.
    func union(_ other: [Range<Int>]) -> [Range<Int>] {
        
        var result: [Range<Int>] = []
        result.reserveCapacity(self.count + other.count)
        var (i, j) = (self.startIndex, other.startIndex)
        
        while i < self.endIndex || j < other.endIndex {
            let range: Range<Int>
            if j == other.endIndex || (i < self.endIndex && self[i].lowerBound <= other[j].lowerBound) {
                range = self[i]
                i += 1
            } else {
                range = other[j]
                j += 1
            }
            
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.endIndex - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        
        return result
    }
}
