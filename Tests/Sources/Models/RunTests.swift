//
//  RunTests.swift
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

import Foundation
import Testing
@testable import CotEditor

struct RunCommandTests {
    
    @Test func builtInCommand() {
        
        let command = RunCommand.command(syntaxName: "Boreas", settings: [:], scriptsDirectoryURL: nil)
        
        #expect(command?.name == "boreas")
        #expect(command?.source == .builtIn)
        #expect(command?.arguments(fileURL: URL(filePath: "/tmp/a b.bor")) == ["/tmp/a b.bor"])
        #expect(RunCommand.command(syntaxName: "Python", settings: [:], scriptsDirectoryURL: nil) == nil)
    }
    
    
    @Test func settingsComeBeforeScriptsAndScriptsBeforeBuiltIn() throws {
        
        let directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scripts = directory.appending(component: RunCommand.directoryName)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let script = scripts.appending(component: "Boreas.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        
        let fromScript = RunCommand.command(syntaxName: "Boreas", settings: [:], scriptsDirectoryURL: directory)
        #expect(fromScript?.source == .script)
        #expect(fromScript?.name == script.path)
        
        let fromSettings = RunCommand.command(syntaxName: "Boreas", settings: ["Boreas": "boreas --trace"], scriptsDirectoryURL: directory)
        #expect(fromSettings?.source == .settings)
        #expect(fromSettings?.commandLine == "boreas --trace")
        
        #expect(RunCommand.command(syntaxName: "Boreas", settings: ["Boreas": "  "], scriptsDirectoryURL: nil)?.source == .builtIn)
    }
    
    
    @MainActor @Test func commandLineGetsTheFileAsOneArgument() async throws {
        
        let command = try #require(RunCommand(commandLine: "printf '[%s]'"))
        let fileURL = URL(filePath: "/tmp/with space.txt")
        let session = RunSession(fileURL: fileURL,
                                 executableURL: try #require(command.executableURL(searchPath: [])),
                                 arguments: command.arguments(fileURL: fileURL),
                                 commandLine: command.commandLine)
        session.start()
        await session.waitUntilEnded()
        
        #expect(session.text(.output) == "[/tmp/with space.txt]")
        #expect(session.state == .finished(status: 0))
    }
}


struct IncrementalUTF8DecoderTests {
    
    @Test func characterSplitBetweenPieces() {
        
        var decoder = IncrementalUTF8Decoder()
        let bytes = Array("aé😀b".utf8)  // é is 2 bytes, 😀 is 4
        
        var text = ""
        for byte in bytes {
            text += decoder.decode(Data([byte]))
        }
        text += decoder.finish()
        
        #expect(text == "aé😀b")
    }
    
    
    @Test func incompleteCharacterIsHeldBack() {
        
        var decoder = IncrementalUTF8Decoder()
        let bytes = Array("x😀".utf8)
        
        #expect(decoder.decode(Data(bytes[..<3])) == "x")
        #expect(decoder.decode(Data(bytes[3...])) == "😀")
    }
}


@MainActor struct RunSessionTests {
    
    private func session(_ script: String) -> RunSession {
        
        RunSession(fileURL: FileManager.default.temporaryDirectory.appending(component: "run.txt"),
                   executableURL: URL(filePath: "/bin/sh"),
                   arguments: ["-c", script],
                   commandLine: "sh")
    }
    
    
    /// Waits until the condition holds, for at most the time given.
    ///
    /// The limit is generous because other tests can keep the main actor, which shows the output, busy for seconds.
    private func wait(atMost limit: Duration = .seconds(15), until condition: () -> Bool) async {
        
        let deadline = ContinuousClock.now + limit
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
    
    
    @Test func outputAndErrorsInOrderAndTheExitStatus() async {
        
        let session = self.session("echo one; echo oops >&2; echo two; echo again >&2; exit 3")
        session.start()
        await session.waitUntilEnded()
        
        #expect(session.text(.output) == "one\ntwo\n")
        #expect(session.text(.error) == "oops\nagain\n")
        #expect(session.state == .finished(status: 3))
        #expect(session.duration != nil)
    }
    
    
    @Test func outputArrivesBeforeTheProgramWaitsForInput() async {
        
        let session = self.session("echo 'Name?'; read name; echo \"Hello, $name\"")
        session.start()
        
        await self.wait { session.text(.output) == "Name?\n" }
        #expect(session.text(.output) == "Name?\n")
        #expect(session.isRunning)
        
        session.send("Ryan")
        await session.waitUntilEnded()
        
        #expect(session.text(.output) == "Name?\nHello, Ryan\n")
        #expect(session.text(.input) == "Ryan\n")
        #expect(session.state == .finished(status: 0))
    }
    
    
    @Test func stopInterruptsTheProgram() async {
        
        let session = self.session("while :; do echo looping; done")
        session.start()
        await self.wait { !session.chunks.isEmpty }
        
        let start = ContinuousClock.now
        session.stop()
        await session.waitUntilEnded()
        
        #expect(session.state == .stopped)
        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(session.chunks.reduce(0) { $0 + $1.text.count } <= RunSession.outputLimit + 100_000)
    }
    
    
    @Test func stopForceQuitsAProgramThatIgnoresTheInterrupt() async {
        
        let session = self.session("trap '' INT; exec sleep 30")
        session.start()
        try? await Task.sleep(for: .milliseconds(200))
        
        let start = ContinuousClock.now
        session.stop()
        await session.waitUntilEnded()
        
        #expect(session.state == .stopped)
        #expect(ContinuousClock.now - start < RunSession.stopTimeout + .seconds(2))
    }
    
    
    @Test func programThatCannotStart() async {
        
        let session = RunSession(fileURL: URL(filePath: "/tmp/run.txt"), executableURL: URL(filePath: "/nonexistent/program"),
                                 arguments: [], commandLine: "program")
        session.start()
        await session.waitUntilEnded()
        
        guard case .failed = session.state else {
            Issue.record("expected the run to fail, got \(session.state)")
            return
        }
    }
    
    
    @Test func clearKeepsTheProgramRunning() async {
        
        let session = self.session("echo before; read x; echo after")
        session.start()
        await self.wait { session.text(.output) == "before\n" }
        
        session.clearOutput()
        #expect(session.chunks.isEmpty)
        #expect(session.clearCount == 1)
        
        session.send("")
        await session.waitUntilEnded()
        #expect(session.text(.output) == "after\n")
    }
}


@MainActor struct RunControllerTests {
    
    @Test func overlappingRunsLeaveOneProgramRunning() async throws {
        
        let controller = RunController()
        let command = try #require(RunCommand(commandLine: "sleep 30;"))  // `sleep 30; "$1"`: the file is ignored
        let fileURL = FileManager.default.temporaryDirectory.appending(component: "run.txt")
        
        async let first: Void = controller.run(fileURL: fileURL, command: command)
        async let second: Void = controller.run(fileURL: fileURL, command: command)
        _ = await (first, second)
        
        #expect(controller.sessions.count == 1)
        #expect(controller.isRunning)
        
        controller.stopAll()
        await controller.currentSession?.waitUntilEnded()
        #expect(!controller.isRunning)
    }
}


private extension RunSession {
    
    /// All text of one stream that's kept.
    func text(_ stream: Stream) -> String {
        
        self.chunks.filter { $0.stream == stream }.map(\.text).joined()
    }
}
