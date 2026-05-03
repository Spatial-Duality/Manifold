// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import Testing
@testable import ManifoldKit
@testable import ManifoldXPC

@Suite("XPC JSON coding")
struct XPCCodingTypesTests {
    @Test("Encodable scalar fragments can be used inside command payloads")
    func encodableScalarFragmentsCanBeUsedInsideCommandPayloads() throws {
        let sortKeyObject = try XPCJSON.object(from: EmailSortKey.date)
        let filterObject = try XPCJSON.object(from: QuickFilter.flagged)

        #expect(sortKeyObject as? String == "date")
        #expect(filterObject as? String == "flagged")

        let payload: [String: Any] = [
            "tokens": try XPCJSON.object(from: [SearchToken]()),
            "freeText": "",
            "sortKey": sortKeyObject,
            "filter": filterObject,
            "limit": 25,
            "offset": 0,
        ]

        let data = try XPCJSON.data(from: payload)
        let decodedPayload = try XPCJSON.dictionary(from: data)
        let decodedSortKey = try XPCJSON.decode(EmailSortKey.self, from: decodedPayload["sortKey"] as Any)
        let decodedFilter = try XPCJSON.decode(QuickFilter.self, from: decodedPayload["filter"] as Any)

        #expect(decodedSortKey == .date)
        #expect(decodedFilter == .flagged)
    }

    @Test("Email message pages still round trip through object payloads")
    func emailMessagePagesRoundTripThroughObjectPayloads() throws {
        let page = EmailMessagePage(
            messages: [
                EmailMessageRecord(
                    emailID: "message-1",
                    accountID: "account-1",
                    mailbox: "INBOX",
                    sender: "Sender <sender@example.com>",
                    recipients: "reader@example.com",
                    subject: "Hello",
                    receivedAt: "2026-05-03T00:00:00Z",
                    sizeBytes: 42,
                    preview: "Preview",
                    isRead: true
                ),
            ],
            totalCount: 1,
            limit: 25,
            offset: 0
        )

        let object = try XPCJSON.object(from: page)
        let decoded = try XPCJSON.decode(EmailMessagePage.self, from: object)

        #expect(decoded.totalCount == 1)
        #expect(decoded.messages.first?.emailID == "message-1")
        #expect(decoded.messages.first?.isRead == true)
    }
}
