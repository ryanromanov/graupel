//
//  DocumentTabsTests.swift
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

import Testing
@testable import Graupel

struct DocumentTabsTests {
    
    @Test func previewReplacesPreviewInPlace() {
        
        var tabs = DocumentTabs<String>()
        tabs.open("a", asPreview: false)
        #expect(tabs.open("b", asPreview: true) == nil)
        tabs.open("c", asPreview: false)
        
        #expect(tabs.open("d", asPreview: true) == "b")
        #expect(tabs.items == ["a", "d", "c"])
        #expect(tabs.preview == "d")
        #expect(tabs.selection == "d")
    }
    
    
    @Test func openingAnOpenItemSelectsIt() {
        
        var tabs = DocumentTabs<String>()
        tabs.open("a", asPreview: false)
        tabs.open("b", asPreview: true)
        
        #expect(tabs.open("a", asPreview: true) == nil)
        #expect(tabs.items == ["a", "b"])
        #expect(tabs.selection == "a")
        #expect(tabs.preview == "b")
        
        // opening to keep it ends the preview
        tabs.open("b", asPreview: false)
        #expect(tabs.preview == nil)
    }
    
    
    @Test func keptPreviewIsNotReplaced() {
        
        var tabs = DocumentTabs<String>()
        tabs.open("a", asPreview: true)
        tabs.keep("a")
        
        #expect(tabs.open("b", asPreview: true) == nil)
        #expect(tabs.items == ["a", "b"])
    }
    
    
    @Test func closingSelectsTheNextTabOrThePrevious() {
        
        var tabs = DocumentTabs<String>()
        for item in ["a", "b", "c"] {
            tabs.open(item, asPreview: false)
        }
        tabs.select("b")
        
        tabs.close("b")
        #expect(tabs.selection == "c")
        tabs.close("c")
        #expect(tabs.selection == "a")
        tabs.close("a")
        #expect(tabs.selection == nil)
        #expect(tabs.items.isEmpty)
    }
    
    
    @Test func closingAnotherTabKeepsTheSelection() {
        
        var tabs = DocumentTabs<String>()
        tabs.open("a", asPreview: true)
        tabs.open("b", asPreview: false)
        
        tabs.close("a")
        
        #expect(tabs.selection == "b")
        #expect(tabs.preview == nil)
    }
    
    
    @Test func replacingKeepsThePosition() {
        
        var tabs = DocumentTabs<String>()
        tabs.open("a", asPreview: true)
        tabs.open("b", asPreview: false)
        tabs.select("a")
        
        tabs.replace("a", with: "c")
        
        #expect(tabs.items == ["c", "b"])
        #expect(tabs.selection == "c")
        #expect(tabs.preview == nil)
    }
    
    
    @Test func movingAndStepping() {
        
        var tabs = DocumentTabs<String>()
        for item in ["a", "b", "c"] {
            tabs.open(item, asPreview: false)
        }
        
        tabs.move("c", to: 0)
        #expect(tabs.items == ["c", "a", "b"])
        tabs.move("c", to: 10)
        #expect(tabs.items == ["a", "b", "c"])
        
        #expect(tabs.item(offsetFromSelection: 1) == "a")
        #expect(tabs.item(offsetFromSelection: -1) == "b")
        #expect(DocumentTabs<String>().item(offsetFromSelection: 1) == nil)
    }
}
