// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import ManifoldKit

@Suite("Read-only IMAP command safety")
struct ReadOnlyIMAPSessionTests {
    @Test("Allows expected read-only commands")
    func allowsReadOnlyCommands() throws {
        #expect(try IMAPCommandBuilder.build(.capability) == "CAPABILITY")
        #expect(try IMAPCommandBuilder.build(.noop) == "NOOP")
        #expect(try IMAPCommandBuilder.build(.examine(mailbox: "INBOX")) == #"EXAMINE "INBOX""#)
        #expect(try IMAPCommandBuilder.build(.uidSearch(criteria: "ALL")) == "UID SEARCH ALL")
        #expect(try IMAPCommandBuilder.build(.uidFetch(uidSet: "1:10", items: "UID FLAGS ENVELOPE RFC822.SIZE")) == "UID FETCH 1:10 (UID FLAGS ENVELOPE RFC822.SIZE)")
        #expect(try IMAPCommandBuilder.build(.uidFetch(uidSet: "42", items: "BODY.PEEK[]")) == "UID FETCH 42 (BODY.PEEK[])")
        #expect(try IMAPCommandBuilder.build(.uidFetch(uidSet: "1,2,42", items: "BODY.PEEK[]")) == "UID FETCH 1,2,42 (BODY.PEEK[])")
        #expect(try IMAPCommandBuilder.build(.enableQResync) == "ENABLE QRESYNC")
    }

    @Test("Rejects mutating commands")
    func rejectsMutatingCommands() {
        let commands = [
            "SELECT INBOX",
            "STORE 1 +FLAGS (\\Seen)",
            "UID STORE 1 +FLAGS (\\Seen)",
            "APPEND INBOX {10}",
            "COPY 1 Archive",
            "UID COPY 1 Archive",
            "MOVE 1 Archive",
            "UID MOVE 1 Archive",
            "EXPUNGE",
            "CLOSE",
            "CREATE Test",
            "DELETE Test",
            "RENAME A B",
            "SUBSCRIBE A",
            "UNSUBSCRIBE A",
            "CHECK",
        ]

        for command in commands {
            #expect(throws: ReadOnlyIMAPCommandError.self) {
                try IMAPCommandBuilder.assertReadOnly(command)
            }
        }
    }

    @Test("Rejects non-peek body fetches")
    func rejectsUnsafeFetches() throws {
        #expect(throws: ReadOnlyIMAPCommandError.self) {
            try IMAPCommandBuilder.build(.uidFetch(uidSet: "1", items: "BODY[]"))
        }
        #expect(throws: ReadOnlyIMAPCommandError.self) {
            try IMAPCommandBuilder.build(.uidFetch(uidSet: "1", items: "UID BODY[TEXT]"))
        }
        #expect(try IMAPCommandBuilder.build(.uidFetch(uidSet: "1", items: "UID BODY.PEEK[TEXT]")) == "UID FETCH 1 (UID BODY.PEEK[TEXT])")
    }

    @Test("Safe high watermark does not skip failed lower UIDs")
    func safeHighWatermarkDoesNotSkipFailedUIDs() {
        let searched: [UInt32] = [104, 103, 102, 101]
        let saved: Set<UInt32> = [104, 103, 101]
        let high = EmailSyncEngine.safeHighWatermark(previousLastUID: 100, searchedUIDs: searched, savedUIDs: saved)
        #expect(high == 101)
    }

    @Test("Safe high watermark advances through all saved returned UIDs")
    func safeHighWatermarkAdvancesThroughSavedUIDs() {
        let searched: [UInt32] = [104, 103, 101]
        let saved: Set<UInt32> = [104, 103, 101]
        let high = EmailSyncEngine.safeHighWatermark(previousLastUID: 100, searchedUIDs: searched, savedUIDs: saved)
        #expect(high == 104)
    }

    @Test("Recent pass high watermark tracks newest synced UID while older history remains")
    func recentPassHighWatermarkTracksNewestSyncedUID() {
        let high = EmailSyncEngine.nextHighWatermark(
            previousLastUID: 0,
            searchedUIDs: [500, 499, 498, 497],
            savedUIDs: [500, 499],
            mode: .recentPass(limitPerMailbox: 2),
            selectedUIDCount: 2,
            candidateUIDCount: 4
        )
        #expect(high == 500)
    }

    @Test("Recent pass does not skip failed UIDs when no historical backfill remains")
    func recentPassUsesSafeWatermarkWhenAllCandidatesWereSelected() {
        let high = EmailSyncEngine.nextHighWatermark(
            previousLastUID: 100,
            searchedUIDs: [104, 103, 102, 101],
            savedUIDs: [104, 103, 101],
            mode: .recentPass(limitPerMailbox: 1_000),
            selectedUIDCount: 4,
            candidateUIDCount: 4
        )
        #expect(high == 101)
    }

    @Test("Historical backfill does not move incremental high watermark")
    func historicalBackfillPreservesIncrementalHighWatermark() {
        let high = EmailSyncEngine.nextHighWatermark(
            previousLastUID: 500,
            searchedUIDs: [120, 119, 118],
            savedUIDs: [120, 119, 118],
            mode: .historicalBackfill(batchLimitPerMailbox: 1_000),
            selectedUIDCount: 3,
            candidateUIDCount: 3
        )
        #expect(high == 500)
    }
}
