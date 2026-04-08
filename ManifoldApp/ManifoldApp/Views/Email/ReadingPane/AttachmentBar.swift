import SwiftUI
import ManifoldKit

struct AttachmentBar: View {
    let attachments: [MIMEParser.AttachmentPart]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            HStack {
                Text("Attachments (\(attachments.count))")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Save All...") {
                    saveAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, Spacing.edge)
            .padding(.top, Spacing.section)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.standard) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { _, att in
                        AttachmentCard(attachment: att)
                    }
                }
                .padding(.horizontal, Spacing.edge)
            }
            .padding(.bottom, Spacing.section)
        }
    }

    private func saveAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save All"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for att in attachments {
            let dest = dir.appendingPathComponent(att.filename)
            try? att.data.write(to: dest)
        }
    }
}

private struct AttachmentCard: View {
    let attachment: MIMEParser.AttachmentPart

    var body: some View {
        Button {
            saveAttachment()
        } label: {
            HStack(spacing: Spacing.tight) {
                Image(systemName: iconForMime(attachment.mimeType))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(Spacing.standard)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func saveAttachment() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? attachment.data.write(to: url)
    }

    private func iconForMime(_ mime: String) -> String {
        let lower = mime.lowercased()
        if lower.hasPrefix("image/") { return "photo" }
        if lower.contains("pdf") { return "doc.richtext" }
        if lower.contains("zip") || lower.contains("archive") { return "doc.zipper" }
        if lower.contains("text") { return "doc.text" }
        return "paperclip"
    }
}
