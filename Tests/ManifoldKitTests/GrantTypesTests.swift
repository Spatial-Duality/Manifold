// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
import Foundation
@testable import ManifoldKit

@Suite("GrantTypes")
struct GrantTypesTests {

    // MARK: - IMAPMailboxRecord.folderType

    /// Helper to create an IMAPMailboxRecord from minimal fields.
    private func makeMailbox(name: String, flags: [String] = []) -> IMAPMailboxRecord? {
        let flagsJSON = try! JSONSerialization.data(withJSONObject: flags)
        let flagsString = String(data: flagsJSON, encoding: .utf8)!
        return IMAPMailboxRecord(row: [
            "account_id": "test",
            "mailbox_name": name,
            "flags": flagsString,
            "is_selectable": "1",
            "sort_order": "0",
        ])
    }

    @Test("folderType detects inbox from IMAP flag")
    func folderTypeInboxFlag() {
        let mailbox = makeMailbox(name: "INBOX", flags: ["\\Inbox"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .inbox)
    }

    @Test("folderType detects inbox from mailbox name")
    func folderTypeInboxName() {
        let mailbox = makeMailbox(name: "INBOX")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .inbox)
    }

    @Test("folderType detects sent from IMAP flag")
    func folderTypeSentFlag() {
        let mailbox = makeMailbox(name: "Sent Messages", flags: ["\\Sent"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .sent)
    }

    @Test("folderType detects sent from name heuristic")
    func folderTypeSentName() {
        let mailbox = makeMailbox(name: "Sent Mail")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .sent)
    }

    @Test("folderType detects drafts from IMAP flag")
    func folderTypeDraftsFlag() {
        let mailbox = makeMailbox(name: "My Drafts", flags: ["\\Drafts"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .drafts)
    }

    @Test("folderType detects drafts from name heuristic")
    func folderTypeDraftsName() {
        let mailbox = makeMailbox(name: "Drafts")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .drafts)
    }

    @Test("folderType detects trash from IMAP flag")
    func folderTypeTrashFlag() {
        let mailbox = makeMailbox(name: "Bin", flags: ["\\Trash"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .trash)
    }

    @Test("folderType detects trash from name heuristic")
    func folderTypeTrashName() {
        let mailbox = makeMailbox(name: "Deleted Items")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .trash)
    }

    @Test("folderType detects junk from IMAP flag")
    func folderTypeJunkFlag() {
        let mailbox = makeMailbox(name: "Bulk", flags: ["\\Junk"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .junk)
    }

    @Test("folderType detects junk from name heuristic")
    func folderTypeJunkName() {
        let mailbox = makeMailbox(name: "Spam")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .junk)
    }

    @Test("folderType detects archive from IMAP flag")
    func folderTypeArchiveFlag() {
        let mailbox = makeMailbox(name: "All Mail", flags: ["\\All"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .archive)
    }

    @Test("folderType detects archive from \\Archive flag")
    func folderTypeArchiveFlagExplicit() {
        let mailbox = makeMailbox(name: "Old Stuff", flags: ["\\Archive"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .archive)
    }

    @Test("folderType detects archive from name heuristic")
    func folderTypeArchiveName() {
        let mailbox = makeMailbox(name: "Archive")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .archive)
    }

    @Test("folderType returns .other for custom folders")
    func folderTypeCustom() {
        let mailbox = makeMailbox(name: "Receipts")
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .other)
    }

    @Test("folderType returns .other for unknown flags")
    func folderTypeUnknownFlags() {
        let mailbox = makeMailbox(name: "Work", flags: ["\\HasChildren"])
        #expect(mailbox != nil)
        #expect(mailbox!.folderType == .other)
    }

    // MARK: - FolderType.systemImage

    @Test("FolderType.systemImage returns non-empty strings for all cases")
    func folderTypeSystemImages() {
        let allTypes: [IMAPMailboxRecord.FolderType] = [
            .inbox, .sent, .drafts, .trash, .junk, .archive, .flagged, .other,
        ]
        for type in allTypes {
            #expect(!type.systemImage.isEmpty, "systemImage should not be empty for \(type)")
        }
    }

    // MARK: - QuickFilter.displayName

    @Test("QuickFilter.displayName returns non-empty for all cases")
    func quickFilterDisplayNames() {
        for filter in QuickFilter.allCases {
            #expect(!filter.displayName.isEmpty, "displayName should not be empty for \(filter)")
        }
    }

    // MARK: - RuleCondition.isValid

    @Test("RuleCondition.isValid returns true for allowed fields")
    func ruleConditionValidFields() {
        let validFields = ["sender", "sender_email", "sender_domain", "subject",
                           "body_text", "is_read", "is_flagged", "is_junk",
                           "mailbox", "attachment_count", "size_bytes", "shared"]
        for field in validFields {
            let condition = RuleCondition(field: field, op: .equals, value: "test")
            #expect(condition.isValid, "field '\(field)' should be valid")
        }
    }

    @Test("RuleCondition.isValid returns false for invalid field names")
    func ruleConditionInvalidFields() {
        let invalidFields = [
            "sender; DROP TABLE",
            "nonexistent_field",
            "",
            "SELECT *",
            "password",
        ]
        for field in invalidFields {
            let condition = RuleCondition(field: field, op: .equals, value: "test")
            #expect(!condition.isValid, "field '\(field)' should be invalid")
        }
    }

    // MARK: - SmartMailboxRules toJSON() roundtrip

    @Test("SmartMailboxRules toJSON() produces valid JSON that roundtrips")
    func smartMailboxRulesToJSONRoundtrip() throws {
        let rules = SmartMailboxRules(
            match: .all,
            conditions: [
                RuleCondition(field: "sender_domain", op: .equals, value: "work.com"),
                RuleCondition(field: "subject", op: .contains, value: "Invoice"),
            ]
        )

        let json = rules.toJSON()
        #expect(json != nil)

        // Verify it's valid JSON by deserializing
        let data = try #require(json?.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SmartMailboxRules.self, from: data)

        #expect(decoded.match == .all)
        #expect(decoded.conditions.count == 2)
        #expect(decoded.conditions[0].field == "sender_domain")
        #expect(decoded.conditions[0].op == .equals)
        #expect(decoded.conditions[0].value == "work.com")
        #expect(decoded.conditions[1].field == "subject")
        #expect(decoded.conditions[1].op == .contains)
        #expect(decoded.conditions[1].value == "Invoice")
    }

    @Test("SmartMailboxRules toJSON() with .any match type roundtrips")
    func smartMailboxRulesAnyMatchRoundtrip() throws {
        let rules = SmartMailboxRules(
            match: .any,
            conditions: [
                RuleCondition(field: "is_flagged", op: .equals, value: "1"),
            ]
        )

        let json = rules.toJSON()
        #expect(json != nil)

        let data = try #require(json?.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SmartMailboxRules.self, from: data)

        #expect(decoded.match == .any)
        #expect(decoded.conditions.count == 1)
    }

    @Test("SmartMailboxRules toJSON() with empty conditions roundtrips")
    func smartMailboxRulesEmptyConditionsRoundtrip() throws {
        let rules = SmartMailboxRules(match: .all, conditions: [])

        let json = rules.toJSON()
        #expect(json != nil)

        let data = try #require(json?.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SmartMailboxRules.self, from: data)

        #expect(decoded.match == .all)
        #expect(decoded.conditions.isEmpty)
    }
}
