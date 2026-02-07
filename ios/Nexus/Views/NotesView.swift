import SwiftUI
import os

struct NotesView: View {
    @State private var notes: [Note] = []
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var allTags: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "notes")

    var body: some View {
        Group {
            if isLoading && notes.isEmpty {
                ProgressView("Loading notes...")
            } else if let error = errorMessage, notes.isEmpty {
                errorView(error)
            } else if notes.isEmpty && searchText.isEmpty && selectedTag == nil {
                emptyView
            } else {
                notesList
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search notes...")
        .onChange(of: searchText) { _, _ in
            Task { await searchNotes() }
        }
        .refreshable {
            await loadNotes()
        }
        .task {
            await loadNotes()
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        List {
            // Tags filter section
            if !allTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allTags, id: \.self) { tag in
                                TagChip(
                                    tag: tag,
                                    isSelected: selectedTag == tag,
                                    onTap: {
                                        if selectedTag == tag {
                                            selectedTag = nil
                                        } else {
                                            selectedTag = tag
                                        }
                                        Task { await searchNotes() }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // Notes
            if filteredNotes.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("No notes match your search")
                    )
                }
            } else {
                Section(noteSectionHeader) {
                    ForEach(filteredNotes) { note in
                        NoteRow(note: note)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var noteSectionHeader: String {
        if let tag = selectedTag {
            return "Tagged: #\(tag)"
        } else if !searchText.isEmpty {
            return "Results"
        }
        return "Recent Notes"
    }

    private var filteredNotes: [Note] {
        notes
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Notes Indexed", systemImage: "doc.text")
        } description: {
            Text("Run the Obsidian indexer to sync your notes")
        } actions: {
            Button("Refresh") {
                Task { await loadNotes() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                Task { await loadNotes() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - API

    private func loadNotes() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NexusAPI.shared.searchNotes(limit: 100)
            notes = response.notes
            extractTags()
            logger.info("Loaded \(response.count) notes")
        } catch {
            if notes.isEmpty {
                errorMessage = error.localizedDescription
            }
            logger.error("Failed to load notes: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func searchNotes() async {
        isLoading = true

        do {
            let response = try await NexusAPI.shared.searchNotes(
                query: searchText.isEmpty ? nil : searchText,
                tag: selectedTag,
                limit: 100
            )
            notes = response.notes
            logger.info("Search returned \(response.count) notes")
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func extractTags() {
        var tagSet = Set<String>()
        for note in notes {
            if let tags = note.tags {
                tags.forEach { tagSet.insert($0) }
            }
        }
        allTags = Array(tagSet).sorted()
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.nexusPrimary.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: noteIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.nexusPrimary)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let folder = note.folder {
                        Label(folder, systemImage: "folder")
                    }

                    if let wordCount = note.wordCount {
                        Label("\(wordCount) words", systemImage: "text.word.spacing")
                    }

                    if let relativeDate = note.relativeDate {
                        Text(relativeDate)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

                // Tags
                if let tags = note.tags, !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.nexusPrimary.opacity(0.1))
                                .foregroundColor(.nexusPrimary)
                                .clipShape(Capsule())
                        }
                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var noteIcon: String {
        if let folder = note.folder?.lowercased() {
            if folder.contains("project") { return "folder.fill" }
            if folder.contains("daily") || folder.contains("journal") { return "calendar" }
            if folder.contains("work") { return "briefcase.fill" }
            if folder.contains("learn") || folder.contains("study") { return "book.fill" }
            if folder.contains("idea") { return "lightbulb.fill" }
        }
        return "doc.text.fill"
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("#\(tag)")
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.nexusPrimary : Color.nexusPrimary.opacity(0.1))
                .foregroundColor(isSelected ? .white : .nexusPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        NotesView()
    }
}
