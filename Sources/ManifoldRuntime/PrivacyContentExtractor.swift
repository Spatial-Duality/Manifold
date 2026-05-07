// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CryptoKit
import Foundation
import ImageIO
import ManifoldKit
import PDFKit
import Vision

struct PrivacyExtractionResult: Sendable {
    let text: String?
    let mimeType: String?
    let extractor: String
    let extractStatus: PrivacyExtractStatus
    let contentHash: String?
    let lastError: String?
}

actor PrivacyContentExtractor {
    private let mailArchiveRoot: URL

    init(mailArchiveRoot: URL = EmailSyncEngine.mailArchiveRoot) {
        self.mailArchiveRoot = mailArchiveRoot
    }

    func extractSourceFile(
        source: SourceRecord,
        relativePath: String
    ) async -> PrivacyExtractionResult {
        let fileURL = URL(fileURLWithPath: source.effectiveRootPath).appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: nil,
                extractor: "missing",
                extractStatus: .failed,
                contentHash: nil,
                lastError: "File is missing."
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let hash = sha256(data)
            return await extract(data: data, fileExtension: fileURL.pathExtension.lowercased(), fileURL: fileURL, defaultHash: hash)
        } catch {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: nil,
                extractor: "file",
                extractStatus: .failed,
                contentHash: nil,
                lastError: error.localizedDescription
            )
        }
    }

    func extractEmailBody(_ email: EmailMessageRecord) async -> PrivacyExtractionResult {
        if let bodyText = nonEmpty(email.bodyText) {
            return PrivacyExtractionResult(
                text: bodyText,
                mimeType: email.contentType ?? "text/plain",
                extractor: "email-body-cache",
                extractStatus: .ready,
                contentHash: sha256(Data(bodyText.utf8)),
                lastError: nil
            )
        }

        guard let emlPath = email.emlPath,
              let data = EmailSyncEngine.readStoredMessage(at: emlPath) else {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: email.contentType,
                extractor: "email-body",
                extractStatus: .failed,
                contentHash: nil,
                lastError: "Stored email content is unavailable."
            )
        }

        let parsed = MIMEParser.parse(data: data)
        let body = parsed.textBody ?? parsed.htmlBody.map(stripHTML)
        return PrivacyExtractionResult(
            text: body?.prefix(128_000).description,
            mimeType: email.contentType ?? "text/plain",
            extractor: parsed.textBody != nil ? "email-text" : "email-html",
            extractStatus: body == nil ? .failed : .ready,
            contentHash: sha256(data),
            lastError: body == nil ? "Email body could not be extracted." : nil
        )
    }

    func extractEmailAttachment(
        _ attachment: EmailAttachmentRecord,
        email: EmailMessageRecord
    ) async -> PrivacyExtractionResult {
        if let attachmentBlobCID = attachment.attachmentBlobCID {
            do {
                let archive = try MailArchiveStore(rootURL: mailArchiveRoot)
                let data = try archive.readObject(
                    contentID: attachmentBlobCID,
                    accountID: email.accountID
                )
                return await extract(
                    data: data,
                    fileExtension: URL(fileURLWithPath: attachment.filename).pathExtension.lowercased(),
                    fileURL: nil,
                    defaultHash: attachment.contentHash
                )
            } catch {
                // Fall back to the canonical message path for dev/test recovery
                // and for rows created before attachment archive blobs existed.
            }
        }

        guard let emlPath = email.emlPath,
              let data = EmailSyncEngine.readStoredMessage(at: emlPath) else {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: attachment.mimeType,
                extractor: "email-attachment",
                extractStatus: .failed,
                contentHash: attachment.contentHash,
                lastError: "Stored email content is unavailable."
            )
        }

        let parsed = MIMEParser.parse(data: data)
        guard let matched = parsed.attachments.first(where: { sha256($0.data) == attachment.contentHash }) else {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: attachment.mimeType,
                extractor: "email-attachment",
                extractStatus: .failed,
                contentHash: attachment.contentHash,
                lastError: "Attachment data could not be located in the stored email."
            )
        }

        return await extract(
            data: matched.data,
            fileExtension: URL(fileURLWithPath: attachment.filename).pathExtension.lowercased(),
            fileURL: nil,
            defaultHash: attachment.contentHash
        )
    }

    private func extract(
        data: Data,
        fileExtension: String,
        fileURL: URL?,
        defaultHash: String
    ) async -> PrivacyExtractionResult {
        if let text = decodePlainText(data), shouldTreatAsPlainText(fileExtension: fileExtension, text: text) {
            let cleaned = fileExtension == "html" || fileExtension == "htm" ? stripHTML(text) : text
            return PrivacyExtractionResult(
                text: cleaned.prefix(128_000).description,
                mimeType: mimeType(for: fileExtension),
                extractor: fileExtension == "html" || fileExtension == "htm" ? "html" : "plain-text",
                extractStatus: .ready,
                contentHash: defaultHash,
                lastError: nil
            )
        }

        if fileExtension == "pdf", let fileURL {
            return await extractPDF(from: fileURL, defaultHash: defaultHash)
        }

        if fileExtension == "docx", let fileURL {
            return extractDOCX(from: fileURL, defaultHash: defaultHash)
        }

        if ["png", "jpg", "jpeg", "gif", "tiff", "heic", "bmp"].contains(fileExtension) {
            return await extractImageOCR(data: data, defaultHash: defaultHash, extractor: "image-ocr")
        }

        return PrivacyExtractionResult(
            text: nil,
            mimeType: mimeType(for: fileExtension),
            extractor: "unsupported",
            extractStatus: .unsupported,
            contentHash: defaultHash,
            lastError: "Unsupported file type for automatic privacy extraction."
        )
    }

    private func extractPDF(from fileURL: URL, defaultHash: String) async -> PrivacyExtractionResult {
        guard let document = PDFDocument(url: fileURL) else {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: "application/pdf",
                extractor: "pdf",
                extractStatus: .failed,
                contentHash: defaultHash,
                lastError: "PDF could not be opened."
            )
        }

        let pageCount = max(document.pageCount, 1)
        let extractedText = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        if extractedText.count / pageCount >= 32 {
            return PrivacyExtractionResult(
                text: extractedText.prefix(128_000).description,
                mimeType: "application/pdf",
                extractor: "pdf-text",
                extractStatus: .ready,
                contentHash: defaultHash,
                lastError: nil
            )
        }

        let ocrPageLimit = min(document.pageCount, 25)
        var ocrText: [String] = []
        for index in 0..<ocrPageLimit {
            guard let page = document.page(at: index) else { continue }
            if let pageText = await recognizeText(in: page) {
                ocrText.append(pageText)
            }
        }
        let combined = ocrText.joined(separator: "\n").prefix(128_000).description
        guard !combined.isEmpty else {
            return PrivacyExtractionResult(
                text: nonEmpty(extractedText),
                mimeType: "application/pdf",
                extractor: "pdf-text",
                extractStatus: extractedText.isEmpty ? .unsupported : .partial,
                contentHash: defaultHash,
                lastError: extractedText.isEmpty ? "PDF OCR did not produce text." : "OCR fallback yielded no additional text."
            )
        }

        return PrivacyExtractionResult(
            text: combined,
            mimeType: "application/pdf",
            extractor: "pdf-ocr",
            extractStatus: document.pageCount > ocrPageLimit ? .partial : .ready,
            contentHash: defaultHash,
            lastError: document.pageCount > ocrPageLimit ? "OCR limited to the first 25 pages." : nil
        )
    }

    private func extractDOCX(from fileURL: URL, defaultHash: String) -> PrivacyExtractionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", fileURL.path, "word/document.xml"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return PrivacyExtractionResult(
                    text: nil,
                    mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    extractor: "docx",
                    extractStatus: .failed,
                    contentHash: defaultHash,
                    lastError: errorText ?? "DOCX extraction failed."
                )
            }

            let xml = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let text = stripXML(xml)
            return PrivacyExtractionResult(
                text: nonEmpty(String(text.prefix(128_000))),
                mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                extractor: "docx",
                extractStatus: text.isEmpty ? .unsupported : .ready,
                contentHash: defaultHash,
                lastError: text.isEmpty ? "DOCX document XML was empty." : nil
            )
        } catch {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                extractor: "docx",
                extractStatus: .failed,
                contentHash: defaultHash,
                lastError: error.localizedDescription
            )
        }
    }

    private func extractImageOCR(
        data: Data,
        defaultHash: String,
        extractor: String
    ) async -> PrivacyExtractionResult {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: nil,
                extractor: extractor,
                extractStatus: .failed,
                contentHash: defaultHash,
                lastError: "Image could not be decoded for OCR."
            )
        }

        do {
            let text = try await recognizeText(in: cgImage)
            return PrivacyExtractionResult(
                text: nonEmpty(text),
                mimeType: nil,
                extractor: extractor,
                extractStatus: text.isEmpty ? .unsupported : .ready,
                contentHash: defaultHash,
                lastError: text.isEmpty ? "OCR returned no text." : nil
            )
        } catch {
            return PrivacyExtractionResult(
                text: nil,
                mimeType: nil,
                extractor: extractor,
                extractStatus: .failed,
                contentHash: defaultHash,
                lastError: error.localizedDescription
            )
        }
    }

    private func decodePlainText(_ data: Data) -> String? {
        if isBinary(data) {
            return nil
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? String(data: data, encoding: .utf16BigEndian)
    }

    private func shouldTreatAsPlainText(fileExtension: String, text: String) -> Bool {
        if ["txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cpp", "cc", "js", "ts", "tsx", "jsx", "json", "yaml", "yml", "toml", "xml", "csv", "log", "py", "rb", "go", "rs", "java", "kt", "sql", "sh", "zsh", "bash", "html", "htm"].contains(fileExtension) {
            return true
        }
        return !text.isEmpty
    }

    private func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripXML(_ xml: String) -> String {
        let withoutTags = xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mimeType(for fileExtension: String) -> String? {
        switch fileExtension {
        case "txt", "md", "swift", "json", "yaml", "yml", "csv", "log", "py", "xml":
            return "text/plain"
        case "html", "htm":
            return "text/html"
        case "pdf":
            return "application/pdf"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "tiff":
            return "image/tiff"
        default:
            return nil
        }
    }

    private func isBinary(_ data: Data) -> Bool {
        data.prefix(2_048).contains(0)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private func recognizeText(in page: PDFPage) async -> String? {
        let bounds = page.bounds(for: .mediaBox)
        let targetSize = CGSize(width: max(bounds.width, 1024), height: max(bounds.height, 1024))
        let image = page.thumbnail(of: targetSize, for: .mediaBox)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return try? await recognizeText(in: cgImage)
    }

    private func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let reply = SingleShotThrowingContinuation<String>(continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    reply.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                reply.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                reply.resume(throwing: error)
            }
        }
    }
}
