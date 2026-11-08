//
//  RunSession.swift
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

import AppKit
import Foundation
import Synchronization

/// One run of a program: it starts the program, collects its output as it arrives, passes it input, and stops it.
///
/// Each run is its own session, so output that arrives late from an earlier run never mixes into a newer one,
/// and a window could later keep several runs at once.
@MainActor @Observable final class RunSession: Identifiable {
    
    enum Stream: Sendable {
        
        case output
        case error
        case input
    }
    
    
    struct Chunk: Equatable, Sendable {
        
        var stream: Stream
        var text: String
    }
    
    
    enum State: Equatable {
        
        case running
        /// The program ended with the exit status.
        case finished(status: Int32)
        /// The program ended after the user pressed Stop.
        case stopped
        /// A signal that didn't come from Stop ended the program.
        case killed(signal: Int32)
        /// The program couldn't be started.
        case failed(String)
    }
    
    
    /// The most characters of output kept; older output is dropped, so a program that prints without end can't
    /// use up memory.
    static let outputLimit = 1_000_000
    
    /// How long to wait for the program to end after the interrupt that Stop sends, before force-quitting it.
    static let stopTimeout: Duration = .seconds(2)
    
    /// How long to wait for the rest of the output after the program ended, in case a child process keeps it open.
    static let drainTimeout: Duration = .seconds(1)
    
    /// How often new output is shown.
    private static let flushInterval: Duration = .milliseconds(40)
    
    
    // MARK: Public Properties
    
    let id = UUID()
    let fileURL: URL
    
    /// The command as shown to users, such as `boreas tour.bor`.
    let commandLine: String
    
    private(set) var state: State = .running
    private(set) var duration: Duration?
    
    /// The output kept, oldest first. A chunk never changes once it's added.
    private(set) var chunks: [Chunk] = []
    
    /// How many chunks were dropped from the start of `chunks`, to stay within the limit or by Clear.
    private(set) var droppedChunkCount = 0
    
    /// Increases when the output is cleared, so that a view showing it starts over.
    private(set) var clearCount = 0
    
    var isRunning: Bool  { self.state == .running }
    
    
    // MARK: Private Properties
    
    @ObservationIgnored private let process = Process()
    @ObservationIgnored private let inputPipe = Pipe()
    @ObservationIgnored private let outputPipe = Pipe()
    @ObservationIgnored private let errorPipe = Pipe()
    @ObservationIgnored private let buffer = RunOutputBuffer()
    
    /// The queue to write input on, so that a program that doesn't read doesn't block the main thread.
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "com.ryanromanov.Graupel.run.input")
    
    @ObservationIgnored private var startTime: ContinuousClock.Instant?
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var endWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var keptCharacterCount = 0
    
    /// The sessions whose program is running, to stop them when the app quits.
    private static let running = NSHashTable<RunSession>.weakObjects()
    
    private static let terminationObserver: any NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            for session in RunSession.running.allObjects where session.process.isRunning {
                session.process.terminate()
            }
        }
    }
    
    
    // MARK: Lifecycle
    
    /// Creates a run that hasn't started yet.
    ///
    /// - Parameters:
    ///   - fileURL: The file being run; the program runs in its folder.
    ///   - executableURL: The program.
    ///   - arguments: The program's arguments.
    ///   - commandLine: The command as shown to users.
    init(fileURL: URL, executableURL: URL, arguments: [String], commandLine: String) {
        
        self.fileURL = fileURL
        self.commandLine = commandLine
        
        self.process.executableURL = executableURL
        self.process.arguments = arguments
        self.process.currentDirectoryURL = fileURL.deletingLastPathComponent()
        self.process.standardInput = self.inputPipe
        self.process.standardOutput = self.outputPipe
        self.process.standardError = self.errorPipe
        
        // fail writes with EPIPE instead of terminating the app when the program has quit
        _ = fcntl(self.inputPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    
    
    // MARK: Public Methods
    
    /// Starts the program.
    ///
    /// - Parameter searchPath: The directories for the program's `PATH`, so that it finds the same tools as in Terminal.
    func start(searchPath: [String] = []) {
        
        _ = Self.terminationObserver
        
        var environment = ProcessInfo.processInfo.environment
        if !searchPath.isEmpty {
            environment["PATH"] = searchPath.joined(separator: ":")
        }
        // Python, which Boreas runs on, holds back output written to a pipe until it has a block of it;
        // this makes it write each line at once, so that a prompt appears before the program waits for input
        environment["PYTHONUNBUFFERED"] = "1"
        self.process.environment = environment
        
        let (exits, exitContinuation) = AsyncStream.makeStream(of: (Process.TerminationReason, Int32).self)
        self.process.terminationHandler = { process in
            exitContinuation.yield((process.terminationReason, process.terminationStatus))
            exitContinuation.finish()
        }
        
        do {
            try self.process.run()
        } catch {
            self.end(state: .failed(error.localizedDescription))
            return
        }
        
        self.startTime = .now
        Self.running.add(self)
        
        let buffer = self.buffer
        let outputPipe = self.outputPipe
        let errorPipe = self.errorPipe
        let readers = [
            Task.detached { await Self.read(outputPipe, as: .output, into: buffer) },
            Task.detached { await Self.read(errorPipe, as: .error, into: buffer) },
        ]
        
        self.flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.flushInterval)
                self?.flush()
            }
        }
        
        Task {
            var exit: (Process.TerminationReason, Int32)?
            for await value in exits {
                exit = value
            }
            
            // let the rest of the output arrive, unless a child process keeps the pipes open
            let deadline = ContinuousClock.now + Self.drainTimeout
            while buffer.endedStreamCount < readers.count, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            readers.forEach { $0.cancel() }
            
            let state: State = switch exit {
                case _ where self.isStopping: .stopped
                case (.uncaughtSignal, let signal)?: .killed(signal: signal)
                case (_, let status)?: .finished(status: status)
                case nil: .finished(status: 0)
            }
            self.end(state: state)
        }
    }
    
    
    /// Stops the program: sends it an interrupt, as Control-C does in Terminal, and force-quits it if it's still
    /// running after a moment.
    func stop() {
        
        guard self.isRunning, !self.isStopping else { return }
        
        self.isStopping = true
        self.process.interrupt()
        
        Task { [process] in
            try? await Task.sleep(for: Self.stopTimeout)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
    
    
    /// Sends a line of input to the program and shows it in the output.
    ///
    /// - Parameter line: The text, without the line ending.
    func send(_ line: String) {
        
        guard self.isRunning else { return }
        
        let text = line + "\n"
        self.buffer.append(text, as: .input)
        
        let handle = self.inputPipe.fileHandleForWriting
        self.writeQueue.async {
            try? handle.write(contentsOf: Data(text.utf8))
        }
    }
    
    
    /// Removes the output shown so far.
    func clearOutput() {
        
        self.flush()
        self.droppedChunkCount += self.chunks.count
        self.chunks.removeAll()
        self.keptCharacterCount = 0
        self.clearCount += 1
    }
    
    
    /// Waits until the program has ended and its output has arrived.
    func waitUntilEnded() async {
        
        guard self.isRunning else { return }
        
        await withCheckedContinuation { continuation in
            self.endWaiters.append(continuation)
        }
    }
    
    
    // MARK: Private Methods
    
    /// Reads a stream of the program's output until it ends.
    private nonisolated static func read(_ pipe: Pipe, as stream: Stream, into buffer: RunOutputBuffer) async {
        
        var decoder = IncrementalUTF8Decoder()
        do {
            for try await data in pipe.readingStream {
                buffer.append(decoder.decode(data), as: stream)
            }
        } catch {
            // the output ended
        }
        buffer.append(decoder.finish(), as: stream)
        buffer.endStream()
    }
    
    
    /// Moves the output that arrived into `chunks`, keeping within the limit.
    private func flush() {
        
        let newChunks = self.buffer.take()
        
        guard !newChunks.isEmpty else { return }
        
        self.chunks += newChunks
        self.keptCharacterCount += newChunks.reduce(0) { $0 + $1.text.count }
        
        var dropCount = 0
        while self.keptCharacterCount > Self.outputLimit, dropCount < self.chunks.count - 1 {
            self.keptCharacterCount -= self.chunks[dropCount].text.count
            dropCount += 1
        }
        if dropCount > 0 {
            self.chunks.removeFirst(dropCount)
            self.droppedChunkCount += dropCount
        }
    }
    
    
    /// Records how the run ended.
    private func end(state: State) {
        
        self.flushTask?.cancel()
        self.flush()
        
        if let startTime = self.startTime {
            self.duration = .now - startTime
        }
        self.state = state
        
        let handle = self.inputPipe.fileHandleForWriting
        self.writeQueue.async {
            try? handle.close()
        }
        Self.running.remove(self)
        
        let waiters = self.endWaiters
        self.endWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}


/// The output that arrived and hasn't been shown yet, filled from the threads that read it.
final class RunOutputBuffer: Sendable {
    
    private struct Contents {
        
        var chunks: [RunSession.Chunk] = []
        var characterCount = 0
        var endedStreamCount = 0
    }
    
    private let contents = Mutex(Contents())
    
    
    /// The number of output streams that have ended.
    var endedStreamCount: Int  { self.contents.withLock(\.endedStreamCount) }
    
    
    /// Adds text, joining it to the last chunk if that came from the same stream.
    ///
    /// Older text is dropped once the buffer holds more than the session keeps anyway.
    func append(_ text: String, as stream: RunSession.Stream) {
        
        guard !text.isEmpty else { return }
        
        self.contents.withLock { contents in
            if contents.chunks.last?.stream == stream {
                contents.chunks[contents.chunks.count - 1].text += text
            } else {
                contents.chunks.append(RunSession.Chunk(stream: stream, text: text))
            }
            contents.characterCount += text.count
            
            while contents.characterCount > RunSession.outputLimit, contents.chunks.count > 1 {
                contents.characterCount -= contents.chunks.removeFirst().text.count
            }
        }
    }
    
    
    /// Records that one of the output streams ended.
    func endStream() {
        
        self.contents.withLock { $0.endedStreamCount += 1 }
    }
    
    
    /// Returns the text that arrived since the last call and empties the buffer.
    func take() -> [RunSession.Chunk] {
        
        self.contents.withLock { contents in
            let chunks = contents.chunks
            contents.chunks.removeAll()
            contents.characterCount = 0
            return chunks
        }
    }
}


/// Decodes UTF-8 text that arrives in pieces, holding back a character that's split between two pieces until
/// the rest of it arrives.
struct IncrementalUTF8Decoder: Sendable {
    
    private var pending: [UInt8] = []
    
    
    /// Returns the text of the complete characters so far.
    mutating func decode(_ data: Data) -> String {
        
        let bytes = self.pending + data
        
        // find where an incomplete character at the end starts, looking back at most 3 bytes
        var end = bytes.count
        for index in bytes.indices.reversed().prefix(4) {
            let byte = bytes[index]
            guard byte & 0b1100_0000 == 0b1000_0000 else {  // not a continuation byte
                let length = switch byte {
                    case 0b1111_0000...: 4
                    case 0b1110_0000...: 3
                    case 0b1100_0000...: 2
                    default: 1
                }
                if bytes.count - index < length {
                    end = index
                }
                break
            }
        }
        
        self.pending = Array(bytes[end...])
        
        return String(decoding: bytes[..<end], as: UTF8.self)
    }
    
    
    /// Returns what's left, once no more data will arrive.
    mutating func finish() -> String {
        
        defer { self.pending.removeAll() }
        
        return String(decoding: self.pending, as: UTF8.self)
    }
}
