//
//  RunPanel.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by ryanromanov on 2026-11-08.
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

import SwiftUI
import AppKit

/// The panel below the editor that shows a run's output, takes its input, and stops it.
struct RunPanel: View {
    
    let controller: RunController
    var run: () -> Void
    var hide: () -> Void
    
    @State private var input = ""
    
    
    var body: some View {
        
        let session = self.controller.currentSession
        
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(session?.commandLine ?? String(localized: "Run", table: "Run", comment: "title of the Run panel"))
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if let session {
                    RunStatusView(session: session)
                }
                
                Button(String(localized: "Run", table: "Run", comment: "button"), systemImage: "play.fill", action: self.run)
                    .help(String(localized: "Save and run the document (Command-R)", table: "Run", comment: "tooltip"))
                Button(String(localized: "Stop", table: "Run", comment: "button"), systemImage: "stop.fill") {
                    self.controller.stop()
                }
                .help(String(localized: "Stop the program (Command-Period)", table: "Run", comment: "tooltip"))
                .disabled(!self.controller.isRunning)
                Button(String(localized: "Clear", table: "Run", comment: "button"), systemImage: "trash") {
                    self.controller.clear()
                }
                .help(String(localized: "Clear the output", table: "Run", comment: "tooltip"))
                .disabled(session == nil && self.controller.notice == nil)
                Button(String(localized: "Hide", table: "Run", comment: "button"), systemImage: "chevron.down", action: self.hide)
                    .help(String(localized: "Hide the Run panel", table: "Run", comment: "tooltip"))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            
            Divider()
            
            if let notice = self.controller.notice {
                Text(notice)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let session {
                RunOutputView(session: session,
                              chunkCount: session.droppedChunkCount + session.chunks.count,
                              clearCount: session.clearCount)
            } else {
                Text("Press Command-R to save and run the document. Its output appears here.", tableName: "Run")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if let session, session.isRunning {
                Divider()
                TextField(String(localized: "Input", table: "Run", comment: "placeholder"), text: $input)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .onSubmit {
                        session.send(self.input)
                        self.input = ""
                    }
                    .help(String(localized: "Text to send to the program; press Return to send it", table: "Run", comment: "tooltip"))
            }
        }
        .background(.background)
    }
}


/// How the run is going: running, or how it ended and how long it took.
private struct RunStatusView: View {
    
    let session: RunSession
    
    
    var body: some View {
        
        switch self.session.state {
            case .running:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running", tableName: "Run")
                        .foregroundStyle(.secondary)
                }
            case .finished(status: 0):
                Text("Finished in \(self.time)", tableName: "Run")
                    .foregroundStyle(.secondary)
            case .finished(let status):
                Text("Ended with status \(status) after \(self.time)", tableName: "Run")
                    .foregroundStyle(.red)
            case .stopped:
                Text("Stopped after \(self.time)", tableName: "Run")
                    .foregroundStyle(.secondary)
            case .killed(let signal):
                Text("Ended by signal \(signal) after \(self.time)", tableName: "Run")
                    .foregroundStyle(.red)
            case .failed(let message):
                Text("Couldn’t start: \(message)", tableName: "Run")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(message)
        }
    }
    
    
    private var time: String {
        
        let seconds = Double(self.session.duration?.components.seconds ?? 0)
            + Double(self.session.duration?.components.attoseconds ?? 0) / 1e18
        
        return (seconds < 60)
            ? String(localized: "\(seconds.formatted(.number.precision(.fractionLength(2)))) s", table: "Run", comment: "duration in seconds")
            : Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}


/// The output of a run, in a text view that grows as output arrives.
private struct RunOutputView: NSViewRepresentable {
    
    let session: RunSession
    
    /// The number of chunks the session has produced, so that the view updates when output arrives.
    let chunkCount: Int
    let clearCount: Int
    
    
    final class Coordinator {
        
        var sessionID: UUID?
        var clearCount = 0
        
        /// The number of the session's chunks that the text view shows, counting the dropped ones.
        var shownChunkCount = 0
    }
    
    
    func makeCoordinator() -> Coordinator {
        
        Coordinator()
    }
    
    
    func makeNSView(context: Context) -> NSScrollView {
        
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.setAccessibilityLabel(String(localized: "Output", table: "Run", comment: "accessibility label"))
        
        return scrollView
    }
    
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        
        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = textView.textStorage
        else { return }
        
        let coordinator = context.coordinator
        
        // start over for another run, after Clear, or when output was dropped before it was shown
        if coordinator.sessionID != self.session.id || coordinator.clearCount != self.clearCount
            || coordinator.shownChunkCount < self.session.droppedChunkCount
        {
            textStorage.setAttributedString(NSAttributedString())
            coordinator.sessionID = self.session.id
            coordinator.clearCount = self.clearCount
            coordinator.shownChunkCount = self.session.droppedChunkCount
        }
        
        let newChunks = self.session.chunks.dropFirst(coordinator.shownChunkCount - self.session.droppedChunkCount)
        
        guard !newChunks.isEmpty else { return }
        
        let isAtEnd = scrollView.documentVisibleRect.maxY >= textView.bounds.maxY - 8
        let font = textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        
        textStorage.beginEditing()
        for chunk in newChunks {
            let color: NSColor = switch chunk.stream {
                case .output: .textColor
                case .error: .systemRed
                case .input: .controlAccentColor
            }
            textStorage.append(NSAttributedString(string: chunk.text, attributes: [.font: font, .foregroundColor: color]))
        }
        // keep about as much as the session does
        let excess = textStorage.length - RunSession.outputLimit
        if excess > 0 {
            textStorage.deleteCharacters(in: NSRange(location: 0, length: excess))
        }
        textStorage.endEditing()
        
        coordinator.shownChunkCount = self.session.droppedChunkCount + self.session.chunks.count
        
        if isAtEnd {
            textView.scrollToEndOfDocument(nil)
        }
    }
}
