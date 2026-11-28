//
//  TabLayoutTests.swift
//
//  Graupel
//  https://github.com/ryanromanov/graupel
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Testing
@testable import Graupel

struct TabLayoutTests {
    
    @Test func scrollingTabsKeepTheirWidth() {
        
        #expect(TabLayout(count: 3, width: 600, listButtonWidth: 36, overflow: .scroll)
                == TabLayout(count: 4, width: 600, listButtonWidth: 36, overflow: .scroll))
        
        let layout = TabLayout(count: 5, width: 600, listButtonWidth: 36, overflow: .scroll)
        #expect(layout.tabWidth == TabLayout.preferredWidth)
        #expect(layout.overflows)
    }
    
    
    @Test func shrinkingTabsShareTheWidthDownToAMinimum() {
        
        let shared = TabLayout(count: 6, width: 600, listButtonWidth: 36, overflow: .shrink)
        #expect(shared.tabWidth == 100)
        #expect(!shared.overflows)
        
        let few = TabLayout(count: 2, width: 600, listButtonWidth: 36, overflow: .shrink)
        #expect(few.tabWidth == TabLayout.preferredWidth)
        
        let crowded = TabLayout(count: 20, width: 600, listButtonWidth: 36, overflow: .shrink)
        #expect(crowded.tabWidth == TabLayout.minimumWidth)
        #expect(crowded.overflows)
    }
    
    
    @Test func scrollOffsetRevealsATabAndStaysInRange() {
        
        func offset(_ current: CGFloat, revealing index: Int?) -> CGFloat {
            TabLayout.offset(current, revealing: index, tabWidth: 100, count: 8, viewport: 300)
        }
        
        #expect(offset(0, revealing: 4) == 200)  // after the view
        #expect(offset(400, revealing: 1) == 100)  // before the view
        #expect(offset(100, revealing: 2) == 100)  // already in view
        #expect(offset(900, revealing: nil) == 500)
        #expect(offset(-20, revealing: nil) == 0)
        #expect(TabLayout.offset(50, revealing: nil, tabWidth: 100, count: 2, viewport: 300) == 0)
    }
}
