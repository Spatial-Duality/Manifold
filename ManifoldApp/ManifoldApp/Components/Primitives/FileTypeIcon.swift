// Copyright 2026 Spatial Duality
// SPDX-License-Identifier: Apache-2.0
//
// FileTypeIcon — colored icons for dense file views.
//
// Maps common extensions to a calm palette (Swift orange, JSON yellow,
// Markdown grey, folder blue, etc.). Unknown extensions fall back to a
// neutral document icon.

import SwiftUI

struct FileTypeIcon: View {
    let filename: String
    var isFolder: Bool = false
    var size: CGFloat = 14

    private var ext: String {
        (filename as NSString).pathExtension.lowercased()
    }

    private var spec: (symbol: String, color: Color) {
        if isFolder { return ("folder.fill", ManifoldPalette.claude) }

        switch ext {
        case "swift":                          return ("swift", Color(red: 0.95, green: 0.36, blue: 0.18))
        case "json":                           return ("curlybraces", Color(red: 0.95, green: 0.75, blue: 0.10))
        case "md", "markdown":                 return ("text.alignleft", ManifoldPalette.text3)
        case "yaml", "yml", "toml", "conf":    return ("gearshape.2", ManifoldPalette.text2)
        case "ts", "tsx", "js", "jsx":         return ("chevron.left.forwardslash.chevron.right", Color(red: 0.32, green: 0.63, blue: 0.88))
        case "py":                              return ("chevron.left.slash.chevron.right", Color(red: 0.18, green: 0.42, blue: 0.78))
        case "rs":                              return ("gearshape", Color(red: 0.85, green: 0.40, blue: 0.20))
        case "go":                              return ("arrow.triangle.branch", Color(red: 0.20, green: 0.65, blue: 0.80))
        case "c", "cpp", "h", "hpp", "m", "mm":return ("curlybraces", ManifoldPalette.text2)
        case "html", "css", "scss":             return ("globe", ManifoldPalette.codex)
        case "txt":                             return ("doc.text", ManifoldPalette.text3)
        case "pdf":                             return ("doc.richtext", ManifoldPalette.danger)
        case "png", "jpg", "jpeg", "heic", "webp", "gif":
            return ("photo", Color(red: 0.25, green: 0.75, blue: 0.50))
        case "mov", "mp4", "m4v":               return ("film", ManifoldPalette.codex)
        case "mp3", "m4a", "wav", "flac":      return ("waveform", ManifoldPalette.active)
        case "zip", "tar", "gz", "bz2", "7z":  return ("archivebox", ManifoldPalette.paused)
        case "env", "pem", "key":              return ("key.fill", ManifoldPalette.danger)
        case "log":                             return ("scroll", ManifoldPalette.text2)
        case "sh", "bash", "zsh":              return ("terminal", ManifoldPalette.text2)
        case "sql":                             return ("cylinder.split.1x2", ManifoldPalette.codex)
        default:                                return ("doc", ManifoldPalette.text3)
        }
    }

    var body: some View {
        Image(systemName: spec.symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(spec.color)
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

#Preview("File type icons") {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: Spacing.s3) {
        Group {
            labeledIcon("Main.swift")
            labeledIcon("package.json")
            labeledIcon("README.md")
            labeledIcon("config.yaml")
            labeledIcon("server.ts")
            labeledIcon("model.py")
            labeledIcon("index.html")
            labeledIcon("build.log")
            labeledIcon("lib.rs")
            labeledIcon("photo.png")
            labeledIcon("demo.mov")
            labeledIcon("song.m4a")
            labeledIcon("archive.zip")
            labeledIcon(".env")
            labeledIcon("Projects", isFolder: true)
        }
    }
    .padding(Spacing.s6)
    .frame(width: 560)
    .background(ManifoldPalette.bg)
}

@ViewBuilder
private func labeledIcon(_ name: String, isFolder: Bool = false) -> some View {
    HStack(spacing: Spacing.s2) {
        FileTypeIcon(filename: name, isFolder: isFolder)
        Text(name)
            .font(ManifoldType.mono)
            .foregroundStyle(ManifoldPalette.text2)
    }
}
