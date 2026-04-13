import Foundation

public enum MailboxResolver {
    public static func resolve(requestedName: String, imapMailboxes: [IMAPMailboxRecord]) -> String {
        let selectable = imapMailboxes
            .filter(\.isSelectable)
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.mailboxName.localizedCaseInsensitiveCompare($1.mailboxName) == .orderedAscending
            }

        if let folderType = requestedFolderType(for: requestedName),
           let typedMatch = selectable.first(where: { $0.folderType == folderType }) {
            return typedMatch.mailboxName
        }

        for alias in aliases(for: requestedName) {
            if let aliasMatch = selectable.first(where: { $0.mailboxName.caseInsensitiveCompare(alias) == .orderedSame }) {
                return aliasMatch.mailboxName
            }
        }

        if let exactMatch = selectable.first(where: { $0.mailboxName.caseInsensitiveCompare(requestedName) == .orderedSame }) {
            return exactMatch.mailboxName
        }

        return requestedName
    }

    private static func requestedFolderType(for name: String) -> IMAPMailboxRecord.FolderType? {
        switch name.uppercased() {
        case "INBOX":
            return .inbox
        case "SENT":
            return .sent
        case "DRAFTS":
            return .drafts
        case "TRASH":
            return .trash
        case "ARCHIVE":
            return .archive
        default:
            return nil
        }
    }

    private static func aliases(for requestedName: String) -> [String] {
        switch requestedName.uppercased() {
        case "INBOX":
            return ["INBOX"]
        case "SENT":
            return ["Sent", "Sent Messages", "Sent Mail", "Sent Items"]
        case "DRAFTS":
            return ["Drafts", "Draft Messages", "Draft Items"]
        case "TRASH":
            return ["Trash", "Deleted Messages", "Deleted Items", "Bin"]
        case "ARCHIVE":
            return ["Archive", "All Mail", "All Messages"]
        default:
            return [requestedName]
        }
    }
}
