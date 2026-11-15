@testable import FlowMail
import Foundation
import Testing

@Suite("MailCommandParser")
struct MailCommandParserTests {
    @Test func parsesCommands() throws {
        #expect(try MailCommandParser.parse("find mail from Sarah") == .find(MailQuery(sender: "Sarah")))
        #expect(try MailCommandParser.parse("mail find Sarah's email about meeting")
            == .find(MailQuery(sender: "Sarah", terms: ["meeting"])))
        #expect(try MailCommandParser.parse("search mail with subject budget in mailbox FlowTest")
            == .find(MailQuery(subject: "budget", mailbox: "FlowTest")))
        #expect(try MailCommandParser.parse("open email from Priya Patel in mailbox Import/FlowTest")
            == .open(MailQuery(sender: "Priya Patel", mailbox: "Import/FlowTest")))
        #expect(try MailCommandParser.parse("read the message titled \"Lunch on Friday\"")
            == .read(MailQuery(subject: "Lunch on Friday")))
        #expect(try MailCommandParser.parse("look for messages about quarterly report")
            == .find(MailQuery(terms: ["quarterly", "report"])))
        #expect(try MailCommandParser.parse("choose 2") == .choose(2))
        #expect(try MailCommandParser.parse("mail 3") == .choose(3))
        #expect(try MailCommandParser.parse("read it") == .readActive)
        #expect(try MailCommandParser.parse("mail read this message") == .readActive)
        #expect(try MailCommandParser.parse("status") == .status(requestPermission: false))
        #expect(try MailCommandParser.parse("allow access") == .status(requestPermission: true))
    }

    @Test(arguments: ["", "find", "open mail", "delete mail from Sarah", "send it", "choose x", "find subject \"unclosed"])
    func rejects(input: String) {
        #expect(throws: MailParseError.self) { try MailCommandParser.parse(input) }
    }
}

@Suite("Mail formatting and wire decoding")
struct MailFormattingTests {
    @Test func cleanBody() {
        let (body, truncated) = MailContentFormatter.clean("A\r\n\r\n\r\n\r\nB\u{200B}\u{FFFC}  \nC", maxCharacters: 100)
        #expect(body == "A\n\nB\nC")
        #expect(!truncated)
    }

    @Test func truncatesOnWordBoundary() {
        let (body, truncated) = MailContentFormatter.clean("alpha beta gamma delta", maxCharacters: 13)
        #expect(body == "alpha beta…")
        #expect(truncated)
    }

    @Test func snippetIsFirstLine() {
        #expect(MailContentFormatter.snippet("\n\n  Hey!\n\nMore") == "Hey!")
        #expect(MailContentFormatter.snippet("\u{FFFC}\n") == nil)
    }

    @Test(arguments: [
        ("Sarah Chen <sarah.chen@example.invalid>", "Sarah Chen", "sarah.chen@example.invalid"),
        ("\"Okafor, Sarah\" <s@example.invalid>", "Okafor, Sarah", "s@example.invalid"),
        ("bare@example.invalid", "", "bare@example.invalid"),
        ("Just A Name", "Just A Name", ""),
    ])
    func splitsSender(raw: String, name: String, address: String) {
        let (n, a) = MailMessageSummary.splitSender(raw)
        #expect(n == name)
        #expect(a == address)
    }

    @Test func decodesSearchReply() throws {
        let json = #"{"total":3,"messages":[{"id":13273,"messageID":"flowtest-002@example.invalid","subject":"[FlowTest] Lunch on Friday?","sender":"Sarah Okafor <sarah.okafor@example.invalid>","date":"2026-11-12T17:30:00.000Z","read":false,"account":null,"path":"Import/FlowTest"}]}"#
        let reply: JXAMailBackend.SearchReply = try JXAMailBackend.decode(Data(json.utf8))
        #expect(reply.total == 3)
        let s = reply.messages[0].summary
        #expect(s.ref == MailMessageRef(messageID: "flowtest-002@example.invalid", mailbox: MailboxRef(account: nil, path: "Import/FlowTest"), internalID: 13273))
        #expect(s.senderName == "Sarah Okafor")
        #expect(s.dateReceived == Date(timeIntervalSince1970: 1_794_504_600))
    }

    @Test func decodesScriptFailures() {
        func failure(_ json: String) -> MailError? {
            do {
                let _: JXAMailBackend.StatusReply = try JXAMailBackend.decode(Data(json.utf8))
                return nil
            } catch { return error }
        }
        #expect(failure(#"{"error":"gone"}"#) == .messageGone)
        #expect(failure(#"{"error":"mailboxNotFound","name":"X"}"#) == .mailboxNotFound("X"))
        #expect(failure(#"{"error":"ambiguousMailbox","name":"A","paths":["On My Mac/A","Work/A"]}"#)
            == .ambiguousMailbox("A", paths: ["On My Mac/A", "Work/A"]))
        #expect(failure("not json") == .scriptFailure(code: -1))
    }

    @Test(arguments: [
        ("execution error: Not authorized to send Apple events to Mail. (-1743)", MailError.automationDenied),
        ("execution error: ... (-1744)", .automationNotDetermined),
        ("execution error: Application isn’t running. (-600)", .launchFailed),
        ("execution error: AppleEvent timed out. (-1712)", .timedOut),
        ("execution error: Error: Can't get object. (-1728)", .scriptFailure(code: -1728)),
        ("garbage", .scriptFailure(code: 1)),
    ])
    func mapsOsascriptErrors(stderr: String, error: MailError) {
        #expect(OSAScriptRunner.mapError(stderr) == error)
    }
}

/// Exercises the real osascript runner with throwaway JavaScript (no Mail involved).
@Suite("OSAScriptRunner")
struct OSAScriptRunnerTests {
    @Test func passesArgumentAsData() async throws {
        let argument = #"{"x":"'; do shell script \"rm -rf ~\" --"}"#
        let out = try await OSAScriptRunner().run(javaScript: "function run(argv) { return JSON.parse(argv[0]).x }", argument: argument, timeout: .seconds(10))
        #expect(String(decoding: out, as: UTF8.self).trimmingCharacters(in: .newlines) == #"'; do shell script "rm -rf ~" --"#)
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let out = try await OSAScriptRunner().run(javaScript: "function run(argv) { return 'x'.repeat(200000) }", argument: "{}", timeout: .seconds(10))
        #expect(out.count >= 200_000)
    }

    @Test func timesOut() async {
        do {
            _ = try await OSAScriptRunner().run(javaScript: "function run(argv) { delay(5); return '' }", argument: "{}", timeout: .milliseconds(500))
            Issue.record("expected timeout")
        } catch {
            #expect(error == .timedOut)
        }
    }

    @Test func scriptErrorsAreMapped() async {
        do {
            _ = try await OSAScriptRunner().run(javaScript: "function run(argv) { throw new Error('boom') }", argument: "{}", timeout: .seconds(10))
            Issue.record("expected error")
        } catch {
            guard case .scriptFailure = error else { Issue.record("got \(error)"); return }
        }
    }
}
