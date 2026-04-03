import Foundation

/// Connects to Apple Mail via AppleScript to fetch emails and render them as .md files.
/// Emails are copied into the workspace, originals in Mail.app are never modified.
public struct AppleMailConnector: Sendable {

    public init() {}

    /// Check if Mail.app is running and AppleScript access is available.
    public func checkAccess() throws -> MailAccessStatus {
        let script = """
        tell application "System Events"
            set isRunning to (exists (processes where name is "Mail"))
        end tell
        return isRunning
        """
        let result = try runAppleScript(script)
        if result.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            return .available
        } else {
            return .mailNotRunning
        }
    }

    /// List all mailboxes (folders) in Mail.app.
    public func listMailboxes() throws -> [MailboxInfo] {
        let script = """
        set output to ""
        tell application "Mail"
            repeat with acct in accounts
                set acctName to name of acct
                repeat with mb in mailboxes of acct
                    set mbName to name of mb
                    set msgCount to count of messages of mb
                    set output to output & acctName & "|||" & mbName & "|||" & msgCount & linefeed
                end repeat
            end repeat
        end tell
        return output
        """

        let result = try runAppleScript(script)
        return result.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "|||")
                guard parts.count >= 3,
                      let count = Int(parts[2].trimmingCharacters(in: .whitespaces)) else { return nil }
                return MailboxInfo(
                    account: parts[0].trimmingCharacters(in: .whitespaces),
                    name: parts[1].trimmingCharacters(in: .whitespaces),
                    messageCount: count
                )
            }
    }

    /// Fetch messages from a mailbox, filtered by date range.
    /// Returns rendered .md content for each message.
    public func fetchMessages(
        account: String,
        mailbox: String,
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [RenderedEmail] {
        let dateFilter: String
        if let since = since {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            dateFilter = "date received of msg > date \"\(formatter.string(from: since))\""
        } else {
            dateFilter = "true"
        }

        let script = """
        set output to ""
        set msgCount to 0
        tell application "Mail"
            set targetMailbox to mailbox "\(mailbox)" of account "\(account)"
            repeat with msg in messages of targetMailbox
                if \(dateFilter) and msgCount < \(limit) then
                    set msgSubject to subject of msg
                    set msgSender to sender of msg
                    set msgDate to date received of msg
                    set msgContent to content of msg
                    set msgID to message id of msg
                    set recipientList to ""
                    repeat with r in to recipients of msg
                        set recipientList to recipientList & address of r & ", "
                    end repeat
                    set output to output & "===MSG_START===" & linefeed
                    set output to output & "ID: " & msgID & linefeed
                    set output to output & "From: " & msgSender & linefeed
                    set output to output & "To: " & recipientList & linefeed
                    set output to output & "Date: " & (msgDate as string) & linefeed
                    set output to output & "Subject: " & msgSubject & linefeed
                    set output to output & "---" & linefeed
                    set output to output & msgContent & linefeed
                    set output to output & "===MSG_END===" & linefeed
                    set msgCount to msgCount + 1
                end if
            end repeat
        end tell
        return output
        """

        let result = try runAppleScript(script)
        return parseMessages(result)
    }

    /// Render fetched emails as .md files into a target directory.
    /// Returns the list of written file URLs.
    public func renderToDirectory(emails: [RenderedEmail], directory: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var urls: [URL] = []
        for email in emails {
            let safeName = email.safeFileName
            let fileURL = directory.appendingPathComponent(safeName)

            let markdown = email.toMarkdown()
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

            // Set read-only
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
            urls.append(fileURL)
        }
        return urls
    }

    // MARK: - Private

    private func runAppleScript(_ source: String) throws -> String {
        let script = NSAppleScript(source: source)
        var errorDict: NSDictionary?
        let result = script?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let errorNum = error[NSAppleScript.errorNumber] as? Int ?? -1

            if errorNum == -1743 {
                throw ManifoldError.workspaceError("Mail access denied. Open System Settings > Privacy > Automation to grant Manifold access to Mail.")
            }
            if errorMsg.contains("not running") || errorMsg.contains("not find") {
                throw ManifoldError.workspaceError("Mail.app is not running. Please open Mail first.")
            }
            throw ManifoldError.workspaceError("AppleScript error: \(errorMsg)")
        }

        return result?.stringValue ?? ""
    }

    private func parseMessages(_ raw: String) -> [RenderedEmail] {
        let blocks = raw.components(separatedBy: "===MSG_START===")
        return blocks.compactMap { block in
            guard block.contains("===MSG_END===") else { return nil }
            let content = block.replacingOccurrences(of: "===MSG_END===", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }

            var email = RenderedEmail()
            let lines = content.components(separatedBy: "\n")
            var inBody = false

            for line in lines {
                if line == "---" {
                    inBody = true
                    continue
                }
                if !inBody {
                    if line.hasPrefix("ID: ") { email.messageID = String(line.dropFirst(4)) }
                    else if line.hasPrefix("From: ") { email.from = String(line.dropFirst(6)) }
                    else if line.hasPrefix("To: ") { email.to = String(line.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: ", ")) }
                    else if line.hasPrefix("Date: ") { email.date = String(line.dropFirst(6)) }
                    else if line.hasPrefix("Subject: ") { email.subject = String(line.dropFirst(9)) }
                } else {
                    email.body += line + "\n"
                }
            }
            return email.messageID != nil ? email : nil
        }
    }
}

// MARK: - Types

public enum MailAccessStatus: Sendable {
    case available
    case mailNotRunning
    case accessDenied
}

public struct MailboxInfo: Sendable {
    public let account: String
    public let name: String
    public let messageCount: Int
}

public struct RenderedEmail: Sendable {
    public var messageID: String?
    public var from: String = ""
    public var to: String = ""
    public var date: String = ""
    public var subject: String = ""
    public var body: String = ""

    public init(messageID: String? = nil, from: String = "", to: String = "", date: String = "", subject: String = "", body: String = "") {
        self.messageID = messageID
        self.from = from
        self.to = to
        self.date = date
        self.subject = subject
        self.body = body
    }

    public var safeFileName: String {
        let dateSlug = date.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
        let subjectSlug = subject
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
            .prefix(40)
        return "\(dateSlug)-\(subjectSlug).md"
    }

    public func toMarkdown() -> String {
        """
        ---
        from: \(from)
        to: \(to)
        date: \(date)
        subject: \(subject)
        message-id: \(messageID ?? "unknown")
        ---

        # \(subject)

        **From:** \(from)
        **To:** \(to)
        **Date:** \(date)

        ---

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}
