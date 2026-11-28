//
//  EditorTextViewEscapeTests.swift
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

import AppKit
import Testing
import LineEnding
@testable import Graupel

@MainActor struct EditorTextViewEscapeTests {
    
    @Test func escapeDoesNotChangeTextInAWindow() {
        
        let textStorage = NSTextStorage(string: "word wo")
        let lineEndingScanner = LineEndingScanner(textStorage: textStorage, lineEnding: .lf)
        let textView = EditorTextView(textStorage: textStorage, lineEndingScanner: lineEndingScanner)
        textView.selectedRange = NSRange(location: 7, length: 0)
        
        textView.cancelOperation(nil)
        
        #expect(textView.string == "word wo")
    }
    
    
    @Test func escapeLeavesFullScreen() {
        
        let textStorage = NSTextStorage(string: "word")
        let lineEndingScanner = LineEndingScanner(textStorage: textStorage, lineEnding: .lf)
        let textView = EditorTextView(textStorage: textStorage, lineEndingScanner: lineEndingScanner)
        let window = FullScreenWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                      styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(textView)
        textView.selectedRange = NSRange(0..<4)
        
        textView.cancelOperation(nil)
        
        #expect(window.toggleCount == 1)
        #expect(textView.string == "word")
    }
}


/// A window that says it’s in full screen, and counts the requests to leave it.
private final class FullScreenWindow: NSWindow {
    
    var toggleCount = 0
    
    
    override var styleMask: NSWindow.StyleMask {
        
        get { super.styleMask.union(.fullScreen) }
        set { super.styleMask = newValue }
    }
    
    
    override func toggleFullScreen(_ sender: Any?) {
        
        self.toggleCount += 1
    }
}
