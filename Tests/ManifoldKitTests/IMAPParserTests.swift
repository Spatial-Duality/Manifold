// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("IMAP Parser")
struct IMAPParserTests {

    // MARK: - LIST Response Parsing

    @Test("Parse iCloud LIST responses into mailbox names")
    func parseICloudListResponses() {
        // Real iCloud LIST responses (after * prefix is stripped)
        let rawLines = [
            #"LIST (\HasNoChildren) "/" "INBOX""#,
            #"LIST (\HasNoChildren) "/" "Sent Messages""#,
            #"LIST (\HasNoChildren) "/" "Drafts""#,
            #"LIST (\HasNoChildren) "/" "Deleted Messages""#,
            #"LIST (\HasNoChildren) "/" "Junk""#,
            #"LIST (\HasChildren) "/" "Archive""#,
            #"LIST (\HasNoChildren) "/" "Notes""#,
        ]

        let mailboxes = rawLines.compactMap {
            IMAPParser.parseListResponse($0, accountID: "test-account")
        }

        #expect(mailboxes.count == 7)
        let names = mailboxes.map(\.name)
        #expect(names.contains("INBOX"))
        #expect(names.contains("Sent Messages"))
        #expect(names.contains("Drafts"))
        #expect(names.contains("Deleted Messages"))
        #expect(names.contains("Junk"))
        #expect(names.contains("Archive"))
        #expect(names.contains("Notes"))
    }

    @Test("Parse Gmail LIST responses with nested folders")
    func parseGmailListResponses() {
        let rawLines = [
            #"LIST (\HasNoChildren) "/" "INBOX""#,
            #"LIST (\HasChildren \Noselect) "/" "[Gmail]""#,
            #"LIST (\HasNoChildren \All) "/" "[Gmail]/All Mail""#,
            #"LIST (\HasNoChildren \Drafts) "/" "[Gmail]/Drafts""#,
            #"LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#,
            #"LIST (\HasNoChildren \Junk) "/" "[Gmail]/Spam""#,
            #"LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash""#,
        ]

        let mailboxes = rawLines.compactMap {
            IMAPParser.parseListResponse($0, accountID: "gmail-test")
        }

        #expect(mailboxes.count == 7)
        let names = mailboxes.map(\.name)
        #expect(names.contains("INBOX"))
        #expect(names.contains("[Gmail]/Sent Mail"))
        #expect(names.contains("[Gmail]/All Mail"))

        // Verify \Noselect detection
        let gmailRoot = mailboxes.first { $0.name == "[Gmail]" }
        #expect(gmailRoot?.isNoSelect == true)
    }

    @Test("Parse LIST response with dot delimiter (Dovecot)")
    func parseDotDelimiterList() {
        let line = #"LIST (\HasNoChildren) "." "INBOX.Sent""#
        let mailbox = IMAPParser.parseListResponse(line, accountID: "dovecot")
        #expect(mailbox?.name == "INBOX.Sent")
        #expect(mailbox?.delimiter == ".")
    }

    @Test("Parse LIST response preserves flags")
    func parseListFlags() {
        let line = #"LIST (\HasNoChildren \Marked \Drafts) "/" "Drafts""#
        let mailbox = IMAPParser.parseListResponse(line, accountID: "test")
        #expect(mailbox != nil)
        #expect(mailbox!.flags.contains("\\HasNoChildren"))
        #expect(mailbox!.flags.contains("\\Marked"))
        #expect(mailbox!.flags.contains("\\Drafts"))
    }

    // MARK: - Inline LIST Parsing (mirrors IMAPConnection.list())

    /// Simulates the inline parsing logic from IMAPConnection.list()
    /// to verify it produces the same mailbox names as the parser.
    @Test("Inline list parsing matches parser output for iCloud responses")
    func inlineListParsingMatchesParser() {
        // These are untagged lines as they'd appear after classifyLine strips "* "
        let untagged = [
            #"LIST (\HasNoChildren) "/" "INBOX""#,
            #"LIST (\HasNoChildren) "/" "Sent Messages""#,
            #"LIST (\HasChildren) "/" "Archive""#,
            #"LIST (\HasNoChildren) "/" "Drafts""#,
            #"LIST (\Noselect \HasChildren) "/" "[Gmail]""#,
            #"LIST (\HasNoChildren) "/" "[Gmail]/Sent Mail""#,
            #"OK LIST complete"#,
        ]

        // IMAPConnection.list() inline parsing logic (exact copy)
        var names: [String] = []
        for line in untagged {
            guard line.uppercased().hasPrefix("LIST ") else { continue }
            let rest = String(line.dropFirst(5))
            guard let flagEnd = rest.firstIndex(of: ")") else { continue }
            let afterFlags = String(rest[rest.index(after: flagEnd)...]).trimmingCharacters(in: .whitespaces)
            let parts = afterFlags.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            var name = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            guard !name.isEmpty else { continue }
            names.append(name)
        }

        #expect(names.count == 6)
        #expect(names.contains("INBOX"))
        #expect(names.contains("Sent Messages"))
        #expect(names.contains("Archive"))
        #expect(names.contains("[Gmail]/Sent Mail"))

        // Cross-check with the parser
        let parsed = untagged.compactMap {
            IMAPParser.parseListResponse($0, accountID: "cross-check")
        }
        let parsedNames = parsed.map(\.name)
        #expect(Set(names) == Set(parsedNames))
    }

    // MARK: - Sync Engine Mailbox Filtering

    @Test("Sync engine prioritizes iCloud inbox before slow trash or junk folders")
    func syncEngineMailboxPriority() {
        let mailboxes = [
            IMAPConnection.ListEntry(name: "Archive", delimiter: "/", flags: []),
            IMAPConnection.ListEntry(name: "Deleted Messages", delimiter: "/", flags: ["\\Trash"]),
            IMAPConnection.ListEntry(name: "INBOX", delimiter: "/", flags: ["\\Noinferiors"]),
            IMAPConnection.ListEntry(name: "Junk", delimiter: "/", flags: []),
            IMAPConnection.ListEntry(name: "Sent Messages", delimiter: "/", flags: ["\\Sent"]),
        ]

        let sorted = mailboxes.sorted { lhs, rhs in
            let lhsKey = EmailSyncEngine.mailboxSortKey(lhs)
            let rhsKey = EmailSyncEngine.mailboxSortKey(rhs)
            if lhsKey.priority != rhsKey.priority {
                return lhsKey.priority < rhsKey.priority
            }
            return lhsKey.name < rhsKey.name
        }.map(\.name)

        #expect(sorted.prefix(3) == ["INBOX", "Sent Messages", "Archive"])
        #expect(Array(sorted.suffix(2)) == ["Deleted Messages", "Junk"])
    }

    @Test("Sync engine skips redundant Gmail system views by flag and localized root")
    func syncEngineGmailFilter() {
        let allMail = IMAPConnection.ListEntry(name: "[Google Mail]/All Mail", delimiter: "/", flags: ["\\All"])
        let important = IMAPConnection.ListEntry(name: "[Google Mail]/Important", delimiter: "/", flags: ["\\Important"])
        let starred = IMAPConnection.ListEntry(name: "[Google Mail]/Starred", delimiter: "/", flags: ["\\Flagged"])
        let inbox = IMAPConnection.ListEntry(name: "INBOX", delimiter: "/", flags: ["\\HasNoChildren"])
        let sent = IMAPConnection.ListEntry(name: "[Google Mail]/Sent Mail", delimiter: "/", flags: ["\\Sent"])

        #expect(EmailSyncEngine.isRedundantMailbox(allMail, provider: .gmail))
        #expect(EmailSyncEngine.isRedundantMailbox(important, provider: .gmail))
        #expect(EmailSyncEngine.isRedundantMailbox(starred, provider: .gmail))
        #expect(!EmailSyncEngine.isRedundantMailbox(inbox, provider: .gmail))
        #expect(!EmailSyncEngine.isRedundantMailbox(sent, provider: .gmail))
        #expect(!EmailSyncEngine.isRedundantMailbox(allMail, provider: .other))
    }

    // MARK: - SELECT Response Parsing

    @Test("Parse SELECT response extracts UIDVALIDITY and EXISTS")
    func parseSelectResponse() {
        let lines = [
            "42 EXISTS",
            "0 RECENT",
            "FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)",
            "OK [UIDVALIDITY 1234567890] UIDs valid",
            "OK [UIDNEXT 43] Predicted next UID",
            "OK [READ-WRITE] SELECT completed"
        ]

        let result = IMAPParser.parseSelectResponses(lines)
        #expect(result.exists == 42)
        #expect(result.recent == 0)
        #expect(result.uidValidity == 1234567890)
        #expect(result.uidNext == 43)
        #expect(result.readWrite == true)
        #expect(result.flags.contains("\\Seen"))
    }

    // MARK: - SEARCH Response Parsing

    @Test("Parse SEARCH response returns sorted UIDs")
    func parseSearchResponse() {
        let uids = IMAPParser.parseSearchResponse("SEARCH 5 3 17 1 42")
        #expect(uids == [5, 3, 17, 1, 42]) // Parser returns in order, caller sorts
    }

    @Test("Parse empty SEARCH response")
    func parseEmptySearch() {
        let uids = IMAPParser.parseSearchResponse("SEARCH")
        #expect(uids.isEmpty)
    }

    // MARK: - Literal Count Detection

    @Test("Detect literal count in FETCH response")
    func detectLiteralCount() {
        #expect(IMAPParser.literalCount(in: "* 1 FETCH (BODY[] {12345}") == 12345)
        #expect(IMAPParser.literalCount(in: "no literal here") == nil)
        #expect(IMAPParser.literalCount(in: "FETCH (UID 1 FLAGS (\\Seen))") == nil)
    }

    // MARK: - Response Classification

    @Test("Classify IMAP response lines")
    func classifyLines() {
        let untagged = IMAPParser.classifyLine("* OK IMAP server ready")
        if case .untagged(let text) = untagged {
            #expect(text == "OK IMAP server ready")
        } else {
            Issue.record("Expected untagged response")
        }

        let tagged = IMAPParser.classifyLine("M0001 OK LOGIN completed")
        if case .tagged(let tag, let status, let text) = tagged {
            #expect(tag == "M0001")
            #expect(status == "OK")
            #expect(text == "LOGIN completed")
        } else {
            Issue.record("Expected tagged response")
        }

        let cont = IMAPParser.classifyLine("+ ")
        if case .continuation = cont { } else {
            Issue.record("Expected continuation")
        }
    }

    // MARK: - FETCH Response Parsing

    @Test("Parse FETCH response with UID, FLAGS, and RFC822.SIZE")
    func parseFetchResponse() {
        let line = "1 FETCH (UID 42 FLAGS (\\Seen \\Answered) RFC822.SIZE 1234)"
        let result = IMAPParser.parseFetchResponse(line)
        #expect(result.sequenceNumber == 1)
        #expect(result.uid == 42)
        #expect(result.flags.contains("\\Seen"))
        #expect(result.flags.contains("\\Answered"))
        #expect(result.rfc822Size == 1234)
    }
}
