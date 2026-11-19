//
//  View+ChromeSurface.swift
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

import SwiftUI
import AppKit

extension View {
    
    /// Fills the view with a color of the window chrome, or with the system style when the window has no custom style.
    ///
    /// The chrome is read from the window the view ends up in, so the view doesn't need to be handed anything.
    ///
    /// - Parameters:
    ///   - color: The chrome color to use.
    ///   - system: The style to use when the window isn't drawn with a custom style.
    func chromeSurface(_ color: KeyPath<ChromeStyle, NSColor> = \.background, system: some ShapeStyle) -> some View {
        
        self.modifier(ChromeSurface(color: color, system: AnyShapeStyle(system)))
    }
}


private struct ChromeSurface: ViewModifier {
    
    let color: KeyPath<ChromeStyle, NSColor>
    let system: AnyShapeStyle
    
    @State private var chrome: WindowChrome?
    
    
    func body(content: Content) -> some View {
        
        content
            .background(self.chrome?.style.map { AnyShapeStyle(Color(nsColor: $0[keyPath: self.color])) } ?? self.system)
            .background(ChromeReader(chrome: $chrome))
    }
}


/// A view that finds the chrome of the window it's in.
private struct ChromeReader: NSViewRepresentable {
    
    @Binding var chrome: WindowChrome?
    
    
    func makeNSView(context: Context) -> ReaderView {
        
        ReaderView { chrome in DispatchQueue.main.async { self.chrome = chrome } }
    }
    
    
    func updateNSView(_ nsView: ReaderView, context: Context) { }
    
    
    final class ReaderView: NSView {
        
        private let onChange: (WindowChrome?) -> Void
        
        init(onChange: @escaping (WindowChrome?) -> Void) {
            
            self.onChange = onChange
            super.init(frame: .zero)
        }
        
        
        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        
        override func viewDidMoveToWindow() {
            
            super.viewDidMoveToWindow()
            
            MainActor.assumeIsolated {
                self.onChange((self.window as? DocumentWindow)?.chrome)
            }
        }
    }
}
