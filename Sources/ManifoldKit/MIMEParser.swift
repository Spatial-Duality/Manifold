import Foundation

/// Parses raw RFC 822 email messages into structured MIME parts.
/// Handles multipart/mixed, multipart/alternative, base64, quoted-printable,
/// and charset decoding. No external dependencies.
public struct MIMEParser: Sendable {

    /// A parsed MIME part — either text content or an attachment.
    public enum MIMEPart: Sendable {
        case text(TextPart)
        case attachment(AttachmentPart)
    }

    public struct TextPart: Sendable {
        public let mimeType: String   // "text/plain" or "text/html"
        public let charset: String
        public let content: String
    }

    public struct AttachmentPart: Sendable {
        public let filename: String
        public let mimeType: String
        public let data: Data
        public let size: Int
        public let contentID: String?  // for inline images
    }

    /// Result of parsing a full RFC 822 message.
    public struct ParsedEmail: Sendable {
        public let headers: [String: String]
        public let textBody: String?       // best text/plain content
        public let htmlBody: String?       // best text/html content
        public let attachments: [AttachmentPart]
        public let allParts: [MIMEPart]
    }

    // MARK: - Public API

    /// Parse a raw RFC 822 message into structured parts.
    public static func parse(data: Data) -> ParsedEmail {
        guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            return ParsedEmail(headers: [:], textBody: nil, htmlBody: nil, attachments: [], allParts: [])
        }
        return parse(raw: raw)
    }

    /// Parse from a raw string.
    public static func parse(raw: String) -> ParsedEmail {
        let (headers, body) = splitHeadersAndBody(raw)
        let contentType = headers["content-type"] ?? "text/plain"
        let encoding = headers["content-transfer-encoding"] ?? "7bit"

        // Check if this is multipart
        if let boundary = extractBoundary(from: contentType) {
            let parts = parseMultipart(body: body, boundary: boundary)
            return assembleParsedEmail(headers: headers, parts: parts)
        }

        // Single-part message
        let decoded = decodeBody(body, encoding: encoding, contentType: contentType)
        let mimeType = extractMimeType(from: contentType).lowercased()

        if mimeType.hasPrefix("text/") {
            let charset = extractParam(from: contentType, name: "charset") ?? "utf-8"
            let part = MIMEPart.text(TextPart(mimeType: mimeType, charset: charset, content: decoded))
            return assembleParsedEmail(headers: headers, parts: [part])
        } else {
            // Single non-text part (unusual but possible)
            let filename = extractFilename(from: contentType, disposition: headers["content-disposition"])
            if let binaryData = Data(base64Encoded: body.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "\n", with: "")) {
                let att = AttachmentPart(filename: filename, mimeType: mimeType, data: binaryData, size: binaryData.count, contentID: headers["content-id"])
                return assembleParsedEmail(headers: headers, parts: [.attachment(att)])
            }
            return ParsedEmail(headers: headers, textBody: decoded, htmlBody: nil, attachments: [], allParts: [])
        }
    }

    // MARK: - Header/Body Split

    static func splitHeadersAndBody(_ raw: String) -> ([String: String], String) {
        // Headers and body are separated by a blank line (\r\n\r\n or \n\n)
        if let range = raw.range(of: "\r\n\r\n") {
            let headerSection = String(raw[raw.startIndex..<range.lowerBound])
            let bodySection = String(raw[range.upperBound...])
            return (parseHeaders(headerSection, lineEnding: "\r\n"), bodySection)
        } else if let range = raw.range(of: "\n\n") {
            let headerSection = String(raw[raw.startIndex..<range.lowerBound])
            let bodySection = String(raw[range.upperBound...])
            return (parseHeaders(headerSection, lineEnding: "\n"), bodySection)
        }
        // No body
        return (parseHeaders(raw, lineEnding: "\n"), "")
    }

    static func parseHeaders(_ section: String, lineEnding: String) -> [String: String] {
        var headers: [String: String] = [:]
        // Unfold continuation lines (lines starting with whitespace are continuations)
        let unfolded = section
            .replacingOccurrences(of: "\(lineEnding)\t", with: " ")
            .replacingOccurrences(of: "\(lineEnding) ", with: " ")

        let lines = unfolded.components(separatedBy: lineEnding)
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    // MARK: - Multipart Parsing

    static func parseMultipart(body: String, boundary: String) -> [MIMEPart] {
        let delimiter = "--\(boundary)"
        let endDelimiter = "--\(boundary)--"

        // Split on boundary
        let sections = body.components(separatedBy: delimiter)
        var parts: [MIMEPart] = []

        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "--" || trimmed.hasPrefix("--") && trimmed.count < 5 { continue }

            // Remove trailing end delimiter marker
            let cleaned: String
            if let endRange = trimmed.range(of: endDelimiter) {
                cleaned = String(trimmed[trimmed.startIndex..<endRange.lowerBound])
            } else {
                // Strip leading "--\r\n" or "--\n" that may remain
                cleaned = trimmed.hasPrefix("--") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .newlines) : trimmed
            }

            if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            let (partHeaders, partBody) = splitHeadersAndBody(cleaned)
            let partContentType = partHeaders["content-type"] ?? "text/plain"
            let partEncoding = partHeaders["content-transfer-encoding"] ?? "7bit"
            let partMimeType = extractMimeType(from: partContentType).lowercased()

            // Nested multipart
            if let nestedBoundary = extractBoundary(from: partContentType) {
                let nested = parseMultipart(body: partBody, boundary: nestedBoundary)
                parts.append(contentsOf: nested)
                continue
            }

            // Check if this is an attachment
            let disposition = partHeaders["content-disposition"] ?? ""
            let isAttachment = disposition.lowercased().contains("attachment")
                || disposition.lowercased().contains("filename")
                || (!partMimeType.hasPrefix("text/") && partContentType.lowercased().contains("name="))

            if isAttachment || (!partMimeType.hasPrefix("text/") && !partMimeType.hasPrefix("multipart/")) {
                let filename = extractFilename(from: partContentType, disposition: disposition)
                let decoded = decodeAttachmentData(partBody, encoding: partEncoding)
                let contentID = partHeaders["content-id"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                parts.append(.attachment(AttachmentPart(
                    filename: filename,
                    mimeType: partMimeType,
                    data: decoded,
                    size: decoded.count,
                    contentID: contentID
                )))
            } else {
                let charset = extractParam(from: partContentType, name: "charset") ?? "utf-8"
                let decoded = decodeBody(partBody, encoding: partEncoding, contentType: partContentType)
                parts.append(.text(TextPart(mimeType: partMimeType, charset: charset, content: decoded)))
            }
        }

        return parts
    }

    // MARK: - Content Transfer Encoding

    static func decodeBody(_ body: String, encoding: String, contentType: String) -> String {
        let enc = encoding.lowercased().trimmingCharacters(in: .whitespaces)
        switch enc {
        case "base64":
            let cleaned = body.replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: cleaned) else { return body }
            let charset = extractParam(from: contentType, name: "charset") ?? "utf-8"
            return String(data: data, encoding: charsetToEncoding(charset)) ?? String(data: data, encoding: .utf8) ?? body
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body
        }
    }

    static func decodeAttachmentData(_ body: String, encoding: String) -> Data {
        let enc = encoding.lowercased().trimmingCharacters(in: .whitespaces)
        switch enc {
        case "base64":
            let cleaned = body
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\r\n", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: " ", with: "")
            return Data(base64Encoded: cleaned) ?? Data(body.utf8)
        case "quoted-printable":
            return Data(decodeQuotedPrintable(body).utf8)
        default:
            return Data(body.utf8)
        }
    }

    static func decodeQuotedPrintable(_ input: String) -> String {
        var result = ""
        var i = input.startIndex

        while i < input.endIndex {
            let c = input[i]
            if c == "=" {
                // Need at least 1 char after "="
                let n1 = input.index(after: i)
                guard n1 < input.endIndex else {
                    result.append(c)
                    break
                }

                // Soft line break: =\r\n or =\n
                if input[n1] == "\n" {
                    i = input.index(after: n1)
                    continue
                }
                if input[n1] == "\r" {
                    let n2 = input.index(after: n1)
                    if n2 < input.endIndex && input[n2] == "\n" {
                        i = input.index(after: n2)
                    } else {
                        i = n2
                    }
                    continue
                }

                // Hex encoded byte: =XX — need 2 chars after "="
                let n2 = input.index(after: n1)
                guard n2 < input.endIndex else {
                    // Malformed QP at end of string, keep as-is
                    result.append(c)
                    result.append(input[n1])
                    i = n2
                    continue
                }

                let hex = String(input[n1]) + String(input[n2])
                if let byte = UInt8(hex, radix: 16) {
                    result.append(Character(UnicodeScalar(byte)))
                    i = input.index(after: n2)
                    continue
                }
                // Not valid hex, keep the "=" and move on
                result.append(c)
                i = n1
                continue
            }
            result.append(c)
            i = input.index(after: i)
        }

        return result
    }

    // MARK: - Helpers

    static func extractBoundary(from contentType: String) -> String? {
        guard contentType.lowercased().contains("multipart/") else { return nil }
        return extractParam(from: contentType, name: "boundary")
    }

    static func extractMimeType(from contentType: String) -> String {
        // "text/plain; charset=utf-8" → "text/plain"
        let parts = contentType.components(separatedBy: ";")
        return parts[0].trimmingCharacters(in: .whitespaces)
    }

    static func extractParam(from header: String, name: String) -> String? {
        let lower = header.lowercased()
        let search = "\(name.lowercased())="
        guard let range = lower.range(of: search) else { return nil }
        let afterEquals = header[range.upperBound...]
        // May be quoted or unquoted
        if afterEquals.hasPrefix("\"") {
            let unquoted = afterEquals.dropFirst()
            if let endQuote = unquoted.firstIndex(of: "\"") {
                return String(unquoted[unquoted.startIndex..<endQuote])
            }
            return String(unquoted)
        }
        // Unquoted: take until semicolon, space, or end
        let value = afterEquals.prefix(while: { $0 != ";" && $0 != " " && $0 != "\r" && $0 != "\n" })
        return String(value)
    }

    static func extractFilename(from contentType: String, disposition: String?) -> String {
        // Try Content-Disposition: attachment; filename="report.pdf"
        if let disp = disposition, let name = extractParam(from: disp, name: "filename") {
            return sanitizeFilename(name)
        }
        // Try Content-Type: application/pdf; name="report.pdf"
        if let name = extractParam(from: contentType, name: "name") {
            return sanitizeFilename(name)
        }
        // Fallback: generate from mime type
        let mimeType = extractMimeType(from: contentType)
        let ext = mimeExtension(for: mimeType)
        return "attachment.\(ext)"
    }

    static func sanitizeFilename(_ name: String) -> String {
        // Decode RFC 2047 if present
        var decoded = name
        if decoded.contains("=?") {
            decoded = IMAPParser.decodeEnvelopeString(name)
        }
        // Remove path separators and null bytes
        return decoded
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func mimeExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "application/pdf": return "pdf"
        case "application/zip": return "zip"
        case "application/msword": return "doc"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.ms-excel": return "xls"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.ms-powerpoint": return "ppt"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "text/csv": return "csv"
        case "text/html": return "html"
        case "text/plain": return "txt"
        case "application/json": return "json"
        case "application/xml", "text/xml": return "xml"
        default: return "bin"
        }
    }

    static func charsetToEncoding(_ charset: String) -> String.Encoding {
        switch charset.uppercased() {
        case "UTF-8", "UTF8": return .utf8
        case "ISO-8859-1", "LATIN1", "LATIN-1": return .isoLatin1
        case "ISO-8859-2": return .isoLatin2
        case "US-ASCII", "ASCII": return .ascii
        case "WINDOWS-1252", "CP1252": return .windowsCP1252
        case "WINDOWS-1251", "CP1251": return .windowsCP1251
        case "ISO-8859-15": return .isoLatin1 // close enough
        default: return .utf8
        }
    }

    // MARK: - Assembly

    static func assembleParsedEmail(headers: [String: String], parts: [MIMEPart]) -> ParsedEmail {
        var textBody: String?
        var htmlBody: String?
        var attachments: [AttachmentPart] = []

        for part in parts {
            switch part {
            case .text(let text):
                if text.mimeType == "text/plain" && textBody == nil {
                    textBody = text.content
                } else if text.mimeType == "text/html" && htmlBody == nil {
                    htmlBody = text.content
                }
            case .attachment(let att):
                attachments.append(att)
            }
        }

        return ParsedEmail(
            headers: headers,
            textBody: textBody,
            htmlBody: htmlBody,
            attachments: attachments,
            allParts: parts
        )
    }
}
