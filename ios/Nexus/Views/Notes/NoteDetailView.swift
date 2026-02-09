import SwiftUI

/// Detail view showing note metadata and content
struct NoteDetailView: View {
    let note: Note
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexusTheme.Spacing.lg) {
                // Header with folder path
                if let folder = note.folder {
                    HStack(spacing: NexusTheme.Spacing.xs) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                        Text(folder)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(NexusTheme.Colors.textTertiary)
                }

                // Full path
                Text(note.relativePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(NexusTheme.Colors.textMuted)

                // Tags
                if let tags = note.tags, !tags.isEmpty {
                    tagsSection(tags)
                }

                // Metadata row
                metadataRow

                Divider()

                // Content section
                contentSection
            }
            .padding(NexusTheme.Spacing.xl)
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onEdit()
                } label: {
                    Text("Edit")
                }
            }
        }
    }

    // MARK: - Tags Section

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.xs) {
            Text("Tags")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NexusTheme.Colors.textTertiary)
                .textCase(.uppercase)

            FlowLayout(spacing: NexusTheme.Spacing.xs) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, NexusTheme.Spacing.sm)
                        .padding(.vertical, NexusTheme.Spacing.xxs)
                        .background(NexusTheme.Colors.accent.opacity(0.12))
                        .foregroundColor(NexusTheme.Colors.accent)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: NexusTheme.Spacing.lg) {
            if let wordCount = note.wordCount {
                metadataItem(icon: "text.word.spacing", value: "\(wordCount)", label: "words")
            }

            if let relativeDate = note.relativeDate {
                metadataItem(icon: "clock", value: relativeDate, label: "modified")
            }

            Spacer()
        }
    }

    private func metadataItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: NexusTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(NexusTheme.Colors.textTertiary)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textPrimary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
            }
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: NexusTheme.Spacing.md) {
            Text("Content")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NexusTheme.Colors.textTertiary)
                .textCase(.uppercase)

            // Content not synced - show placeholder
            VStack(spacing: NexusTheme.Spacing.md) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundColor(NexusTheme.Colors.textMuted)

                Text("Content not synced")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NexusTheme.Colors.textSecondary)

                Text("Note content lives in your Obsidian vault.\nOnly metadata is indexed for search.")
                    .font(.system(size: 12))
                    .foregroundColor(NexusTheme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(NexusTheme.Spacing.xxl)
            .background(NexusTheme.Colors.card)
            .cornerRadius(NexusTheme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: NexusTheme.Radius.card)
                    .stroke(NexusTheme.Colors.divider, lineWidth: 1)
            )
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        NoteDetailView(
            note: Note(
                noteId: 1,
                relativePath: "Projects/LifeOS.md",
                title: "LifeOS",
                tags: ["project", "active", "ios", "swift"],
                wordCount: 1500,
                fileModifiedAt: "2026-02-08T10:00:00Z",
                indexedAt: "2026-02-08T11:00:00Z"
            ),
            onEdit: {}
        )
    }
}
